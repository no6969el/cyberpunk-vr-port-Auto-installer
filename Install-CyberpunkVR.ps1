<#
.SYNOPSIS
    One-click installer for the Cyberpunk 2077 VR Port v0.2.1+ (Nexus mod 30093) and all of its
    required dependencies for Cyberpunk 2077 v2.5.

.DESCRIPTION
    Finds your Cyberpunk 2077 installation, cleans up legacy VR port files from older versions
    (<= 0.1.9), downloads every dependency published on GitHub (RED4ext, Cyber Engine Tweaks,
    redscript, TweakXL, ArchiveXL, Codeware, Input Loader, Equipment-EX) plus the VR port itself
    (v0.2.1+), and installs them into the game folder.

    Three companion mods are distributed on Nexus Mods (Visual Holsters, Nova Optics, and
    More Occluders Scripted v0.3). Nexus only hands out direct download links to Premium
    accounts, so:
      * If you supply a Nexus API key from a Premium account, those are downloaded
        automatically too.
      * Otherwise the script opens each mod page in your browser, you click "Manual
        Download", and the script picks the archive up out of your Downloads folder and
        installs it for you.
      * Or you can pre-download them yourself and drop the archives into the
        "ManualDownloads" folder next to this script.

    Since VR Port v0.2.0+, the core VR plugin (cyberpunkvrport.dll) embeds its own Lua host,
    redscript compiler (scc_lib.dll), archive mounter, TweakDB loader, input merger, and
    Codeware replacements. If you pass -Minimal, the installer will ONLY install RED4ext and
    the Cyberpunk VR Port itself (skipping the companion mods and their frameworks).

    Everything it overwrites or retires is backed up first, and -Uninstall puts it all back.

.PARAMETER GamePath
    Path to the Cyberpunk 2077 folder (the one containing bin\x64\Cyberpunk2077.exe).
    Auto-detected if omitted.

.PARAMETER NexusApiKey
    Nexus Mods personal API key (Premium accounts only). Defaults to the NEXUS_API_KEY
    environment variable. Get one at https://next.nexusmods.com/settings/api-keys

.PARAMETER DownloadsPath
    Folder to watch for browser downloads. Defaults to your Downloads folder.

.PARAMETER SkipNexus
    Install only the GitHub-hosted components and the VR port; print a checklist for the
    three Nexus-only mods instead of fetching them.

.PARAMETER Minimal
    Install ONLY RED4ext (1.31.0+) and the Cyberpunk VR Port (0.2.1+), skipping all optional
    companion mods (Visual Holsters, Equipment-EX, Nova Optics, More Occluders) and the
    external frameworks they require (CET, redscript, TweakXL, ArchiveXL, Codeware, Input Loader).

.PARAMETER Uninstall
    Remove everything this script installed and restore the backed-up originals.

.PARAMETER Force
    Skip the "press Enter to continue" confirmations.

.EXAMPLE
    .\Install-CyberpunkVR.ps1

.EXAMPLE
    .\Install-CyberpunkVR.ps1 -NexusApiKey "abc123..." -Force

.EXAMPLE
    .\Install-CyberpunkVR.ps1 -Minimal

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
    [string] $NexusApiKey = $env:NEXUS_API_KEY,
    [string] $DownloadsPath,
    [switch] $SkipNexus,
    [switch] $Minimal,
    [switch] $Uninstall,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is ~10x faster without it

$ScriptRoot        = Split-Path -Parent $MyInvocation.MyCommand.Definition
$StateDirName      = '_CyberpunkVR_Installer'
$UserAgent         = 'CyberpunkVR-Installer/2.0 (VRPort-0.2.1)'
$NexusGame         = 'cyberpunk2077'
$TargetGameVersion = '2.5'

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
    @{ Name = 'Equipment-EX';       Repo = 'psiberx/cp2077-equipment-ex';              Pattern = '^EquipmentEx-.*\.zip$' }
)

$GitHubComponents = if ($Minimal) {
    $CoreGitHubComponents
} else {
    $CoreGitHubComponents + $FrameworkGitHubComponents
}

# Installed last, after every dependency is in place.
$VrPort = @{ Name = 'Cyberpunk VR Port'; Repo = 'dariulone/cyberpunk-vr-port'; Pattern = '^CyberpunkVRPort-.*\.zip$' }

