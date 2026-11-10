<#
.SYNOPSIS
    One-click installer for the Cyberpunk 2077 VR Port v0.2.x (Nexus mod 30093) for
    Cyberpunk 2077 v2.5.

.DESCRIPTION
    Finds your Cyberpunk 2077 installation, cleans up legacy VR port files and incompatible scripts
    (including More Occluders, which fails to compile on Cyberpunk 2.5), downloads RED4ext and the
    latest VR port release from GitHub, and installs them into the game folder.

    Standalone by default:
      Since VR Port v0.2.0 the plugin (cyberpunkvrport.dll) runs standalone. It carries its own
      Lua host, redscript compiler (scc_lib.dll), archive mounter, TweakDB loader, input merger and
      Codeware replacements, so RED4ext is its only requirement. CET, redscript, TweakXL,
      ArchiveXL, Codeware and Input Loader are no longer needed; pass -WithFrameworks if your
      other mods want them.

    No Nexus downloads:
      Visual Holsters, Equipment-EX, Nova Optics and More Occluders stopped being requirements in
      v0.2.2, and v0.2.3 builds in the Valentino Holsters pieces (leg holster, shoulder harness,
      chest knife sheath). Everything comes from GitHub; no Nexus account or browser is needed.

    Seamless upgrade from earlier versions:
      * Removes and backs up More Occluders (r6\scripts\MoreOccluders.reds), which fails to
        compile on CP2077 2.5 and would otherwise disable every redscript mod.
      * Retires superseded Visual Holsters files in favour of the port's built-in holsters.
      * Retires legacy folders (CyberpunkVR_Stereo, CyberpunkVR_Hands, bin\x64\dxgi.dll, etc.).
      * Preserves existing VRIK calibration and user settings (vrik_calibration.ini, vrport.ini).
      * Leaves frameworks installed by an earlier full install in place; the port works with or
        without them, and -Uninstall still removes them.

    Everything it overwrites or retires is backed up first, and -Uninstall puts it all back.

.PARAMETER GamePath
    Path to the Cyberpunk 2077 folder (the one containing bin\x64\Cyberpunk2077.exe).
    Auto-detected if omitted.

.PARAMETER WithFrameworks
    Also install the general modding frameworks (Cyber Engine Tweaks, redscript, TweakXL,
    ArchiveXL, Codeware, Input Loader). The VR port does not need them; use this only when other
    mods you run do. Alias: -Full.

.PARAMETER Minimal
    Kept for older command lines. Standalone (RED4ext + VR port only) is now the default, so this
    does nothing unless combined with -WithFrameworks, which it overrides. Alias: -Standalone.

.PARAMETER Uninstall
    Remove everything this script installed and restore the backed-up originals.

.PARAMETER Force
    Skip the "press Enter to continue" confirmations.

.EXAMPLE
    .\Install-CyberpunkVR.ps1

.EXAMPLE
    .\Install-CyberpunkVR.ps1 -WithFrameworks

.EXAMPLE
    .\Install-CyberpunkVR.ps1 -GamePath "D:\Games\Cyberpunk 2077"

.EXAMPLE
    .\Install-CyberpunkVR.ps1 -Uninstall

.NOTES
    Mod page : https://www.nexusmods.com/cyberpunk2077/mods/30093
    Source   : https://github.com/dariulone/cyberpunk-vr-port
    Requires : Windows, PowerShell 5.1+, Cyberpunk 2077 v2.5, an OpenXR runtime.
#>

