# Cyberpunk 2077 VR Port (v0.2.1+) — Automatic Installer

Installs [dariulone's cyberpunk-vr-port](https://www.nexusmods.com/cyberpunk2077/mods/30093) (`v0.2.1+`) and all of its required dependencies into your **Cyberpunk 2077 (v2.5)** folder.

## How to use it

1. Put all the files in this folder anywhere you like (Desktop is fine).
2. Double-click **`Install Cyberpunk VR.bat`**.
3. Answer the prompts.

That's it. If your game lives under `Program Files`, right-click the `.bat` and choose **Run as administrator** instead.

## What it does

### 1. Cleans up legacy VR Port files (`<= 0.1.9`)
Starting with `v0.2.0` / `v0.2.1`, the VR Port lives inside a single self-contained plugin folder (`red4ext\plugins\cyberpunkvrport\`). If older folders (`red4ext\plugins\CyberpunkVR_Stereo`, `red4ext\plugins\CyberpunkVR_Hands`, `bin\x64\dxgi.dll`, legacy `r6\scripts\CyberpunkVRPort_*`, `r6\tweaks\vrport`, or old `.archive` files in `archive\pc\mod\`) are left behind, they will conflict with or disable the new plugin. The installer automatically backs up and removes those retired paths (while migrating your `vrik_calibration.ini` if present).

### 2. Downloads automatically from GitHub — no account, no login

| Component | Source | Notes |
|---|---|---|
| **RED4ext** (`1.31.0+`) | `WopsS/RED4ext` | Required by the VR Port plugin |
| **Cyber Engine Tweaks** (`1.38.0+`) | `maximegmd/CyberEngineTweaks` | Used by companion mods (skipped in `-Minimal` mode) |
| **redscript** (`0.5.32+`) | `jac3km4/redscript` | Used by companion mods (skipped in `-Minimal` mode) |
| **TweakXL** (`1.12.0+`) | `psiberx/cp2077-tweak-xl` | Used by companion mods (skipped in `-Minimal` mode) |
| **ArchiveXL** (`1.28.0+`) | `psiberx/cp2077-archive-xl` | Used by companion mods (skipped in `-Minimal` mode) |
| **Codeware** (`1.21.0+`) | `psiberx/cp2077-codeware` | Used by companion mods (skipped in `-Minimal` mode) |
| **Input Loader** (`0.2.6+`) | `jackhumbert/cyberpunk2077-input-loader` | Used by companion mods (skipped in `-Minimal` mode) |
| **Equipment-EX** | `psiberx/cp2077-equipment-ex` | Required for Visual Holsters & VR wardrobe |
| **Cyberpunk VR Port** (`0.2.1+`) | `dariulone/cyberpunk-vr-port` | Core VR plugin, shaders, assets, Lua & script modules |

### 3. Installs the three Nexus-only companion mods

- [Visual Holsters (Automatic Clothes Swap)](https://www.nexusmods.com/cyberpunk2077/mods/21936) (Mod `21936`)
- [Nova Optics](https://www.nexusmods.com/cyberpunk2077/mods/29190) (Mod `29190`)
- [More Occluders (Scripted v0.3)](https://www.nexusmods.com/cyberpunk2077/mods/33136) (Mod `33136` — replaces the retired *Visible Bullets* mod)

Because Nexus only issues direct API download links to **Premium** accounts, the script handles these three mods in three ways (in order):

1. **`ManualDownloads` folder** — drop any pre-downloaded archives into a `ManualDownloads` folder next to the script and it installs them automatically without asking.
2. **Nexus Premium** — pass `-NexusApiKey` (or set `NEXUS_API_KEY`) and all three download automatically.
3. **Browser handoff (default for free accounts)** — the script opens each mod page, you click *Manual Download → Slow download*, and it picks the archive out of your `Downloads` folder and installs it.

> **Standalone / Minimal Mode (`-Minimal`)**: Since `v0.2.0`, `cyberpunkvrport.dll` embeds its own LuaJIT host, redscript compiler (`scc_lib.dll`), archive mounter, TweakDB loader, and input merger. If you run `.\Install-CyberpunkVR.ps1 -Minimal`, the script installs **only `RED4ext` and `Cyberpunk VR Port`** from GitHub—completely hands-off with zero Nexus downloads.

## Options

```powershell
# Normal full install (recommended)
.\Install-CyberpunkVR.ps1

# Nexus Premium: 100% hands-off full install
.\Install-CyberpunkVR.ps1 -NexusApiKey "your-key-here" -Force

# Minimal standalone install (RED4ext + Cyberpunk VR Port 0.2.1 only, no Nexus mods needed)
.\Install-CyberpunkVR.ps1 -Minimal

# Specify game folder manually
.\Install-CyberpunkVR.ps1 -GamePath "D:\Games\Cyberpunk 2077"

# GitHub components only; skip the three Nexus mods
.\Install-CyberpunkVR.ps1 -SkipNexus

# Uninstall everything and restore backups
.\Install-CyberpunkVR.ps1 -Uninstall
```

## Safety

- Refuses to run while `Cyberpunk2077.exe` is running so locked DLLs and settings files are never corrupted.
- Every file it overwrites or retires is backed up to `<game>\_CyberpunkVR_Installer\backup-<timestamp>\`.
- Every file it writes is recorded in `<game>\_CyberpunkVR_Installer\manifest.json`.
- `-Uninstall` removes all installed files, cleans up runtime VR Port configs/logs, restores backed-up files, and offers to restore your pre-VR `UserSettings.json` (`UserSettings.pre-vr-*.json`).
- Checks your executable version and warns if you are not on **Cyberpunk 2077 v2.5** (`2.31` is no longer supported by `v0.1.9+`).

## After it finishes

1. **Start your OpenXR runtime first** (Virtual Desktop VDXR, SteamVR, Meta Quest Link, etc.), *then* launch `bin\x64\Cyberpunk2077.exe`.
2. In the **pre-launch VR window**, select your headset preset and per-eye render resolution (leave `DEBUG` unchecked for normal gameplay).
3. **First launch**: The VR Port automatically merges its VR graphics/input/HUD preset into `%LOCALAPPDATA%\CD Projekt Red\Cyberpunk 2077\UserSettings.json` (backing up your original file as `UserSettings.pre-vr-*.json`) and launches into the **3D VR Lobby**, where you pick your weapon hand, T-pose, and height.
4. **In-game hotkeys & shortcuts**:
   - **Hold `L3 + R3` (0.5 s)**: Open / close the holographic VR menu (inventory, map, settings, wardrobe).
   - **Hold `L3 + Left Grip` (0.5 s)**: Activate cyberware OS (Sandevistan, Berserk, Overclock).
   - **`F10` / `Insert`**: Toggle the in-headset VR settings overlay.
   - **`F7`**: Recenter HMD view.
   - **`Home` (or `Scroll Lock` when CET is installed)**: Toggle the VR Port's Lua mod windows.

## Requirements

- Windows 10/11, PowerShell 5.1 or newer
- **Cyberpunk 2077 v2.5** on PC (Steam, GOG, or Epic)
- An OpenXR-capable VR headset and runtime
- [7-Zip](https://www.7-zip.org) — only needed if a Nexus download is packaged as `.7z` or `.rar`

## Credits

The VR port is created by **dariulone** — [Nexus Mods](https://www.nexusmods.com/cyberpunk2077/mods/30093) · [GitHub](https://github.com/dariulone/cyberpunk-vr-port). Original auto-installer by **no6969el**, updated for Cyberpunk 2077 v2.5 and VR Port v0.2.1+.
