# Cyberpunk 2077 VR Port — automatic installer

Installs [cyberpunk-vr-port](https://www.nexusmods.com/cyberpunk2077/mods/30093) and all of
its required dependencies into your Cyberpunk 2077 folder.

## How to use it

1. Put all the files in this folder anywhere you like (Desktop is fine).
2. Double-click **`Install Cyberpunk VR.bat`**.
3. Answer the prompts.

That's it. If your game lives under `Program Files`, right-click the `.bat` and choose
**Run as administrator** instead.

## What it does

**Downloads automatically from GitHub — no account, no login:**

| Component | Source |
|---|---|
| RED4ext | `WopsS/RED4ext` |
| Cyber Engine Tweaks | `maximegmd/CyberEngineTweaks` |
| redscript | `jac3km4/redscript` |
| TweakXL | `psiberx/cp2077-tweak-xl` |
| ArchiveXL | `psiberx/cp2077-archive-xl` |
| Codeware | `psiberx/cp2077-codeware` |
| Equipment-EX | `psiberx/cp2077-equipment-ex` |
| **Cyberpunk VR Port** | `dariulone/cyberpunk-vr-port` |

It always grabs the **latest release** of each, so re-running the script updates everything.

**Three mods live only on Nexus** and need a hand:

- [Visual Holsters](https://www.nexusmods.com/cyberpunk2077/mods/21936) (mod 21936)
- [Visible Bullets](https://www.nexusmods.com/cyberpunk2077/mods/22251) (mod 22251)
- [Nova Optics](https://www.nexusmods.com/cyberpunk2077/mods/29190) (mod 29190)

**Being logged into Nexus in your browser is not enough to automate these.** Nexus only
issues direct download links through its API to **Premium** accounts; free accounts have to
click the download button on the site. So the script handles it three ways, in this order:

1. **`ManualDownloads` folder** — if you've already downloaded any of the three, drop the
   archives in a folder called `ManualDownloads` next to the script and it installs them
   without asking.
2. **Nexus Premium** — pass your API key and all three download automatically.
3. **Browser handoff (default, works for free accounts)** — the script opens each mod page,
   you click *Manual Download → Slow download*, and it picks the archive out of your
   Downloads folder and installs it. You just press Enter when each download finishes.

## Options

```powershell
# normal run
.\Install-CyberpunkVR.ps1

# Nexus Premium: fully hands-off
.\Install-CyberpunkVR.ps1 -NexusApiKey "your-key-here"
# (or set the NEXUS_API_KEY environment variable once and forget it)
# key from: https://next.nexusmods.com/settings/api-keys

# game folder isn't auto-detected
.\Install-CyberpunkVR.ps1 -GamePath "D:\Games\Cyberpunk 2077"

# GitHub components only; print a checklist for the Nexus three
.\Install-CyberpunkVR.ps1 -SkipNexus

# no confirmation prompts
.\Install-CyberpunkVR.ps1 -Force

# put everything back the way it was
.\Install-CyberpunkVR.ps1 -Uninstall
```

## Safety

- Every file it overwrites is copied to `<game>\_CyberpunkVR_Installer\backup-<timestamp>\`
  first.
- Every file it writes is recorded in `<game>\_CyberpunkVR_Installer\manifest.json`.
- `-Uninstall` deletes exactly the files it installed and restores the backed-up originals.
- It checks the game version and warns if you're not on **2.31**, which is what the mod
  targets.
- It deletes any pre-existing `bin\x64\dxgi.dll` (into the backup) before installing, which
  the mod's instructions require when upgrading from an earlier VR build.

Nothing is touched outside your game folder and your Downloads folder.

## After it finishes

The script prints this, but so it's written down:

1. **Launch the game flat (no VR) once.** CET and redscript need one run to finish setting
   themselves up.
2. **Graphics settings → Low**, and turn **off**: Film Grain, Chromatic Aberration, Motion
   Blur, Lens Flare, Depth of Field, Frame Generation.
3. **Start your OpenXR runtime first** (SteamVR, Oculus, Virtual Desktop, WMR…), *then*
   launch the game.
4. Run `bin\x64\Cyberpunk2077.exe` — the launcher lets you pick render resolution and
   runtime.
5. In game: **F10** = VR menu, **F7** = recenter.

## Requirements

- Windows, PowerShell 5.1 or newer (built into Windows 10/11)
- Cyberpunk 2077 **v2.31** on PC
- An OpenXR-capable headset and runtime
- [7-Zip](https://www.7-zip.org) — only needed if one of the Nexus downloads happens to be a
  `.7z` or `.rar`. The script tells you if it hits one.

## Troubleshooting

**"Cannot write to …"** — run the `.bat` as administrator, or move the game out of
`Program Files`.

**A component fails to download** — GitHub rate-limits anonymous API calls to 60/hour. If
you hit it, wait an hour, or set a `GITHUB_TOKEN` environment variable to a personal access
token (no scopes needed).

**Game crashes on launch** — check `<game>\red4ext\logs\` and
`<game>\bin\x64\plugins\cyber_engine_tweaks\cyber_engine_tweaks.log`. The most common cause
is being on a game version other than 2.31.

**Want to start over** — run the uninstaller, verify game files in Steam/GOG, then re-run
the installer.

## Credits

The VR port is by **dariulone** — [Nexus](https://www.nexusmods.com/cyberpunk2077/mods/30093)
· [GitHub](https://github.com/dariulone/cyberpunk-vr-port). This script just automates the
install steps from that page; all the actual work is theirs. Consider endorsing the mod.