[CmdletBinding()]
param(
    [string] $GamePath,
    [Alias('Full')]
    [switch] $WithFrameworks,
    [Alias('Standalone')]
    [switch] $Minimal,
    [switch] $Uninstall,
    [switch] $Force,

    # Retired options, still accepted so old shortcuts and command lines keep working.
    [Parameter(DontShow)] [string] $NexusApiKey,
    [Parameter(DontShow)] [string] $DownloadsPath,
    [Parameter(DontShow)] [switch] $SkipNexus,
    [Parameter(DontShow)] [switch] $IncludeValentinoHolsters
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is ~10x faster without it

$ScriptRoot        = Split-Path -Parent $MyInvocation.MyCommand.Definition
$StateDirName      = '_CyberpunkVR_Installer'
$UserAgent         = 'CyberpunkVR-Installer/2.3 (VRPort-0.2.3)'
$TargetGameVersion = '2.5'
$InstallFrameworks = $WithFrameworks -and -not $Minimal

# --------------------------------------------------------------------------------------
# What gets installed, in order. Every one of these archives extracts to the game root.
# --------------------------------------------------------------------------------------

$CoreGitHubComponents = @(
    @{ Name = 'RED4ext';            Repo = 'WopsS/RED4ext';                            Pattern = '^red4ext-[\d.]+\.zip$' }
)

$FrameworkGitHubComponents = @(
    @{ Name = 'Cyber Engine Tweaks';Repo = 'maximegmd/CyberEngineTweaks';              Pattern = '^cet_.*\.zip$' }
    @{ Name = 'redscript';          Repo = 'jac3km4/redscript';                        Pattern = 'windows\.zip$' }
    @{ Name = 'TweakXL';            Repo = 'psiberx/cp2077-tweak-xl';                  Pattern = '^TweakXL-[\d.]+\.zip$' }
    @{ Name = 'ArchiveXL';          Repo = 'psiberx/cp2077-archive-xl';                Pattern = '^ArchiveXL-[\d.]+\.zip$' }
    @{ Name = 'Codeware';           Repo = 'psiberx/cp2077-codeware';                  Pattern = '^Codeware-[\d.]+\.zip$' }
    @{ Name = 'Input Loader';       Repo = 'jackhumbert/cyberpunk2077-input-loader';   Pattern = '^input_loader_v[\d.]+\.zip$' }
)

$GitHubComponents = if ($InstallFrameworks) {
    $CoreGitHubComponents + $FrameworkGitHubComponents
} else {
    $CoreGitHubComponents
}

# Installed last, after every dependency is in place.
$VrPort = @{ Name = 'Cyberpunk VR Port'; Repo = 'dariulone/cyberpunk-vr-port'; Pattern = '^CyberpunkVRPort-.*\.zip$' }

# No Nexus mods: Visual Holsters, Nova Optics, Equipment-EX and More Occluders stopped being
# requirements in 0.2.2 (More Occluders does not even compile on 2.5), and 0.2.3 builds in the
# Valentino Holsters pieces.

# --------------------------------------------------------------------------------------
# Console helpers
# --------------------------------------------------------------------------------------

function Write-Head ($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Write-Step ($t) { Write-Host "   -> $t" -ForegroundColor Gray }
function Write-Ok   ($t) { Write-Host "   [ok] $t" -ForegroundColor Green }
function Write-Note ($t) { Write-Host "   [!] $t" -ForegroundColor Yellow }
function Write-Bad  ($t) { Write-Host "   [x] $t" -ForegroundColor Red }

function Confirm-Continue ($message) {
    if ($Force) { return }
    Write-Host ""
    Read-Host "$message (press Enter to continue)" | Out-Null
}

function Stop-WithError ($message) {
    Write-Host ""
    Write-Bad $message
    Write-Host ""
    if (-not $Force) { Read-Host "Press Enter to close" | Out-Null }
    exit 1
}

function Assert-GameNotRunning {
    $proc = Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-WithError "Cyberpunk2077.exe is currently running. Close the game first so plugin DLLs and UserSettings.json are not locked."
    }
}

# --------------------------------------------------------------------------------------
# Locating the game
# --------------------------------------------------------------------------------------

function Test-GameFolder ($path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    return (Test-Path (Join-Path $path 'bin\x64\Cyberpunk2077.exe'))
}

function Get-SteamLibraryFolders {
    $steam = $null
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = (Get-ItemProperty -Path $key -ErrorAction Stop)
            $steam = if ($p.SteamPath) { $p.SteamPath } else { $p.InstallPath }
            if ($steam) { break }
        } catch { }
    }
    if (-not $steam) { return @() }
    $steam = $steam -replace '/', '\'

    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s*"([^"]+)"')) {
            $libs += ($m.Groups[1].Value -replace '\\\\', '\')
        }
    }
    return $libs | Select-Object -Unique
}

function Find-GamePath {
    # 1. Steam libraries
    foreach ($lib in Get-SteamLibraryFolders) {
        $candidate = Join-Path $lib 'steamapps\common\Cyberpunk 2077'
        if (Test-GameFolder $candidate) { return $candidate }
    }

    # 2. GOG Galaxy registry entries
    foreach ($root in 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\*', 'HKLM:\SOFTWARE\GOG.com\Games\*') {
        try {
            foreach ($g in Get-ItemProperty -Path $root -ErrorAction Stop) {
                if ($g.gameName -like '*Cyberpunk*' -and (Test-GameFolder $g.path)) { return $g.path }
            }
        } catch { }
    }

    # 3. Epic Games manifests
    $epicManifests = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path $epicManifests) {
        foreach ($f in Get-ChildItem $epicManifests -Filter *.item -ErrorAction SilentlyContinue) {
            try {
                $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
                if ($j.DisplayName -like '*Cyberpunk*' -and (Test-GameFolder $j.InstallLocation)) { return $j.InstallLocation }
            } catch { }
        }
    }

    # 4. Uninstall keys (covers most storefronts)
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        try {
            foreach ($k in Get-ItemProperty -Path $root -ErrorAction Stop) {
                if ($k.DisplayName -like '*Cyberpunk 2077*' -and (Test-GameFolder $k.InstallLocation)) { return $k.InstallLocation }
            }
        } catch { }
    }

    # 5. Brute force common drives
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null })) {
        foreach ($sub in 'Games\Cyberpunk 2077', 'GOG Games\Cyberpunk 2077', 'SteamLibrary\steamapps\common\Cyberpunk 2077',
                         'Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077') {
            $candidate = Join-Path $d.Root $sub
            if (Test-GameFolder $candidate) { return $candidate }
        }
    }

    return $null
}

function Get-GameVersion ($gameRoot) {
    try {
        $exe = Join-Path $gameRoot 'bin\x64\Cyberpunk2077.exe'
        $vi = (Get-Item $exe).VersionInfo
        foreach ($v in @($vi.ProductVersion, $vi.FileVersion)) {
            if ($v -and $v -match '(\d+\.\d+(?:\.\d+)?)') { return $Matches[1] }
        }
    } catch { }
    return $null
}

# --------------------------------------------------------------------------------------
# Download + extract
# --------------------------------------------------------------------------------------

