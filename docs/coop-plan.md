# Co-op plan (not started)

Written 2026-10-31. Online co-op for 1 to 5 players, the same on the web build and the portable build,
through a WebSocket relay on the existing VPS. Nothing here is built yet.

## Decisions

- **WebSocket only.** No LAN mode and no Epic Online Services. EOS has no browser SDK and its P2P runs over
  UDP, which a web page cannot open, so it would leave web players out. A WebSocket works from the browser and
  from the desktop build alike.
- **Host-authoritative, like Azeroth Survivors.** The host's game runs the whole run (the engine is already a
  Quake 2 style server with remote clients). Guests send input and receive snapshots. The relay only forwards
  bytes; it never runs the game.
- **The relay runs on the existing OVH VPS** (`ssh yarrr`, Debian 12, 4 vCores / 4 GB), next to the WoW server,
  behind its nginx. A second VPS is added only if real co-op traffic needs it.
- **Downloads stay as they are** (OVH shared hosting for the web data and the portable zip).
- **Balance** (agreed): see below.

## How Azeroth Survivors does it (for reference)

A WebSocket lobby (`wss://wow.aethus.pl/coop/lobby/`, behind Cloudflare) lists lobbies, hosts, joins by code,
checks passwords and the game version, then hands each player a relay ticket (relay address). The relay forwards
game data between the host and its guests; the game runs on the host's PC. Source: the community replacements
[kodfod/azeroth-survivors-coop](https://github.com/kodfod/azeroth-survivors-coop) and
[Whads1985/AzerothSurvivors-COOP-Server](https://github.com/Whads1985/AzerothSurvivors-COOP-Server).

## Architecture

```
 host game (browser or desktop)          VPS: coop.para-bellum.eu (nginx, TLS)          guest games
 engine server + host's client  <--wss-->  lobby + relay (Node, 127.0.0.1)  <--wss-->  engine clients
```

- **Lobby** (JSON messages): list public lobbies of the same version, host (name, description, public or
  private, max players 1-5, optional password, zone, difficulty, host hero), join by code, refresh, leave.
  Returns a relay ticket: relay address + session token. Lobby codes are 6 characters.
- **Relay** (binary messages): `[peer id][engine packet]`. The host's connection talks to every guest; each
  guest's connection talks only to the host.
- **Relay tickets from day one**: the lobby picks the relay, so adding a second relay VPS later is a config
  line, not a code change.
- **Limits** in the relay: connections per IP, lobbies per IP, bytes per second per connection, idle timeout,
  maximum lobbies. A guest that drops keeps their slot 60 s.
- **Version check**: lobbies carry `SURVIVOR_ENGINE.version` and the engine protocol version; the list only
  shows lobbies of the player's own version, and a join from another version is refused.

## Engine work (open-realm fork, branch `survivor`)

1. **Relay transport.** A new address type (`NA_RELAY`, next to `NA_EOS` in `common/net.h`). A WebSocket is
   reliable and ordered, so it takes the existing lossless path EOS uses (no netchan sequence header).
   - Desktop: WinHTTP's WebSocket API (built into Windows, does TLS, no new library).
   - Web: Emscripten's `emscripten/websocket.h` (`-lwebsocket.js`), from the engine's worker thread.
   - `connect relay:<ticket>` on a guest, `relay_host <ticket>` on the host's server.
2. **Per-player UI.** Script frames are currently sent to every client (`UI_WriteScriptFrames` in
   `hud/hud_script_frames.c`) and `GetLocalPlayer()` is always the host (`G_LuaLocalPlayer` in `g_lua.c`).
   Frames need an owning player (e.g. `EngineFrameSetOwner(frame, player)`, `nil` = everyone), and camera and
   UI sound natives need a target player.
3. **Profile handoff.** A guest's profile lives on the guest's PC, but the script only runs on the host.
   - On join, the guest's client sends its loadout (hero, talents, gear, starting spell, perks) to the host.
   - At the end of the run, the host sends the guest its rewards; a new server-to-client message makes the
     guest's client write them into its own `profile.pld`.
4. **Map flow.** Each player sits on their own local menu map. On Start, the host's server changes level to
   the zone; guests drop their local server and connect to the host through the relay. On the end screen,
   everyone goes back to their own menu map.
5. **Guest input delay** (measure first, then decide). The engine predicts only the camera, not units. Guest
   delay = relay round trip (40-100 ms in Europe) + up to 100 ms server tick + ~100 ms interpolation. If WASD
   feels sluggish, the guest's client moves its own hero at once and the host's snapshot corrects it.

## Script work (`src/ashenvale_survivor.lua`)

- **Split the run table `R`**: world state (time, zone, difficulty, enemies, spawner, bosses, endless) and one
  table per player (hero, position, stats, spells, cooldowns, buffs, level, xp, card hand, blessings, summons,
  gear, HUD frames). About 400 references to move (`R.hero` 64, `R.hx/hy` 61, `R.stats` 23, `R.hand` 25...).
- **Enemies** target the nearest living hero; spawns are placed around all heroes.
- **Level-ups do not pause** in co-op: each player picks their own cards while the run goes on, with a 3 s
  shield while the hand is open. The Escape menu does not pause either.
- **Downed, not dead**: a downed hero is revived by a teammate standing next to it for 3 s. The run is lost
  when every hero is down.
- **Lobby UI** in our WC3 style: a Co-op button next to Enter Zone, with Lobbies (list + filters: can join,
  no password, zone, difficulty), Host (name, description, public/private, max players, password) and Join by
  code (code + password). Everyone who joins needs the host's zone and difficulty open with their hero.

## Balance (n = number of players)

| Rule | Value | 2 players | 5 players |
|---|---|---|---|
| Horde size (spawn rate and alive cap) | x(1 + 0.5(n-1)) | x1.5 | x3 |
| Enemy health | x(1 + 0.12(n-1)) | x1.12 | x1.48 |
| Enemy damage | x(1 + 0.04(n-1)) | x1.04 | x1.16 |
| Boss and elite health | x(1 + 0.6(n-1)) | x1.6 | x3.4 |
| Experience | shared by the party, everyone levels together | | |
| Gold | everyone gets all of it | | |

All in one `CFG.COOP` table. The alive cap (`MAX_ENEMIES`, 150 solo) would reach 450 at 5 players: measure
the server and snapshot cost first, and lower the multiplier or the cap if needed.

## Testing

- Relay on `127.0.0.1`, two or more hidden engine processes (`vid_hidden 1`, `s_volume 0`) joined through cvar
  test aids (`+set coop_host ...`, `+set coop_join <code>`), with `survivor_autopick` and a keep-alive add-on.
  Log snapshot sizes and guest input-to-movement delay.
- Then the web build in headless Chrome against the same local relay (host in the browser, guest native, and
  the reverse).
- Then the VPS, with the user and a friend.
- Back up the real profile before every run (guests save rewards too).

## Resources (estimates until snapshot sizes are measured)

Solo play never touches the server. Assumed: lobbies of 3 on average (2 guests on the relay), 0.25-0.65 Mbit/s
of relay traffic per guest. The relay itself needs about 50 MB of RAM and a few percent of one core. Bandwidth
is the only thing that grows.

| | Worst case: all online at once, all in co-op | Realistic peak for a community of that size |
|---|---|---|
| 500 players | ~330 guests, 80-210 Mbit/s, 1 relay VPS | 20-40 in co-op, 5-20 Mbit/s, current VPS |
| 1,500 players | ~1,000 guests, 250-650 Mbit/s, 2-3 relay VPSes | 60-120 in co-op, 15-50 Mbit/s, current VPS or 1 small one |
| 3,000 players | ~2,000 guests, 0.5-1.3 Gbit/s, 3-6 relay VPSes (~20-35 EUR/month) | 120-240 in co-op, 30-100 Mbit/s, 1 dedicated VPS |

On the WoW VPS: the relay runs as its own systemd service and user with `MemoryMax=150M` and a `CPUQuota`, so a
problem kills the relay, not the worldserver (RAM is the tight resource there: the worldserver may use up to
3 GB). nginx proxies `coop.para-bellum.eu` to it, with a certificate from the existing certbot. Move the relay to
its own VPS once co-op passes a couple of hundred players at once.

For comparison, downloads (kept on the shared hosting): each new web player fetches the 199 MB data once,
about 100 GB per 500 new players.

## Order and size

| Step | What | Size |
|---|---|---|
| 1 | Relay and lobby server (Node), run locally | Small |
| 2 | Engine relay transport, desktop: two local processes in the same run | Medium |
| 3 | Per-player frames and `GetLocalPlayer` in the engine | Medium |
| 4 | Script split into world and per-player state, balance table, revive | Large |
| 5 | Measure guest delay and snapshot size; hero prediction if needed | Medium |
| 6 | Profile handoff (loadout in, rewards out) | Medium |
| 7 | Lobby UI | Medium |
| 8 | Web transport, headless browser test | Small-Medium |
| 9 | VPS deployment (service, nginx, certificate, limits) and a real test with a friend | Small |

## Open questions

- Host leaves mid-run: v1 ends the run for everyone. Do guests keep the gold and kills earned so far?
- Do guests unlock the next zone by winning in the host's zone (only if they already had it open)?
- Endless mode in co-op: the host decides, or a vote?
- Late join into a running run: not in v1.
