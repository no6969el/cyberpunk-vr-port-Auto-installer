# Cyberpunk 2077 VR Port (v0.2.2+) — Automatic Installer

Installs [dariulone's cyberpunk-vr-port](https://www.nexusmods.com/cyberpunk2077/mods/30093) (`v0.2.2+`) and all of its dependencies into your **Cyberpunk 2077 (v2.5)** folder.

## How to use it

1. Put all the files in this folder anywhere you like (Desktop is fine).
2. Double-click **`Install Cyberpunk VR.bat`**.
3. Answer the prompts.

That's it. If your game lives under `Program Files`, right-click the `.bat` and choose **Run as administrator** instead.

---

## Seamless Upgrade from v0.2.1 (and older versions)

If you already installed `v0.2.1` or older releases, simply run **`Install Cyberpunk VR.bat`** over your current installation. The installer handles the upgrade automatically:

- **Fixes Redscript Compilation on Cyberpunk 2.5**: Earlier installers installed *More Occluders (Scripted v0.3)* (`r6\scripts\MoreOccluders.reds`), which fails to compile on Cyberpunk 2.5 and disables all redscript mods. The installer detects, backs up, and removes More Occluders so redscript compiles cleanly.
- **Retires Superseded Visual Holsters**: Cleans up older *Visual Holsters* files so they do not conflict or clip with the new native immersive holsters introduced in `v0.2.2`.
- **Cleans Legacy Folders**: Retires old `<= 0.1.9` files (`CyberpunkVR_Stereo`, `CyberpunkVR_Hands`, `bin\x64\dxgi.dll`, legacy `r6\scripts\CyberpunkVRPort_*`, etc.).
- **Preserves Your Calibration**: Keeps your existing `vrik_calibration.ini`, weapon-hand configuration, and launcher preferences intact.

---

## What's New in VR Port v0.2.2

- **Zero Required Nexus Downloads**: *Visual Holsters*, *Equipment-EX*, *Nova Optics*, and *More Occluders* are **no longer required**! The VR Port now provides native holsters, native optics, and belt slots directly.
- **Native Immersive Holsters**: Every equipped weapon hangs naturally on V's body (pistols on hips/thighs/chest, blades at hip, long guns over shoulders or across the back). Reach with your hand and grip to draw; stow naturally by reaching back to the holster.
- **Single-Pass Stereo**: G-buffer draws for both eyes are submitted as a single view-instanced draw using the bundled DirectX shader compiler (`dxc\dxcompiler.dll`), saving ~2.5 ms of CPU driver time per frame.
- **Hands Only Option**: Play with V's hands alone (cut and capped at wrists) with belt and wrist screen preserved, transitioning cleanly in cutscenes.
- **Full-Body & Finger Tracking**: Support for SteamVR Vive Trackers (waist + feet) and OpenXR hand/finger tracking.
- **Combat & Movement Improvements**: Aiming down sights and melee blocking no longer slow V to a crawl; left stick click sprint mode; 1:1 responsive car steering.

---

## What it installs

### 1. From GitHub (100% Fully Automatic — No Login Needed)

| Component | Source | Purpose |
|---|---|---|
| **RED4ext** (`1.31.0+`) | `WopsS/RED4ext` | Core plugin loader required by Cyberpunk VR Port |
| **Cyberpunk VR Port** (`0.2.2+`) | `dariulone/cyberpunk-vr-port` | Core VR plugin, single-pass stereo (`dxc\`), shaders, packed assets, Lua & script modules |
| **Cyber Engine Tweaks** | `maximegmd/CyberEngineTweaks` | General modding framework (skipped in `-Minimal` mode) |
| **redscript** | `jac3km4/redscript` | Script compiler framework (skipped in `-Minimal` mode) |
| **TweakXL** | `psiberx/cp2077-tweak-xl` | TweakDB framework (skipped in `-Minimal` mode) |
| **ArchiveXL** | `psiberx/cp2077-archive-xl` | Archive resource loader (skipped in `-Minimal` mode) |
| **Codeware** | `psiberx/cp2077-codeware` | Script extensions framework (skipped in `-Minimal` mode) |
| **Input Loader** | `jackhumbert/cyberpunk2077-input-loader` | Custom input binding loader (skipped in `-Minimal` mode) |

### 2. Optional Visual Mods (Nexus Mods)

Because VR Port `v0.2.2` ships its own holsters and optics, **no Nexus mods are required by default**. 

- **[Valentino Holsters](https://www.nexusmods.com/cyberpunk2077/mods/18100)** (Mod `18100`): Optional visual holster models. If you drop the archive into the `ManualDownloads` folder next to this script or pass `-IncludeValentinoHolsters`, the script will install it for you.

---

## Usage Modes

```powershell
# Standard full install (recommended: 100% automatic via GitHub)
.\Install-CyberpunkVR.ps1

# Standalone / Minimal install (RED4ext + VR Port 0.2.2 only; uses embedded Lua/redscript host)
.\Install-CyberpunkVR.ps1 -Minimal

# Specify game folder manually
.\Install-CyberpunkVR.ps1 -GamePath "D:\Games\Cyberpunk 2077"

# Optional: Install with Valentino Holsters (Nexus 18100)
.\Install-CyberpunkVR.ps1 -IncludeValentinoHolsters

# Uninstall everything and restore original backups
.\Install-CyberpunkVR.ps1 -Uninstall
```

---

## Safety & Backups

- Refuses to run while `Cyberpunk2077.exe` is running so DLLs and configuration files are never locked or corrupted.
- Every file overwritten or retired is backed up to `<game>\_CyberpunkVR_Installer\backup-<timestamp>\`.
- Every installed file is recorded in `<game>\_CyberpunkVR_Installer\manifest.json`.
- `-Uninstall` cleanly removes installed files, cleans up runtime VR caches/logs, restores original files, and offers to restore your pre-VR `UserSettings.json` (`UserSettings.pre-vr-*.json`).
- Verifies your executable version and warns if you are not on **Cyberpunk 2077 v2.5**.

---

## After it finishes

1. **Start your OpenXR runtime first** (Virtual Desktop VDXR, SteamVR, Meta Quest Link, etc.), *then* launch `bin\x64\Cyberpunk2077.exe`.
2. In the **pre-launch VR window**, select your headset preset and per-eye render resolution (leave `DEBUG` unchecked for normal gameplay).
3. **VR Lobby & Calibration**: On first launch (or after resetting), configure your weapon hand, height, T-pose, and new `v0.2.2` avatar options (Hands Only, left-handed controls, sprint mode).
4. **In-game hotkeys & shortcuts**:
   - **Hold `L3 + R3` (0.5 s)**: Open / close the holographic VR menu (holster slots, inventory, map, settings).
   - **Hold `L3 + Left Grip` (0.5 s)**: Activate cyberware OS (Sandevistan, Berserk, Overclock).
   - **`F10` / `Insert`**: Toggle the in-headset VR settings overlay (rendered in both eyes).
   - **`F7`**: Recenter HMD view.
   - **`Home` (or `Scroll Lock` when CET is installed)**: Toggle VR Port Lua mod windows.

---

## Requirements

- Windows 10/11, PowerShell 5.1 or newer
- **Cyberpunk 2077 v2.5** on PC (Steam, GOG, or Epic)
- An OpenXR-capable VR headset and runtime

---

## Credits

The VR port is created by **dariulone** — [Nexus Mods](https://www.nexusmods.com/cyberpunk2077/mods/30093) · [GitHub](https://github.com/dariulone/cyberpunk-vr-port). Original auto-installer by **no6969el**, updated for Cyberpunk 2077 v2.5 and VR Port v0.2.2+.
