# Cyberpunk 2077 VR Port (v0.2.x) — Automatic Installer

Installs [dariulone's cyberpunk-vr-port](https://www.nexusmods.com/cyberpunk2077/mods/30093) (latest `v0.2.x` release) into your **Cyberpunk 2077 (v2.5)** folder.

## How to use it

1. Put all the files in this folder anywhere you like (Desktop is fine).
2. Double-click **`Install Cyberpunk VR.bat`**.
3. Answer the prompts.

That's it. If your game lives under `Program Files`, right-click the `.bat` and choose **Run as administrator** instead.

---

## Standalone since v0.2.0

The VR port runs standalone and needs **only RED4ext**. Its plugin carries its own Lua host, redscript compiler (`scc_lib.dll`), archive mounter, TweakDB loader, input merger and Codeware replacements, so Cyber Engine Tweaks, redscript, TweakXL, ArchiveXL, Codeware and Input Loader are no longer needed.

The installer therefore installs **RED4ext + the VR port** by default. If other mods you run need the frameworks, add `-WithFrameworks` and it installs those too. The port works with or without them: with CET installed it runs CET's mods beside its own, and with redscript installed that compiler compiles the port's scripts.

No Nexus mods are needed either. *Visual Holsters*, *Equipment-EX*, *Nova Optics* and *More Occluders* stopped being requirements in `v0.2.2`, and `v0.2.3` builds in the *Valentino Holsters* pieces (leg holster, shoulder harness, chest knife sheath). Everything downloads from GitHub, with no account or browser needed.

---

## Seamless upgrade from older versions

Run **`Install Cyberpunk VR.bat`** over your current installation. The installer handles the upgrade:

- **Fixes redscript compilation on Cyberpunk 2.5**: earlier installers installed *More Occluders (Scripted v0.3)* (`r6\scripts\MoreOccluders.reds`), which fails to compile on 2.5 and turns every redscript mod off. The installer backs it up and removes it.
- **Retires superseded Visual Holsters** files so they don't clip with the port's built-in holsters.
- **Cleans legacy folders** from `<= 0.1.9` (`CyberpunkVR_Stereo`, `CyberpunkVR_Hands`, `bin\x64\dxgi.dll`, old `r6\scripts\CyberpunkVRPort_*`, etc.).
- **Keeps your calibration**: `vrik_calibration.ini`, weapon-hand configuration and launcher preferences stay.
- **Leaves frameworks from an earlier full install in place** (CET, redscript, …). They keep working, and `-Uninstall` still removes them.

---

## What it installs

| Component | Source | Installed |
|---|---|---|
| **RED4ext** | `WopsS/RED4ext` | Always (the port's only requirement) |
| **Cyberpunk VR Port** | `dariulone/cyberpunk-vr-port` | Always (latest release) |
| **Cyber Engine Tweaks** | `maximegmd/CyberEngineTweaks` | Only with `-WithFrameworks` |
| **redscript** | `jac3km4/redscript` | Only with `-WithFrameworks` |
| **TweakXL** | `psiberx/cp2077-tweak-xl` | Only with `-WithFrameworks` |
| **ArchiveXL** | `psiberx/cp2077-archive-xl` | Only with `-WithFrameworks` |
| **Codeware** | `psiberx/cp2077-codeware` | Only with `-WithFrameworks` |
| **Input Loader** | `jackhumbert/cyberpunk2077-input-loader` | Only with `-WithFrameworks` |

---

## Usage

```powershell
# Standalone install (default): RED4ext + VR port
.\Install-CyberpunkVR.ps1

# Also install the modding frameworks, for other mods that need them
.\Install-CyberpunkVR.ps1 -WithFrameworks

# Specify the game folder manually
.\Install-CyberpunkVR.ps1 -GamePath "D:\Games\Cyberpunk 2077"

# Uninstall everything and restore the original files
.\Install-CyberpunkVR.ps1 -Uninstall
```

Older switches still work: `-Minimal` / `-Standalone` is now the default, and the Nexus options (`-IncludeValentinoHolsters`, `-SkipNexus`, `-NexusApiKey`, `-DownloadsPath`) are accepted and ignored.

If GitHub rate-limits you, set a `GITHUB_TOKEN` environment variable and re-run.

---

## Safety & backups

- Refuses to run while `Cyberpunk2077.exe` is running, so DLLs and configuration files are never locked mid-copy.
- Every original file it overwrites or retires is backed up to `<game>\_CyberpunkVR_Installer\backup-<timestamp>\`.
- Every installed file is recorded in `<game>\_CyberpunkVR_Installer\manifest.json`. Re-running the installer adds to that record instead of replacing it, so `-Uninstall` covers every run.
- `-Uninstall` removes the installed files, clears the port's runtime logs and caches, restores the original files, and offers to restore your pre-VR `UserSettings.json` (`UserSettings.pre-vr-*.json`).
- Warns if your game executable is not **Cyberpunk 2077 v2.5**.

---

## After it finishes

1. **Start your OpenXR runtime first** (Virtual Desktop VDXR, SteamVR, Meta Quest Link, etc.), *then* launch `bin\x64\Cyberpunk2077.exe`.
2. In the **pre-launch VR window**, pick your headset preset and per-eye render resolution (leave `DEBUG` unchecked for normal play).
3. **VR lobby & calibration**: on first launch, set your weapon hand, height, T-pose and avatar options (Hands Only, left-handed controls, sprint mode).
4. **In-game controls**:
   - **Hold `L3 + R3` (0.5 s)**: open / close the holographic VR menu (holster slots, inventory, map, settings).
   - **Hold `L3 + Left Grip` (0.5 s)**: activate cyberware OS (Sandevistan, Berserk, Overclock).
   - **`F10` / `Insert`**: toggle the in-headset VR settings overlay.
   - **`F7`**: recenter the HMD view.
   - **`Home` (or `Scroll Lock` when CET is installed)**: toggle the VR port's Lua mod windows.

---

## Requirements

- Windows 10/11, PowerShell 5.1 or newer
- **Cyberpunk 2077 v2.5** on PC (Steam, GOG, or Epic)
- An OpenXR-capable VR headset and runtime

---

## Credits

The VR port is created by **dariulone** — [Nexus Mods](https://www.nexusmods.com/cyberpunk2077/mods/30093) · [GitHub](https://github.com/dariulone/cyberpunk-vr-port). Original auto-installer by **no6969el**, updated for Cyberpunk 2077 v2.5 and VR Port v0.2.x.
