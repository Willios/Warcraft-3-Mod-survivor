using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class WarcraftSurvivorsLauncher
{
    [STAThread]
    private static void Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string runtime = Path.Combine(root, "OpenRealm");
        string engine = Path.Combine(runtime, "openwarcraft3.exe");
        string data = Path.Combine(root, "Data");

        if (!File.Exists(engine))
        {
            MessageBox.Show("The OpenRealm runtime is missing. Rebuild or restore the OpenRealm folder.",
                "Warcraft Survivors", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        if (!Directory.Exists(data))
        {
            MessageBox.Show("The Data folder is missing. Restore it beside WarcraftSurvivors.exe.",
                "Warcraft Survivors", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        string arguments = "-data \"" + data + "\" -tft " +
            "+set vid_fullscreen 2 +set vid_native 1 " +
            "+set wc3_loading_quiet 1 +set scr_showfps 0 " +
            "+set wc3_lua_script \"Scripts/Survivor/ashenvale_survivor.lua," +
            "Scripts/Survivor/engine_boot.lua\" " +
            "+map \"Maps/FrozenThrone/(6)Moonglade.w3x\"";

        try
        {
            Process.Start(new ProcessStartInfo
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
                "Warcraft Survivors", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
