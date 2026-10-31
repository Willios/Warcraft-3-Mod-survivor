// Warcraft Survivors portable launcher (built by make_portable.ps1 with the
// .NET Framework 4 compiler, so C# 5: no string interpolation, no ?.).
//
// Starts the engine on the menu map, then checks for a newer release while the
// game runs. version.json beside this exe lists this build's version and every
// file (path, size, sha1); its "update" URL is the folder of the uploaded
// release's version.json (portable_manifest.py stage). When the uploaded
// version is newer, the launcher tells the game, which shows the update window
// (Updater in src/ashenvale_survivor.lua). They talk through preload files in
// %APPDATA%\warcraft-3\CustomMapData\WarcraftSurvivors\Update, the only files
// the game's script can read:
//   info.pld      launcher -> game: the newer version, its notes and download size
//   request.pld   game -> launcher: Download & restart was pressed
//   progress.pld  launcher -> game: bytes done, then ready or error
// Every file carries a per-session token. Only the files whose sha1 changed
// are downloaded (into .update\, each verified). When the game has quit, the
// old files move to .update-backup\ and the new ones take their place (rolled
// back on failure), then the new launcher starts. Saves live in %APPDATA% and
// are never touched.
//
// Command line: --update-url <folder URL> replaces the URL in version.json (tests);
// everything after -- is passed to the engine (e.g. +set vid_hidden 1).

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal sealed class ManifestFile
{
    public string Path;
    public long Size;
    public string Sha1;
    public string Url;
}

internal sealed class Manifest
{
    public string Version;
    public string Notes;
    public string Update;
    public string Text;
    public List<ManifestFile> Files = new List<ManifestFile>();

    public static Manifest Parse(string text)
    {
        var json = (Dictionary<string, object>)new JavaScriptSerializer { MaxJsonLength = 64 << 20 }.DeserializeObject(text);
        var m = new Manifest();
        m.Text = text;
        m.Version = Get(json, "version");
        m.Notes = Get(json, "notes");
        m.Update = Get(json, "update");
        object files;
        if (json.TryGetValue("files", out files) && files is IEnumerable)
        {
            foreach (object item in (IEnumerable)files)
            {
                var entry = item as Dictionary<string, object>;
                if (entry == null) continue;
                var f = new ManifestFile();
                f.Path = Get(entry, "path");
                f.Sha1 = (Get(entry, "sha1") ?? "").ToLowerInvariant();
                f.Url = Get(entry, "url") ?? f.Path;
                f.Size = Convert.ToInt64(entry.ContainsKey("size") ? entry["size"] : 0, CultureInfo.InvariantCulture);
                if (!string.IsNullOrEmpty(f.Path)) m.Files.Add(f);
            }
        }
        return m;
    }

    private static string Get(Dictionary<string, object> json, string key)
    {
        object value;
        return json.TryGetValue(key, out value) && value != null ? Convert.ToString(value, CultureInfo.InvariantCulture) : null;
    }

    public Dictionary<string, ManifestFile> ByPath()
    {
        var map = new Dictionary<string, ManifestFile>(StringComparer.OrdinalIgnoreCase);
        foreach (var f in Files) map[f.Path] = f;
        return map;
    }
}

internal static class WarcraftSurvivorsLauncher
{
    private const string Title = "Warcraft Survivors";

    private static string root, runtime, engine, data, channel, token, updateUrl;
    private static string engineExtra = "";
    private static string[] launcherArgs;
    private static Manifest local, remote;
    private static List<ManifestFile> changed;
    private static volatile bool ready, engineExited;

    [STAThread]
    private static void Main(string[] args)
    {
        launcherArgs = args;
        root = AppDomain.CurrentDomain.BaseDirectory;
        runtime = Path.Combine(root, "OpenRealm");
        engine = Path.Combine(runtime, "openwarcraft3.exe");
        data = Path.Combine(root, "Data");

        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--update-url" && i + 1 < args.Length)
            {
                updateUrl = args[++i];
            }
            else if (args[i] == "--")
            {
                var rest = new List<string>();
                for (int j = i + 1; j < args.Length; j++) rest.Add(Quote(args[j]));
                engineExtra = " " + string.Join(" ", rest.ToArray());
                break;
            }
        }