# Nexus-only companion mods required by the full setup in v0.2.1:
# - Visible Bullets (22251) was removed in v0.1.9.
# - More Occluders (Scripted v0.3) (33136) was added in v0.1.7.
$NexusComponents = @(
    @{
        Name         = 'Visual Holsters (Automatic Clothes Swap)'
        ModId        = 21936
        MatchPattern = '(?i)(visual.*holster|automatic.*clothes.*swap|(?<!\d)21936(?!\d))'
    }
    @{
        Name         = 'Nova Optics'
        ModId        = 29190
        MatchPattern = '(?i)(nova.*optic|(?<!\d)29190(?!\d))'
    }
    @{
        Name         = 'More Occluders (Scripted v0.3)'
        ModId        = 33136
        MatchPattern = '(?i)(more.*occluder|(?<!\d)33136(?!\d))'
    }
)

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

function Backup-AndRemoveItem ($gameRoot, $relativePath, $state) {
    $target = Join-Path $gameRoot $relativePath
    if (-not (Test-Path -LiteralPath $target)) { return 0 }

    $item = Get-Item -LiteralPath $target -Force
    if ($item.PSIsContainer) {
        $files = @(Get-ChildItem -LiteralPath $target -Recurse -File -Force -ErrorAction SilentlyContinue)
        $count = 0
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($gameRoot.Length).TrimStart('\')
            $bk  = Join-Path $state.BackupDir $rel
            if (-not (Test-Path -LiteralPath $bk)) {
                $bkDir = Split-Path -Parent $bk
                if (-not (Test-Path -LiteralPath $bkDir)) { New-Item -ItemType Directory -Path $bkDir -Force | Out-Null }
                Copy-Item -LiteralPath $f.FullName -Destination $bk -Force
            }
            $count++
        }
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        return $count
    } else {
        $bk = Join-Path $state.BackupDir $relativePath
        if (-not (Test-Path -LiteralPath $bk)) {
            $bkDir = Split-Path -Parent $bk
            if (-not (Test-Path -LiteralPath $bkDir)) { New-Item -ItemType Directory -Path $bkDir -Force | Out-Null }
            Copy-Item -LiteralPath $target -Destination $bk -Force
        }
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

    # 2. Folders retired in <= 0.2.1 that MUST NOT coexist with red4ext\plugins\cyberpunkvrport:
    #    - CyberpunkVR_Stereo: causes 0.2.0+ plugin to stay off and refuse to load.
    #    - CyberpunkVR_Hands: causes a crash at 0xFFFFFFFFFFFFFFFF due to double-hooking.
    #    - r6\tweaks\vrport & vrcigarette: now in red4ext\plugins\cyberpunkvrport\config\tweaks.
    #    - QuickBoot dev tool folders.
    $retiredDirs = @(
        'red4ext\plugins\CyberpunkVR_Stereo',
        'red4ext\plugins\CyberpunkVR_Hands',
        'r6\tweaks\vrport',
        'r6\tweaks\vrcigarette',
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

    # 3. Loose files retired across 0.1.0 -> 0.2.1:
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

    $cleaned = 0
    foreach ($relDir in ($retiredDirs | Select-Object -Unique)) {
        $n = Backup-AndRemoveItem $gameRoot $relDir $state
        if ($n -gt 0) {
            Write-Ok "Retired legacy folder: $relDir ($n file(s) backed up)"
            $cleaned += $n
        }
    }
    foreach ($relFile in ($retiredFiles | Select-Object -Unique)) {
        $n = Backup-AndRemoveItem $gameRoot $relFile $state
        if ($n -gt 0) {
            Write-Ok "Retired legacy file: $relFile (backed up)"
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

        if (Test-Path $target) {
            $backupTarget = Join-Path $state.BackupDir $relative
            if (-not (Test-Path $backupTarget)) {
                $backupDir = Split-Path -Parent $backupTarget
                if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
                Copy-Item -LiteralPath $target -Destination $backupTarget -Force
                $backedUp++
            }
        }

        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        $installed++
        if ($state.Files -notcontains $relative) { $state.Files += $relative }
    }

    $msg = "$componentName : $installed file(s) installed"
    if ($backedUp -gt 0) { $msg += ", $backedUp existing file(s) backed up" }
    Write-Ok $msg
}

# A few Nexus archives are just loose .archive / .reds files with no folder structure.
# Put those where the game expects them before copying.
function Repair-LooseFiles ($root) {
    $markers = @('bin', 'r6', 'red4ext', 'archive', 'engine', 'mods', 'plugins')
    $dirs = @(Get-ChildItem -LiteralPath $root -Directory -Force)
    if ($dirs | Where-Object { $markers -contains $_.Name.ToLower() }) { return }

    $moves = @(
        @{ Ext = @('.archive', '.xl'); Dest = 'archive\pc\mod' }
        @{ Ext = @('.reds');           Dest = 'r6\scripts' }
        @{ Ext = @('.tweak', '.yaml'); Dest = 'r6\tweaks' }
        @{ Ext = @('.xml');            Dest = 'r6\input' }
    )
    foreach ($m in $moves) {
        $hits = @(Get-ChildItem -LiteralPath $root -File -Force | Where-Object { $m.Ext -contains $_.Extension.ToLower() })
        if ($hits.Count -eq 0) { continue }
        $dest = Join-Path $root $m.Dest
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $hits | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $dest -Force }
    }
}

function Install-Archive ($archivePath, $gameRoot, $componentName, $state, $workDir) {
    $stage = Join-Path $workDir ("stage_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Expand-AnyArchive $archivePath $stage
        $root = Find-ArchiveRoot $stage
        Repair-LooseFiles $root
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
# Nexus Mods
# --------------------------------------------------------------------------------------

function Invoke-NexusApi ($path, $apiKey) {
    $headers = @{ apikey = $apiKey; 'User-Agent' = $UserAgent; 'Accept' = 'application/json' }
    return Invoke-RestMethod -Uri "https://api.nexusmods.com/v1/$path" -Headers $headers -TimeoutSec 60
}

function Test-NexusPremium ($apiKey) {
    try {
        $me = Invoke-NexusApi 'users/validate.json' $apiKey
        return [bool]$me.is_premium
    } catch {
        return $false
    }
}

function Get-NexusDownloadUrl ($modId, $apiKey) {
    $files = Invoke-NexusApi "games/$NexusGame/mods/$modId/files.json?category=main" $apiKey
    $candidates = @($files.files | Where-Object { $_.category_name -eq 'MAIN' })
    if ($candidates.Count -eq 0) { $candidates = @($files.files) }
    if ($candidates.Count -eq 0) { throw "No files listed for mod $modId." }

    $primary = @($candidates | Where-Object { $_.is_primary }) | Select-Object -First 1
    if (-not $primary) { $primary = $candidates | Sort-Object uploaded_timestamp -Descending | Select-Object -First 1 }

    $links = Invoke-NexusApi "games/$NexusGame/mods/$modId/files/$($primary.file_id)/download_link.json" $apiKey
    return @{ Url = $links[0].URI; FileName = $primary.file_name }
}

function Get-DownloadsFolder {
    if ($DownloadsPath) { return $DownloadsPath }
    try {
        $p = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($p -and (Test-Path $p)) { return $p }
    } catch { }
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Get-ArchiveSnapshot ($folder) {
    if (-not (Test-Path $folder)) { return @{} }
    $map = @{}
    foreach ($f in Get-ChildItem $folder -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Extension -match '(?i)^\.(zip|7z|rar)$' }) {
        $map[$f.FullName] = $f.LastWriteTimeUtc
    }
    return $map
}

function Wait-ForStableFile ($path) {
    $last = -1
    for ($i = 0; $i -lt 120; $i++) {
        try { $size = (Get-Item $path -ErrorAction Stop).Length } catch { Start-Sleep 1; continue }
        if ($size -gt 0 -and $size -eq $last) { return $true }
        $last = $size
        Start-Sleep 1
    }
    return $false
}

function Install-NexusComponent ($component, $gameRoot, $state, $workDir, $apiKey, $usePremium) {
    $modUrl = "https://www.nexusmods.com/$NexusGame/mods/$($component.ModId)?tab=files"

    # Path A: already sitting in ManualDownloads next to the script.
    $manualDir = Join-Path $ScriptRoot 'ManualDownloads'
    if (Test-Path $manualDir) {
        $pattern = if ($component.MatchPattern) { $component.MatchPattern } else { [regex]::Escape(($component.Name -split '[ (]')[0]) }
        $hit = Get-ChildItem $manualDir -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -match '(?i)^\.(zip|7z|rar)$' -and $_.BaseName -match $pattern } |
               Sort-Object LastWriteTimeUtc -Descending |
               Select-Object -First 1
        if ($hit) {
            Write-Step "$($component.Name) - using $($hit.Name) from ManualDownloads"
            Install-Archive $hit.FullName $gameRoot $component.Name $state $workDir
            return $true
        }
    }

    # Path B: Premium API key -> fully automatic.
    if ($usePremium) {
        try {
            Write-Step "$($component.Name) - requesting download link from Nexus API..."
            $dl = Get-NexusDownloadUrl $component.ModId $apiKey
            $file = Join-Path $workDir $dl.FileName
            Write-Step "$($component.Name) - downloading $($dl.FileName)"
            Invoke-Download $dl.Url $file
            Install-Archive $file $gameRoot $component.Name $state $workDir
            return $true
        } catch {
            Write-Note "Nexus API download failed ($($_.Exception.Message)). Falling back to the browser."
        }
    }

    # Path C: browser handoff.
    $downloads = Get-DownloadsFolder
    Write-Host ""
    Write-Host "   $($component.Name)" -ForegroundColor White
    Write-Host "   Opening: $modUrl" -ForegroundColor Gray
    Write-Host "   In the browser: click the MAIN file's 'Manual Download', then 'Slow download'." -ForegroundColor Gray
    Write-Host "   Watching for new archives in: $downloads" -ForegroundColor Gray

    $before = Get-ArchiveSnapshot $downloads
    try { Start-Process $modUrl } catch { Write-Note "Could not open a browser. Open the URL above manually." }

    Write-Host ""
    $answer = Read-Host "   Press Enter when the download has finished (or type S to skip this mod)"
    if ($answer -match '^(s|skip)$') {
        Write-Note "$($component.Name) skipped. Some VR features may not work without it."
        return $false
    }

    $after = Get-ArchiveSnapshot $downloads
    $new = @($after.Keys | Where-Object { -not $before.ContainsKey($_) -or $before[$_] -ne $after[$_] })

    if ($new.Count -eq 0) {
        Write-Note "No new archive appeared in $downloads."
        $manual = Read-Host "   Paste the full path to the downloaded archive (or Enter to skip)"
        if ([string]::IsNullOrWhiteSpace($manual)) { return $false }
        $new = @($manual.Trim('"'))
    }

    $ok = $false
    foreach ($n in $new) {
        if (-not (Test-Path $n)) { Write-Note "Not found: $n"; continue }
        Wait-ForStableFile $n | Out-Null
        Install-Archive $n $gameRoot $component.Name $state $workDir
        $ok = $true
    }
    return $ok
}

# --------------------------------------------------------------------------------------
# Uninstall
# --------------------------------------------------------------------------------------

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

    # Also remove runtime-generated files created by CyberpunkVRPort 0.2.1+
    $runtimeFiles = @(
        'bin\x64\vrport.ini',
        'bin\x64\vrport-launcher.ini',
        'bin\x64\cyberpunkvrport.log',
        'r6\input\CyberpunkVRPort_ScannerHud.xml'
    )
    foreach ($rf in $runtimeFiles) {
        $p = Join-Path $gameRoot $rf
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    foreach ($rd in @('red4ext\plugins\cyberpunkvrport\log', 'red4ext\plugins\cyberpunkvrport\config\input\merged')) {
        $p = Join-Path $gameRoot $rd
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Ok "$removed file(s) removed"

    if ($m.BackupDir -and (Test-Path $m.BackupDir)) {
        $restored = 0
        $backupRoot = (Resolve-Path $m.BackupDir).Path
        foreach ($f in Get-ChildItem $backupRoot -Recurse -File -Force) {
            $rel = $f.FullName.Substring($backupRoot.Length).TrimStart('\')
            $target = Join-Path $gameRoot $rel
            $dir = Split-Path -Parent $target
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $f.FullName -Destination $target -Force
            $restored++
        }
        Write-Ok "$restored original file(s) restored from backup"
    }

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
Write-Host "  Cyberpunk 2077 VR Port (v0.2.1+) - automatic installer" -ForegroundColor Magenta
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
        Write-Ok "Game version $version (matches Cyberpunk 2077 $TargetGameVersion required by VR Port 0.2.1)"
    } else {
        Write-Note "Game version reads as $version. VR Port 0.2.1 requires Cyberpunk 2077 $TargetGameVersion (2.31 is no longer supported and the plugin will refuse to hook on mismatched builds)."
    }
} else {
    Write-Note "Could not read the game version. VR Port 0.2.1 requires Cyberpunk 2077 $TargetGameVersion."
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
if ($Minimal) { $SkipNexus = $true }

$usePremium = $false
if (-not $SkipNexus -and $NexusApiKey) {
    Write-Step "Validating Nexus API key..."
    if (Test-NexusPremium $NexusApiKey) {
        $usePremium = $true
        Write-Ok "Nexus Premium detected - the three Nexus-only mods will download automatically."
    } else {
        Write-Note "That key works but the account isn't Premium. Nexus only allows API downloads for Premium members, so those three will go through your browser."
    }
}

Write-Head "Plan"
if ($Minimal) {
    Write-Host "   Mode: MINIMAL (Standalone VR Port 0.2.1+ with built-in Lua/redscript/Archive/Tweak host)" -ForegroundColor Yellow
}
Write-Host "   From GitHub (fully automatic):" -ForegroundColor Gray
$GitHubComponents | ForEach-Object { Write-Host "     - $($_.Name)" -ForegroundColor DarkGray }
Write-Host "     - $($VrPort.Name)" -ForegroundColor DarkGray
if (-not $SkipNexus) {
    Write-Host "   From Nexus ($(if ($usePremium) { 'automatic' } else { 'ManualDownloads / browser handoff' })):" -ForegroundColor Gray
    $NexusComponents | ForEach-Object { Write-Host "     - $($_.Name) (Mod $($_.ModId))" -ForegroundColor DarkGray }
}
Write-Host ""
Write-Host "   Anything overwritten or retired is backed up. Re-run later to update; -Uninstall to revert." -ForegroundColor DarkGray

Confirm-Continue "Ready to install"

# --- State ------------------------------------------------------------------------------
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$stateDir = Join-Path $GamePath $StateDirName
$workDir  = Join-Path $env:TEMP "cpvr_$stamp"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
New-Item -ItemType Directory -Path $workDir  -Force | Out-Null

$state = [ordered]@{
    InstalledAt = (Get-Date).ToString('s')
    GamePath    = $GamePath
    BackupDir   = (Join-Path $stateDir "backup-$stamp")
    MinimalMode = [bool]$Minimal
    Files       = @()
    Versions    = [ordered]@{}
}
New-Item -ItemType Directory -Path $state.BackupDir -Force | Out-Null

$failed = @()

try {
    # --- Clean up legacy VR builds (<= 0.1.9) --------------------------------------------
    Write-Head "Checking for legacy VR Port files"
    Clear-LegacyVrPortInstall $GamePath $state

    # --- GitHub dependencies -------------------------------------------------------------
    Write-Head "Installing dependencies from GitHub"
    foreach ($c in $GitHubComponents) {
        try { Install-FromGitHub $c $GamePath $state $workDir }
        catch { Write-Bad "$($c.Name) failed: $($_.Exception.Message)"; $failed += $c.Name }
    }

    # --- Nexus-only mods ------------------------------------------------------------------
    if (-not $SkipNexus) {
        Write-Head "Installing Nexus-only mods"
        foreach ($c in $NexusComponents) {
            try {
                if (-not (Install-NexusComponent $c $GamePath $state $workDir $NexusApiKey $usePremium)) { $failed += $c.Name }
            } catch { Write-Bad "$($c.Name) failed: $($_.Exception.Message)"; $failed += $c.Name }
        }
    }

    # --- The VR port itself ----------------------------------------------------------------
    Write-Head "Installing the VR port"
    try { Install-FromGitHub $VrPort $GamePath $state $workDir }
    catch { Write-Bad "$($VrPort.Name) failed: $($_.Exception.Message)"; $failed += $VrPort.Name }

} finally {
    $state.Files = @($state.Files | Select-Object -Unique)
    $state | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $stateDir 'manifest.json') -Encoding UTF8
    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Verify -------------------------------------------------------------------------------
Write-Head "Verifying"
$expected = @(
    @{ Path = 'red4ext\RED4ext.dll';                                                    What = 'RED4ext loader' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\cyberpunkvrport.dll';                    What = 'VR Port core plugin (cyberpunkvrport.dll)' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\redscript\scc_lib.dll';                  What = 'VR Port built-in redscript compiler' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\archive\cyberpunkvrport.archive';        What = 'VR Port packed assets archive' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\config\archive.yaml';                    What = 'VR Port archive manifest' }
    @{ Path = 'red4ext\plugins\cyberpunkvrport\config\UserSettings.json';               What = 'VR Port first-launch settings preset' }
    @{ Path = 'bin\x64\openvr_api.dll';                                                 What = 'OpenVR API shim' }
)

if (-not $Minimal) {
    $expected += @(
        @{ Path = 'bin\x64\plugins\cyber_engine_tweaks.asi';                            What = 'Cyber Engine Tweaks' }
        @{ Path = 'engine\tools\scc.exe';                                               What = 'redscript compiler' }
        @{ Path = 'red4ext\plugins\ArchiveXL\ArchiveXL.dll';                            What = 'ArchiveXL' }
        @{ Path = 'red4ext\plugins\TweakXL\TweakXL.dll';                                What = 'TweakXL' }
        @{ Path = 'red4ext\plugins\Codeware\Codeware.dll';                              What = 'Codeware' }
        @{ Path = 'red4ext\plugins\input_loader\input_loader.dll';                      What = 'Input Loader' }
        @{ Path = 'r6\scripts\EquipmentEx\EquipmentEx.reds';                            What = 'Equipment-EX' }
    )
}

$missing = @()
foreach ($e in $expected) {
    if (Test-Path (Join-Path $GamePath $e.Path)) { Write-Ok "$($e.What)" }
    else { Write-Bad "missing: $($e.Path)  ($($e.What))"; $missing += $e.What }
}

# Verify that conflicting legacy plugin folders are NOT present
foreach ($conflict in @('red4ext\plugins\CyberpunkVR_Stereo', 'red4ext\plugins\CyberpunkVR_Hands', 'bin\x64\dxgi.dll')) {
    if (Test-Path (Join-Path $GamePath $conflict)) {
        Write-Bad "conflicting legacy path still present: $conflict (remove it before launching!)"
    }
}

# --- Summary --------------------------------------------------------------------------------
Write-Head "Done"
if ($state.Versions.Count -gt 0) {
    Write-Host "   Installed versions:" -ForegroundColor Gray
    $state.Versions.GetEnumerator() | ForEach-Object { Write-Host ("     {0,-22} {1}" -f $_.Key, $_.Value) -ForegroundColor DarkGray }
}
Write-Host "   Backups: $($state.BackupDir)" -ForegroundColor DarkGray

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Note "These did not install: $($failed -join ', ')"
    Write-Host "   Install them by hand (or place them in ManualDownloads), then re-run this script." -ForegroundColor Gray
}

Write-Host ""
Write-Host "  BEFORE YOU PLAY (VR Port 0.2.1+)" -ForegroundColor Yellow
Write-Host "   1. Start your OpenXR runtime (Virtual Desktop VDXR / SteamVR / Meta Quest Link) FIRST." -ForegroundColor Gray
Write-Host "   2. Launch bin\x64\Cyberpunk2077.exe. In the pre-launch VR window, pick your headset" -ForegroundColor Gray
Write-Host "      model and per-eye render resolution (leave DEBUG unchecked for normal play)." -ForegroundColor Gray
Write-Host "   3. On first launch, the VR port automatically merges its optimal VR graphics/input/HUD" -ForegroundColor Gray
Write-Host "      preset into UserSettings.json (saving a backup as UserSettings.pre-vr-*.json)" -ForegroundColor Gray
Write-Host "      and guides you through weapon-hand, T-pose, and height calibration in the VR lobby." -ForegroundColor Gray
Write-Host "   4. In game: Hold L3 + R3 (0.5 s) for the holographic VR menu, F10 / Insert for the" -ForegroundColor Gray
Write-Host "      in-headset settings overlay, F7 to recenter, Home / Scroll Lock for Lua windows." -ForegroundColor Gray
Write-Host ""
Write-Host "   Re-run this script any time to update. Run with -Uninstall to revert." -ForegroundColor DarkGray
Write-Host ""

if (-not $Force) { Read-Host "Press Enter to close" | Out-Null }