function Get-LatestRelease ($repo) {
    $url = "https://api.github.com/repos/$repo/releases/latest"
    $headers = @{ 'User-Agent' = $UserAgent; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    return Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 60
}

function Select-ReleaseAsset ($release, $pattern) {
    $assets = @($release.assets | Where-Object {
        $_.name -notmatch '(?i)(symbol|pdb|debug|source|\.sig$|\.sha256$|\.txt$)'
    })
    $match = @($assets | Where-Object { $_.name -match $pattern })
    if ($match.Count -gt 0) { return $match[0] }

    # Fallback so a renamed asset doesn't break the whole install.
    $zip = @($assets | Where-Object { $_.name -match '(?i)\.(zip|7z|rar)$' })
    if ($zip.Count -gt 0) { return $zip[0] }
    return $null
}

function Invoke-Download ($url, $destination, $headers) {
    $h = @{ 'User-Agent' = $UserAgent }
    if ($headers) { $headers.GetEnumerator() | ForEach-Object { $h[$_.Key] = $_.Value } }
    Invoke-WebRequest -Uri $url -OutFile $destination -Headers $h -TimeoutSec 900 -UseBasicParsing
    if (-not (Test-Path $destination) -or (Get-Item $destination).Length -eq 0) {
        throw "Download produced an empty file: $url"
    }
}

function Get-SevenZip {
    foreach ($p in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
                   "$env:ProgramFiles\NanaZip\7z.exe", "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe") {
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    try {
        $reg = Get-ItemProperty 'HKLM:\SOFTWARE\7-Zip' -ErrorAction Stop
        if ($reg.Path -and (Test-Path (Join-Path $reg.Path '7z.exe'))) { return (Join-Path $reg.Path '7z.exe') }
    } catch { }
    return $null
}

function Expand-AnyArchive ($archive, $destination) {
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $ext = [IO.Path]::GetExtension($archive).ToLower()

    if ($ext -eq '.zip') {
        try {
            Expand-Archive -Path $archive -DestinationPath $destination -Force
            return
        } catch {
            # Some mod authors ship zips with entries .NET dislikes; fall through to 7-Zip.
        }
    }

    $sevenZip = Get-SevenZip
    if (-not $sevenZip) {
        throw "This archive is a '$ext' file and 7-Zip is not installed. Install it from https://www.7-zip.org (or run: winget install 7zip.7zip) and re-run this script."
    }
    & $sevenZip x $archive "-o$destination" -y -bso0 -bsp0 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7-Zip failed to extract $archive" }
}

# Some archives are already rooted at the game folder; others wrap everything in one
# top-level directory. Work out which and return the folder that should be merged in.
function Find-ArchiveRoot ($path) {
    $markers = @('bin', 'r6', 'red4ext', 'archive', 'engine', 'mods', 'plugins')
    $current = $path

    for ($depth = 0; $depth -lt 4; $depth++) {
        $entries = @(Get-ChildItem -LiteralPath $current -Force)
        $dirs    = @($entries | Where-Object { $_.PSIsContainer })
        $files   = @($entries | Where-Object { -not $_.PSIsContainer })

        if ($dirs | Where-Object { $markers -contains $_.Name.ToLower() }) { return $current }

        # A single folder with nothing meaningful beside it => descend into it.
        $junk = @($files | Where-Object { $_.Extension -notmatch '(?i)^\.(dll|asi|exe|archive|xl|reds|lua|json|ini|toml|yaml|tweak|xml)$' })
        if ($dirs.Count -eq 1 -and $files.Count -eq $junk.Count) {
            $current = $dirs[0].FullName
            continue
        }
        return $current
    }
    return $current
}

# --------------------------------------------------------------------------------------
# Legacy VR Port cleanup (upgrading from <= 0.1.9 to 0.2.1+)
# --------------------------------------------------------------------------------------

# Copies a game file into this run's backup folder before it is overwritten or removed.
# Files an earlier run of this installer put there are not originals, so they are skipped:
# -Uninstall deletes them anyway, and restoring them would leave them behind.
# Returns $true when a backup was written.
function Save-Original ($gameRoot, $relativePath, $state) {
    if ($state.Owned.Contains($relativePath)) { return $false }
    $bk = Join-Path $state.BackupDir $relativePath
    if (Test-Path -LiteralPath $bk) { return $false }
    $bkDir = Split-Path -Parent $bk
    if (-not (Test-Path -LiteralPath $bkDir)) { New-Item -ItemType Directory -Path $bkDir -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $gameRoot $relativePath) -Destination $bk -Force
    return $true
}

function Backup-AndRemoveItem ($gameRoot, $relativePath, $state) {
    $target = Join-Path $gameRoot $relativePath
    if (-not (Test-Path -LiteralPath $target)) { return 0 }

    $item = Get-Item -LiteralPath $target -Force
    if ($item.PSIsContainer) {
        $files = @(Get-ChildItem -LiteralPath $target -Recurse -File -Force -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            Save-Original $gameRoot ($f.FullName.Substring($gameRoot.Length).TrimStart('\')) $state | Out-Null
        }
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        return $files.Count
    } else {
        Save-Original $gameRoot $relativePath $state | Out-Null
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        return 1
    }
}

function Clear-LegacyVrPortInstall ($gameRoot, $state) {
    # 1. Preserve VRIK calibration from <= 0.1.9 (red4ext\plugins\CyberpunkVR_Stereo\vrik_calibration.ini)
    #    before removing the old plugin folder.
    $oldCalib = Join-Path $gameRoot 'red4ext\plugins\CyberpunkVR_Stereo\vrik_calibration.ini'
    $newCalib = Join-Path $gameRoot 'red4ext\plugins\cyberpunkvrport\config\vrik_calibration.ini'
    if ((Test-Path -LiteralPath $oldCalib) -and -not (Test-Path -LiteralPath $newCalib)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $newCalib) -Force | Out-Null
        Copy-Item -LiteralPath $oldCalib -Destination $newCalib -Force
        Write-Ok "Migrated vrik_calibration.ini from CyberpunkVR_Stereo to cyberpunkvrport\config"
    }

    # 2. Folders retired in <= 0.2.2 that MUST NOT coexist with red4ext\plugins\cyberpunkvrport:
    #    - CyberpunkVR_Stereo: causes 0.2.0+ plugin to stay off and refuse to load.
    #    - CyberpunkVR_Hands: causes a crash at 0xFFFFFFFFFFFFFFFF due to double-hooking.
    #    - r6\tweaks\vrport & vrcigarette: now in red4ext\plugins\cyberpunkvrport\config\tweaks.
    #    - QuickBoot dev tool folders.
    #    - r6\tweaks\VisualHolsters: superseded by 0.2.2 native immersive holsters.
    $retiredDirs = @(
        'red4ext\plugins\CyberpunkVR_Stereo',
        'red4ext\plugins\CyberpunkVR_Hands',
        'r6\tweaks\vrport',
        'r6\tweaks\vrcigarette',
        'r6\tweaks\VisualHolsters',
        'red4ext\plugins\cyberpunkvrport\lua\CyberpunkVRPort_QuickBoot',
        'bin\x64\plugins\cyber_engine_tweaks\mods\CyberpunkVRPort_QuickBoot'
    )

    # Also retire any legacy r6\scripts\CyberpunkVRPort_* folders (scripts now live inside
    # red4ext\plugins\cyberpunkvrport\scripts\CyberpunkVRPort_*; keeping both defines symbols twice).
    $r6Scripts = Join-Path $gameRoot 'r6\scripts'
    if (Test-Path -LiteralPath $r6Scripts) {
        foreach ($d in Get-ChildItem -LiteralPath $r6Scripts -Directory -Filter 'CyberpunkVRPort_*' -Force -ErrorAction SilentlyContinue) {
            $retiredDirs += ("r6\scripts\" + $d.Name)
        }
    }

    # 3. Loose files retired across 0.1.0 -> 0.2.2:
    $retiredFiles = @(
        'bin\x64\dxgi.dll',
        'red4ext\plugins\cyberpunkvrport\CyberpunkVR_Stereo.dll',
        'red4ext\plugins\cyberpunkvrport\CyberpunkVR_Stereo.pdb',
        'red4ext\plugins\cyberpunkvrport\CyberpunkVR_Stereo.dll.old',
        'engine\config\platform\pc\vrcam_cpu_tweaks.ini',
        'archive\pc\mod\cyberpunkvrport.archive',
        'archive\pc\mod\cyberpunkvrport.archive.xl',
        'archive\pc\mod\VRCigarette.archive.xl',
        'archive\pc\mod\vrport_basketball.archive',
        'archive\pc\mod\vrport_mag.archive',
        'archive\pc\mod\vrport_menu_native.archive',
        'archive\pc\mod\vrport_menu_panels.archive'
    )

    # 4. Critical v0.2.1 -> v0.2.2 upgrade fix:
    #    More Occluders (Scripted v0.3) was installed by earlier installers, but fails to
    #    compile on Cyberpunk 2.5! In redscript, a single script failure disables all scripts.
    #    The VR Port v0.2.2 does not require More Occluders and actively advises removing it.
    $moreOccluderPaths = @(
        'r6\scripts\MoreOccluders.reds',
        'r6\scripts\MoreOccluders'
    )
    $pcModDir = Join-Path $gameRoot 'archive\pc\mod'
    if (Test-Path -LiteralPath $pcModDir) {
        foreach ($f in Get-ChildItem -LiteralPath $pcModDir -File -Filter '*MoreOccluder*' -Force -ErrorAction SilentlyContinue) {
            $moreOccluderPaths += ("archive\pc\mod\" + $f.Name)
        }
    }

    # 5. Visual Holsters cleanup (superseded by native immersive holsters in 0.2.2):
    $visualHolsterPaths = @()
    if (Test-Path -LiteralPath $pcModDir) {
        foreach ($f in Get-ChildItem -LiteralPath $pcModDir -File -Filter '*VisualHolster*' -Force -ErrorAction SilentlyContinue) {
            $visualHolsterPaths += ("archive\pc\mod\" + $f.Name)
        }
    }

    $cleaned = 0

    # Clean legacy directories
    foreach ($relDir in ($retiredDirs | Select-Object -Unique)) {
        $n = Backup-AndRemoveItem $gameRoot $relDir $state
        if ($n -gt 0) {
            Write-Ok "Retired legacy folder: $relDir ($n file(s) backed up)"
            $cleaned += $n
        }
    }

    # Clean legacy loose files
    foreach ($relFile in ($retiredFiles | Select-Object -Unique)) {
        $n = Backup-AndRemoveItem $gameRoot $relFile $state
        if ($n -gt 0) {
            Write-Ok "Retired legacy file: $relFile (backed up)"
            $cleaned += $n
        }
    }

    # Clean More Occluders (vital fix for redscript on 2.5)
    foreach ($item in ($moreOccluderPaths | Select-Object -Unique)) {
        $n = Backup-AndRemoveItem $gameRoot $item $state
        if ($n -gt 0) {
            Write-Ok "Retired incompatible More Occluders: $item (backed up) - fixes redscript compilation failure on Cyberpunk 2.5!"
            $cleaned += $n
        }
    }

    # Clean Visual Holsters (prevents mesh clipping with native holsters)
    foreach ($item in ($visualHolsterPaths | Select-Object -Unique)) {
        $n = Backup-AndRemoveItem $gameRoot $item $state
        if ($n -gt 0) {
            Write-Ok "Retired superseded Visual Holsters: $item (backed up) - replaced by native immersive holsters in 0.2.2"
            $cleaned += $n
        }
    }
}

# --------------------------------------------------------------------------------------
# Installing into the game folder (with backups + a manifest for uninstall)
# --------------------------------------------------------------------------------------

function Copy-IntoGame ($sourceRoot, $gameRoot, $componentName, $state) {
    $sourceRoot = (Resolve-Path $sourceRoot).Path
    $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)
    if ($files.Count -eq 0) { throw "$componentName : archive contained no files." }

    $installed = 0
    $backedUp  = 0

    foreach ($f in $files) {
        $relative = $f.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $target   = Join-Path $gameRoot $relative
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

        if ((Test-Path -LiteralPath $target) -and (Save-Original $gameRoot $relative $state)) { $backedUp++ }

        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        $installed++
        [void]$state.Files.Add($relative)
        [void]$state.Owned.Add($relative)
    }

    $msg = "$componentName : $installed file(s) installed"
    if ($backedUp -gt 0) { $msg += ", $backedUp existing file(s) backed up" }
    Write-Ok $msg
}

function Install-Archive ($archivePath, $gameRoot, $componentName, $state, $workDir) {
    $stage = Join-Path $workDir ("stage_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Expand-AnyArchive $archivePath $stage
        $root = Find-ArchiveRoot $stage
        Copy-IntoGame $root $gameRoot $componentName $state
    } finally {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-FromGitHub ($component, $gameRoot, $state, $workDir) {
    Write-Step "$($component.Name) - checking latest release..."
    $release = Get-LatestRelease $component.Repo
    $asset   = Select-ReleaseAsset $release $component.Pattern
    if (-not $asset) { throw "$($component.Name): no downloadable asset found in release $($release.tag_name)." }

    $file = Join-Path $workDir $asset.name
    Write-Step "$($component.Name) $($release.tag_name) - downloading $($asset.name)"
    Invoke-Download $asset.browser_download_url $file
    Install-Archive $file $gameRoot $component.Name $state $workDir
    $state.Versions[$component.Name] = $release.tag_name
}

# --------------------------------------------------------------------------------------
# Uninstall
# --------------------------------------------------------------------------------------

# Manifests list every backup folder, oldest first (BackupDirs). Manifests written before
# that only had the one folder of their own run (BackupDir).
function Get-ManifestBackupDirs ($manifest) {
    if ($manifest.BackupDirs) { return @($manifest.BackupDirs) }
    if ($manifest.BackupDir)  { return @($manifest.BackupDir) }
    return @()
}

function Invoke-Uninstall ($gameRoot) {
    Assert-GameNotRunning

    $stateDir = Join-Path $gameRoot $StateDirName
    $manifestPath = Join-Path $stateDir 'manifest.json'
    if (-not (Test-Path $manifestPath)) {
        Stop-WithError "No install manifest found at $manifestPath - nothing to uninstall."
    }

    $m = Get-Content $manifestPath -Raw | ConvertFrom-Json
    Write-Head "Uninstalling (installed $($m.InstalledAt))"

    $removed = 0
    foreach ($rel in $m.Files) {
        $p = Join-Path $gameRoot $rel
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; $removed++ }
    }

    # Also remove runtime-generated files created by CyberpunkVRPort 0.2.2+
    $runtimeFiles = @(
        'bin\x64\vrport.ini',
        'bin\x64\vrport-launcher.ini',
        'bin\x64\cyberpunkvrport.log',
        'r6\input\CyberpunkVRPort_ScannerHud.xml',
        'r6\input\CyberpunkVRPort_PhotoMode.xml'
    )
    foreach ($rf in $runtimeFiles) {
        $p = Join-Path $gameRoot $rf
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    foreach ($rd in @('red4ext\plugins\cyberpunkvrport\log', 'red4ext\plugins\cyberpunkvrport\config\input\merged', 'red4ext\plugins\cyberpunkvrport\dxc')) {
        $p = Join-Path $gameRoot $rd
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Ok "$removed file(s) removed"

    # Newest backup first, so where two runs saved the same path the oldest copy (the true
    # original) is written last and wins.
    $backupDirs = @(Get-ManifestBackupDirs $m)
    [array]::Reverse($backupDirs)
    $restored = 0
    foreach ($bd in $backupDirs) {
        if (-not (Test-Path -LiteralPath $bd)) { continue }
        $backupRoot = (Resolve-Path -LiteralPath $bd).Path
        foreach ($f in Get-ChildItem -LiteralPath $backupRoot -Recurse -File -Force) {
            $rel = $f.FullName.Substring($backupRoot.Length).TrimStart('\')
            $target = Join-Path $gameRoot $rel
            $dir = Split-Path -Parent $target
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $f.FullName -Destination $target -Force
            $restored++
        }
    }
    if ($restored -gt 0) { Write-Ok "$restored original file(s) restored from backup" }

    # Tidy up now-empty mod folders.
    foreach ($d in @('red4ext\plugins', 'bin\x64\plugins\cyber_engine_tweaks\mods', 'r6\scripts', 'r6\tweaks', 'r6\input', 'archive\pc\mod')) {
        $p = Join-Path $gameRoot $d
        if (Test-Path $p) {
            Get-ChildItem $p -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending |
                Where-Object { -not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue) } |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    # Offer to restore UserSettings.json backup created by the VR Port on first launch
    $cfgDir = Join-Path $env:LOCALAPPDATA 'CD Projekt Red\Cyberpunk 2077'
    if (Test-Path $cfgDir) {
        $preVrBackup = Get-ChildItem -Path $cfgDir -Filter 'UserSettings.pre-vr-*.json' -File -ErrorAction SilentlyContinue |
                       Sort-Object Name -Descending |
                       Select-Object -First 1
        if ($preVrBackup) {
            $restoreSettings = $true
            if (-not $Force) {
                Write-Host ""
                $ans = Read-Host "   Restore pre-VR UserSettings.json from $($preVrBackup.Name)? [y/N]"
                $restoreSettings = ($ans -match '^(y|yes)$')
            }
            if ($restoreSettings) {
                Copy-Item -LiteralPath $preVrBackup.FullName -Destination (Join-Path $cfgDir 'UserSettings.json') -Force
                Write-Ok "Restored UserSettings.json from $($preVrBackup.Name)"
            }
        }
    }

    Rename-Item $manifestPath ("manifest.removed.{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss')) -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Ok "Uninstall complete. Backups kept in $stateDir"
    if (-not $Force) { Read-Host "Press Enter to close" | Out-Null }
    exit 0
}

# ======================================================================================
# Main
# ======================================================================================

Write-Host ""
Write-Host "  Cyberpunk 2077 VR Port (v0.2.x) - automatic installer" -ForegroundColor Magenta
Write-Host "  https://www.nexusmods.com/cyberpunk2077/mods/30093" -ForegroundColor DarkGray
Write-Host ""

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Stop-WithError "PowerShell 5.1 or newer is required. Yours is $($PSVersionTable.PSVersion)."
}

Assert-GameNotRunning

# --- Find the game ---------------------------------------------------------------------
Write-Head "Locating Cyberpunk 2077"
if (-not $GamePath) { $GamePath = Find-GamePath }
while (-not (Test-GameFolder $GamePath)) {
    if ($GamePath) { Write-Note "Not a Cyberpunk 2077 folder: $GamePath" }
    Write-Host "   Enter the game folder (the one containing bin\x64\Cyberpunk2077.exe)." -ForegroundColor Gray
    $GamePath = (Read-Host "   Game folder").Trim('"')
    if ([string]::IsNullOrWhiteSpace($GamePath)) { Stop-WithError "No game folder given." }
}
$GamePath = (Resolve-Path $GamePath).Path
Write-Ok "Game folder: $GamePath"

if ($Uninstall) { Invoke-Uninstall $GamePath }

$version = Get-GameVersion $GamePath
if ($version) {
    if ($version -match '^2\.5(\b|\.)') {
        Write-Ok "Game version $version (matches Cyberpunk 2077 $TargetGameVersion required by VR Port 0.2.x)"
    } else {
        Write-Note "Game version reads as $version. VR Port 0.2.x requires Cyberpunk 2077 $TargetGameVersion (2.31 is no longer supported and the plugin will refuse to hook on mismatched builds)."
    }
} else {
    Write-Note "Could not read the game version. VR Port 0.2.x requires Cyberpunk 2077 $TargetGameVersion."
}

# --- Writability check ------------------------------------------------------------------
try {
    $probe = Join-Path $GamePath '.vrinstaller_write_test'
    Set-Content -Path $probe -Value 'x' -Force
    Remove-Item $probe -Force
} catch {
    Stop-WithError "Cannot write to $GamePath. Right-click this script and choose 'Run as administrator', or move the game out of Program Files."
}

# --- Plan -------------------------------------------------------------------------------
if ($NexusApiKey -or $DownloadsPath -or $SkipNexus -or $IncludeValentinoHolsters) {
    Write-Note "Nexus options are no longer used: nothing is downloaded from Nexus, and VR Port 0.2.3 builds in the Valentino Holsters pieces. Ignoring them."
}
if ($WithFrameworks -and $Minimal) {
    Write-Note "-Minimal overrides -WithFrameworks: installing RED4ext and the VR port only."
}

Write-Head "Plan"
if ($InstallFrameworks) {
    Write-Host "   Mode: VR port + modding frameworks (CET, redscript, TweakXL, ArchiveXL, Codeware, Input Loader)" -ForegroundColor Yellow
    Write-Host "         The port does not need them; they are here for your other mods." -ForegroundColor DarkGray
} else {
    Write-Host "   Mode: STANDALONE (RED4ext + VR port; the port has its own Lua, redscript, archive and TweakDB host)" -ForegroundColor Yellow
}
Write-Host "   From GitHub (fully automatic, no account needed):" -ForegroundColor Gray
$GitHubComponents | ForEach-Object { Write-Host "     - $($_.Name)" -ForegroundColor DarkGray }
Write-Host "     - $($VrPort.Name)" -ForegroundColor DarkGray
Write-Host "   Nexus mods: none needed (holsters, optics and belt slots are built into the port)." -ForegroundColor Green

if (-not $InstallFrameworks) {
    $presentFrameworks = @(
        @{ Name = 'Cyber Engine Tweaks'; Path = 'bin\x64\plugins\cyber_engine_tweaks.asi' }
        @{ Name = 'redscript';           Path = 'engine\tools\scc.exe' }
        @{ Name = 'TweakXL';             Path = 'red4ext\plugins\TweakXL\TweakXL.dll' }
        @{ Name = 'ArchiveXL';           Path = 'red4ext\plugins\ArchiveXL\ArchiveXL.dll' }
        @{ Name = 'Codeware';            Path = 'red4ext\plugins\Codeware\Codeware.dll' }
        @{ Name = 'Input Loader';        Path = 'red4ext\plugins\input_loader\input_loader.dll' }
    ) | Where-Object { Test-Path -LiteralPath (Join-Path $GamePath $_.Path) } | ForEach-Object { $_.Name }
    if ($presentFrameworks.Count -gt 0) {
        Write-Host "   Already installed and left as they are: $($presentFrameworks -join ', ')." -ForegroundColor DarkGray
        Write-Host "   The port works with or without them; pass -WithFrameworks to update them too." -ForegroundColor DarkGray
    }
}
Write-Host ""
Write-Host "   Upgrading from an older release is seamless: retired files and More Occluders are removed, calibration is kept." -ForegroundColor DarkGray
Write-Host "   Anything overwritten or retired is backed up. Re-run later to update; -Uninstall to revert." -ForegroundColor DarkGray

Confirm-Continue "Ready to install"

# --- State ------------------------------------------------------------------------------
$stamp        = Get-Date -Format 'yyyyMMdd-HHmmss'
$stateDir     = Join-Path $GamePath $StateDirName
$manifestPath = Join-Path $stateDir 'manifest.json'
$workDir      = Join-Path $env:TEMP "cpvr_$stamp"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
New-Item -ItemType Directory -Path $workDir  -Force | Out-Null

# Re-running over an earlier install carries its manifest forward, so -Uninstall still removes
# what that run installed (frameworks from a full install, say) and restores its backups.
$previous = $null
if (Test-Path -LiteralPath $manifestPath) {
    try { $previous = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
    catch { Write-Note "Could not read the previous install manifest ($($_.Exception.Message)); starting a new one." }
}

$ci = [StringComparer]::OrdinalIgnoreCase
$state = [ordered]@{
    InstalledAt = (Get-Date).ToString('s')
    GamePath    = $GamePath
    BackupDir   = (Join-Path $stateDir "backup-$stamp")
    BackupDirs  = @()
    Frameworks  = [bool]$InstallFrameworks
    Files       = New-Object 'System.Collections.Generic.HashSet[string]' $ci
    Owned       = New-Object 'System.Collections.Generic.HashSet[string]' $ci
    Versions    = [ordered]@{}
}
if ($previous) {
    foreach ($f in @($previous.Files)) { if ($f) { [void]$state.Files.Add($f); [void]$state.Owned.Add($f) } }
    $state.BackupDirs = @(Get-ManifestBackupDirs $previous)
    if ($previous.Versions) {
        foreach ($p in $previous.Versions.PSObject.Properties) { $state.Versions[$p.Name] = $p.Value }
    }
}
$state.BackupDirs += $state.BackupDir
New-Item -ItemType Directory -Path $state.BackupDir -Force | Out-Null

$failed = @()

try {
    # --- Clean up legacy VR builds & incompatible scripts ---------------------------------
    Write-Head "Checking for legacy VR Port files & incompatible scripts"
    Clear-LegacyVrPortInstall $GamePath $state

    # --- GitHub dependencies -------------------------------------------------------------
    Write-Head "Installing dependencies from GitHub"
    foreach ($c in $GitHubComponents) {
        try { Install-FromGitHub $c $GamePath $state $workDir }
        catch { Write-Bad "$($c.Name) failed: $($_.Exception.Message)"; $failed += $c.Name }
    }

    # --- The VR port itself ----------------------------------------------------------------
    Write-Head "Installing the VR port"
    try { Install-FromGitHub $VrPort $GamePath $state $workDir }
    catch { Write-Bad "$($VrPort.Name) failed: $($_.Exception.Message)"; $failed += $VrPort.Name }

} finally {
    # Drop this run's backup folder from the manifest if nothing needed backing up.
    if (-not (Get-ChildItem -LiteralPath $state.BackupDir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $state.BackupDir -Recurse -Force -ErrorAction SilentlyContinue
        $state.BackupDirs = @($state.BackupDirs | Where-Object { $_ -ne $state.BackupDir })
    }
    $manifest = [ordered]@{
        InstalledAt = $state.InstalledAt
        GamePath    = $state.GamePath
        BackupDirs  = @($state.BackupDirs)
        Frameworks  = $state.Frameworks
        Files       = @($state.Files | Sort-Object)
        Versions    = $state.Versions
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Verify -------------------------------------------------------------------------------
Write-Head "Verifying"
$expected = @(
    @{ Path = 'red4ext\RED4ext.dll';                                                    What = 'RED4ext loader' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\cyberpunkvrport.dll';                    What = 'VR Port core plugin (cyberpunkvrport.dll)' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\dxc\dxcompiler.dll';                    What = 'DirectX shader compiler (single-pass stereo)' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\dxc\dxil.dll';                          What = 'DirectX intermediate language library' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\redscript\scc_lib.dll';                  What = 'VR Port built-in redscript compiler' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\archive\cyberpunkvrport.archive';        What = 'VR Port packed assets archive' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\config\archive.yaml';                    What = 'VR Port archive manifest' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\config\UserSettings.json';               What = 'VR Port first-launch settings preset' }
    @{ Path = 'bin\x64\openvr_api.dll';                                                 What = 'OpenVR API shim' }
)

if ($InstallFrameworks) {
    $expected += @(
        @{ Path = 'bin\x64\plugins\cyber_engine_tweaks.asi';                            What = 'Cyber Engine Tweaks' }
        @{ Path = 'engine\tools\scc.exe';                                               What = 'redscript compiler' }
        @{ Path = 'red4ext\plugins\ArchiveXL\ArchiveXL.dll';                            What = 'ArchiveXL' }
        @{ Path = 'red4ext\plugins\TweakXL\TweakXL.dll';                                What = 'TweakXL' }
        @{ Path = 'red4ext\plugins\Codeware\Codeware.dll';                              What = 'Codeware' }
        @{ Path = 'red4ext\plugins\input_loader\input_loader.dll';                      What = 'Input Loader' }
    )
}

$missing = @()
foreach ($e in $expected) {
    if (Test-Path (Join-Path $GamePath $e.Path)) { Write-Ok "$($e.What)" }
    else { Write-Bad "missing: $($e.Path)  ($($e.What))"; $missing += $e.What }
}

# Verify that conflicting legacy plugin folders or broken scripts are NOT present
$conflicts = @(
    @{ Path = 'red4ext\plugins\CyberpunkVR_Stereo'; Reason = 'causes VR plugin to stay off and refuse to load' }
    @{ Path = 'red4ext\plugins\CyberpunkVR_Hands';  Reason = 'causes crash at 0xFFFFFFFFFFFFFFFF due to double-hooking' }
    @{ Path = 'bin\x64\dxgi.dll';                   Reason = 'interferes with VR hooking' }
    @{ Path = 'r6\scripts\MoreOccluders.reds';      Reason = 'incompatible with CP2077 2.5 and disables all redscript mods' }
)
foreach ($c in $conflicts) {
    if (Test-Path (Join-Path $GamePath $c.Path)) {
        Write-Bad "conflicting/broken path still present: $($c.Path) ($($c.Reason))"
    }
}

# --- Summary --------------------------------------------------------------------------------
Write-Head "Done"
if ($state.Versions.Count -gt 0) {
    Write-Host "   Installed versions:" -ForegroundColor Gray
    $state.Versions.GetEnumerator() | ForEach-Object { Write-Host ("     {0,-22} {1}" -f $_.Key, $_.Value) -ForegroundColor DarkGray }
}
if (Test-Path -LiteralPath $state.BackupDir) {
    Write-Host "   Backups: $($state.BackupDir)" -ForegroundColor DarkGray
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Note "These did not install: $($failed -join ', ')"
    Write-Host "   Check your connection (or set GITHUB_TOKEN if GitHub rate-limited you), then re-run this script." -ForegroundColor Gray
}

Write-Host ""
Write-Host "  BEFORE YOU PLAY" -ForegroundColor Yellow
Write-Host "   1. Start your OpenXR runtime (Virtual Desktop VDXR / SteamVR / Meta Quest Link) FIRST." -ForegroundColor Gray
Write-Host "   2. Launch bin\x64\Cyberpunk2077.exe. In the pre-launch VR window, pick your headset" -ForegroundColor Gray
Write-Host "      model and per-eye render resolution (leave DEBUG unchecked for normal play)." -ForegroundColor Gray
Write-Host "   3. On first launch the VR lobby walks you through weapon hand, height, T-pose and avatar" -ForegroundColor Gray
Write-Host "      options (Hands Only, left-handed bindings, sprint mode)." -ForegroundColor Gray
Write-Host "   4. In game controls:" -ForegroundColor Gray
Write-Host "      - Hold L3 + R3 (0.5 s) for the holographic VR menu (holster slots, inventory, map, settings)." -ForegroundColor DarkGray
Write-Host "      - F10 / Insert for the in-headset settings overlay (now rendered in both eyes)." -ForegroundColor DarkGray
Write-Host "      - F7 to recenter HMD view." -ForegroundColor DarkGray
Write-Host "      - Home / Scroll Lock for Lua mod windows." -ForegroundColor DarkGray
Write-Host ""
Write-Host "   Re-run this script any time to update. Run with -Uninstall to revert." -ForegroundColor DarkGray
Write-Host ""

if (-not $Force) { Read-Host "Press Enter to close" | Out-Null }