        if (!File.Exists(engine))
        {
            MessageBox.Show("The OpenRealm runtime is missing. Rebuild or restore the OpenRealm folder.",
                Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        if (!Directory.Exists(data))
        {
            MessageBox.Show("The Data folder is missing. Restore it beside WarcraftSurvivors.exe.",
                Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        // Left by the previous update: the old launcher could not delete itself.
        TryDeleteDirectory(Path.Combine(root, ".update-backup"));
        TryDeleteDirectory(Path.Combine(root, ".update"));

        string appData = Environment.GetEnvironmentVariable("APPDATA");
        try
        {
            string manifestPath = Path.Combine(root, "version.json");
            if (File.Exists(manifestPath)) local = Manifest.Parse(File.ReadAllText(manifestPath, Encoding.UTF8));
        }
        catch (Exception)
        {
            local = null;
        }
        if (updateUrl == null && local != null) updateUrl = local.Update;
        bool updates = local != null && !string.IsNullOrEmpty(updateUrl) && !string.IsNullOrEmpty(appData);

        string arguments = "-data " + Quote(data) + " -tft " +
            "+set vid_fullscreen 2 +set vid_native 1 " +
            "+set wc3_loading_quiet 1 +set scr_showfps 0 " +
            "+set wc3_lua_script \"Scripts/Survivor/ashenvale_survivor.lua," +
            "Scripts/Survivor/engine_boot.lua\" ";
        if (updates)
        {
            // Same folder the engine's preload files use (APPDATA\warcraft-3, common/main.c).
            channel = Path.Combine(appData, "warcraft-3", "CustomMapData", "WarcraftSurvivors", "Update");
            token = Guid.NewGuid().ToString("N");
            try
            {
                Directory.CreateDirectory(channel);
                foreach (string name in new[] { "info.pld", "request.pld", "progress.pld" })
                    TryDelete(Path.Combine(channel, name));
                arguments += "+set survivor_updater " + token + " ";
            }
            catch (Exception)
            {
                updates = false;
            }
        }
        arguments += "+map \"Maps/FrozenThrone/(6)Moonglade.w3x\"" + engineExtra;

        Process game;
        try
        {
            game = Process.Start(new ProcessStartInfo
            {
                FileName = engine,
                Arguments = arguments,
                WorkingDirectory = runtime,
                UseShellExecute = false
            });
        }
        catch (Exception error)
        {
            MessageBox.Show("Could not start Warcraft Survivors.\r\n\r\n" + error.Message,
                Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        if (!updates || game == null) return;

        ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // TLS 1.2
        var check = new Thread(CheckForUpdate);
        check.IsBackground = true;
        check.Start();

        // Wait for the game, answering its download requests meanwhile.
        Thread download = null;
        while (!game.WaitForExit(250))
        {
            string request = ReadRequest();
            if (request == null || changed == null || (download != null && download.IsAlive)) continue;
            int attempt = 0;
            string[] parts = request.Split(' ');
            if (parts.Length > 1) int.TryParse(parts[1], out attempt);
            int captured = attempt;
            download = new Thread(delegate() { Download(captured); });
            download.IsBackground = true;
            download.Start();
        }
        engineExited = true;
        if (download != null) download.Join();

        foreach (string name in new[] { "info.pld", "request.pld", "progress.pld" })
            TryDelete(Path.Combine(channel, name));
        if (!ready)
        {
            TryDeleteDirectory(Path.Combine(root, ".update"));
            return;
        }
        string failure = Apply();
        if (failure != null)
        {
            MessageBox.Show("The update could not be installed; this version was kept.\r\n\r\n" + failure,
                Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        // The new launcher starts the new game.
        var again = new List<string>();
        foreach (string a in launcherArgs) again.Add(Quote(a));
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = Path.Combine(root, "WarcraftSurvivors.exe"),
                Arguments = string.Join(" ", again.ToArray()),
                WorkingDirectory = root,
                UseShellExecute = false
            });
        }
        catch (Exception error)
        {
            MessageBox.Show("The update is installed but the game could not restart.\r\n\r\n" + error.Message,
                Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // ---- Update check ------------------------------------------------------

    private static void CheckForUpdate()
    {
        string state = "none";
        try
        {
            string text = Encoding.UTF8.GetString(Fetch(Resolve("version.json"), 15000));
            remote = Manifest.Parse(text);
            if (remote.Version != null && CompareVersions(remote.Version, local.Version) > 0)
            {
                var have = local.ByPath();
                var list = new List<ManifestFile>();
                foreach (var f in remote.Files)
                {
                    ManifestFile mine;
                    if (!have.TryGetValue(f.Path, out mine) || mine.Sha1 != f.Sha1 || mine.Size != f.Size
                        || !File.Exists(Target(f.Path)))
                        list.Add(f);
                }
                changed = list;
                state = "update";
            }
        }
        catch (Exception)
        {
            // Offline or no release uploaded yet: play this version.
        }
        long size = 0;
        if (changed != null) foreach (var f in changed) size += f.Size;
        var fields = new List<string>();
        fields.Add("state = " + Lua(state));
        if (changed != null)
        {
            fields.Add("version = " + Lua(remote.Version));
            fields.Add("notes = " + Lua(remote.Notes ?? ""));
            fields.Add("size = " + size.ToString(CultureInfo.InvariantCulture));
            fields.Add("files = " + changed.Count.ToString(CultureInfo.InvariantCulture));
        }
        WriteChannel("info.pld", "SurvivorUpdateInfo", fields);
    }

    // ---- Download ----------------------------------------------------------

    private static void Download(int attempt)
    {
        string staging = Path.Combine(root, ".update");
        long total = 0, done = 0;
        foreach (var f in changed) total += f.Size;
        var clock = Stopwatch.StartNew();
        long lastReport = -1000;
        double speed = 0;
        long speedBytes = 0, speedTime = 0;
        try
        {
            Directory.CreateDirectory(staging);
            byte[] buffer = new byte[1 << 16];
            foreach (var f in changed)
            {
                string file = Path.Combine(staging, f.Path.Replace('/', '\\'));
                Directory.CreateDirectory(Path.GetDirectoryName(file));
                // A file already staged by an earlier attempt of this session is kept.
                if (File.Exists(file) && new FileInfo(file).Length == f.Size && Sha1(file) == f.Sha1)
                {
                    done += f.Size;
                    continue;
                }
                var request = (HttpWebRequest)WebRequest.Create(Resolve(f.Url));
                request.Timeout = 30000;
                request.ReadWriteTimeout = 30000;
                request.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
                using (var response = request.GetResponse())
                using (var input = response.GetResponseStream())
                using (var output = File.Create(file))
                {
                    int n;
                    while ((n = input.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        if (engineExited) throw new OperationCanceledException();
                        output.Write(buffer, 0, n);
                        done += n;
                        long now = clock.ElapsedMilliseconds;
                        if (now - lastReport >= 200)
                        {
                            if (now - speedTime >= 1000)
                            {
                                double rate = (done - speedBytes) * 1000.0 / Math.Max(1, now - speedTime);
                                speed = speed <= 0 ? rate : speed * 0.6 + rate * 0.4;
                                speedBytes = done;
                                speedTime = now;
                            }
                            lastReport = now;
                            Progress(attempt, "downloading", Math.Min(done, total), total, (long)speed, null);
                        }
                    }
                }
                if (new FileInfo(file).Length != f.Size || Sha1(file) != f.Sha1)
                    throw new IOException(f.Path + " arrived damaged. Try again.");
            }
            ready = true;
            Progress(attempt, "ready", total, total, 0, null);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception error)
        {
            Progress(attempt, "error", done, total, 0, error.Message);
        }
    }

    private static void Progress(int attempt, string state, long done, long total, long speed, string error)
    {
        var fields = new List<string>();
        fields.Add("attempt = " + attempt.ToString(CultureInfo.InvariantCulture));
        fields.Add("state = " + Lua(state));
        fields.Add("done = " + done.ToString(CultureInfo.InvariantCulture));
        fields.Add("total = " + total.ToString(CultureInfo.InvariantCulture));
        fields.Add("speed = " + speed.ToString(CultureInfo.InvariantCulture));
        if (error != null) fields.Add("error = " + Lua(error));
        WriteChannel("progress.pld", "SurvivorUpdateProgress", fields);
    }

    // ---- Install -----------------------------------------------------------

    // Moves the staged files in; every replaced or removed file goes to
    // .update-backup first, so a failure puts the old build back.
    private static string Apply()
    {
        string staging = Path.Combine(root, ".update");
        string backup = Path.Combine(root, ".update-backup");
        var moved = new List<KeyValuePair<string, string>>(); // target, backup copy (null: was new)
        try
        {
            TryDeleteDirectory(backup);
            Directory.CreateDirectory(backup);
            var keep = remote.ByPath();
            var work = new List<KeyValuePair<string, string>>(); // target, staged file (null: remove)
            foreach (var f in changed)
                work.Add(new KeyValuePair<string, string>(Target(f.Path), Path.Combine(staging, f.Path.Replace('/', '\\'))));
            foreach (var f in local.Files)
                if (!keep.ContainsKey(f.Path)) work.Add(new KeyValuePair<string, string>(Target(f.Path), null));

            foreach (var item in work)
            {
                string target = item.Key;
                string saved = null;
                if (File.Exists(target))
                {
                    saved = Path.Combine(backup, moved.Count.ToString(CultureInfo.InvariantCulture));
                    MoveWithRetry(target, saved);
                }
                moved.Add(new KeyValuePair<string, string>(target, saved));
                if (item.Value != null)
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    MoveWithRetry(item.Value, target);
                }
            }
            File.WriteAllText(Path.Combine(root, "version.json"), remote.Text, new UTF8Encoding(false));
        }
        catch (Exception error)
        {
            for (int i = moved.Count - 1; i >= 0; i--)
            {
                try
                {
                    if (File.Exists(moved[i].Key)) File.Delete(moved[i].Key);
                    if (moved[i].Value != null) File.Move(moved[i].Value, moved[i].Key);
                }
                catch (Exception)
                {
                }
            }
            return error.Message;
        }
        TryDeleteDirectory(staging);
        // Holds the running launcher; the next start deletes it.
        TryDeleteDirectory(backup);
        return null;
    }

    private static void MoveWithRetry(string from, string to)
    {
        for (int i = 0; ; i++)
        {
            try
            {
                File.Move(from, to);
                return;
            }
            catch (IOException)
            {
                // The engine's files can stay locked for a moment after it exits.
                if (i >= 20) throw;
                Thread.Sleep(250);
            }
        }
    }

    // ---- Helpers -----------------------------------------------------------

    private static string Target(string path)
    {
        string full = Path.GetFullPath(Path.Combine(root, path.Replace('/', '\\')));
        if (!full.StartsWith(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase))
            throw new IOException("Refused path " + path);
        return full;
    }

    // A manifest URL, relative to the update folder, one escaped segment at a time.
    private static Uri Resolve(string relative)
    {
        string folder = updateUrl.EndsWith("/") ? updateUrl : updateUrl + "/";
        var parts = relative.Split('/');
        for (int i = 0; i < parts.Length; i++)
            if (parts[i] != ".." && parts[i] != ".") parts[i] = Uri.EscapeDataString(parts[i]);
        return new Uri(new Uri(folder), string.Join("/", parts));
    }

    private static byte[] Fetch(Uri url, int timeout)
    {
        var request = (HttpWebRequest)WebRequest.Create(url);
        request.Timeout = timeout;
        request.ReadWriteTimeout = timeout;
        request.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
        request.CachePolicy = new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
        using (var response = request.GetResponse())
        using (var input = response.GetResponseStream())
        using (var memory = new MemoryStream())
        {
            input.CopyTo(memory);
            return memory.ToArray();
        }
    }

    private static string Sha1(string file)
    {
        using (var sha = SHA1.Create())
        using (var stream = File.OpenRead(file))
        {
            var sb = new StringBuilder();
            foreach (byte b in sha.ComputeHash(stream)) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
    }

    private static int CompareVersions(string a, string b)
    {
        string[] x = (a ?? "0").Split('.'), y = (b ?? "0").Split('.');
        for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
        {
            int p = 0, q = 0;
            if (i < x.Length) int.TryParse(x[i], out p);
            if (i < y.Length) int.TryParse(y[i], out q);
            if (p != q) return p.CompareTo(q);
        }
        return 0;
    }

    // request.pld holds "<token> <attempt>"; it is consumed once read whole
    // (the game may still be writing it).
    private static string ReadRequest()
    {
        string path = Path.Combine(channel, "request.pld");
        try
        {
            if (!File.Exists(path)) return null;
            string text = File.ReadAllText(path);
            int at = text.IndexOf(token, StringComparison.Ordinal);
            int end = at < 0 ? -1 : text.IndexOf('"', at);
            if (end < 0) return null;
            File.Delete(path);
            return text.Substring(at, end - at);
        }
        catch (Exception)
        {
            return null;
        }
    }

    // A preload file whose Lua block sets one global table (read by Preloader).
    private static void WriteChannel(string name, string global, List<string> fields)
    {
        fields.Insert(0, "token = " + Lua(token));
        string text = "function PreloadFiles takes nothing returns nothing\n//!beginusercode\n"
            + global + " = {" + string.Join(", ", fields.ToArray()) + "}\n//!endusercode\nendfunction\n";
        string path = Path.Combine(channel, name);
        string temp = path + ".tmp";
        for (int i = 0; i < 20; i++)
        {
            try
            {
                File.WriteAllText(temp, text, new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temp, path, null);
                else File.Move(temp, path);
                return;
            }
            catch (IOException)
            {
                // The game may be reading the old copy.
                Thread.Sleep(20);
            }
            catch (UnauthorizedAccessException)
            {
                Thread.Sleep(20);
            }
        }
    }

    private static string Lua(string s)
    {
        var sb = new StringBuilder("\"");
        foreach (char c in s ?? "")
        {
            if (c == '\\') sb.Append("\\\\");
            else if (c == '"') sb.Append("\\\"");
            else if (c == '\n') sb.Append("\\n");
            else if (c == '\r') continue;
            else if (c < ' ') sb.Append(' ');
            else sb.Append(c);
        }
        return sb.Append('"').ToString();
    }

    private static string Quote(string s)
    {
        if (s.Length > 0 && s.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return s;
        return "\"" + s.Replace("\"", "\\\"") + "\"";
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception)
        {
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path)) Directory.Delete(path, true);
        }
        catch (Exception)
        {
        }
    }
}
