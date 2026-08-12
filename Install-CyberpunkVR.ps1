<#
.SYNOPSIS
    One-click installer for the Cyberpunk 2077 VR Port (Nexus mod 30093) and all of its
    required dependencies.

.DESCRIPTION
    Finds your Cyberpunk 2077 installation, downloads every dependency that is published
    on GitHub (RED4ext, Cyber Engine Tweaks, redscript, TweakXL, ArchiveXL, Codeware,
    Equipment-EX) plus the VR port itself, and installs them into the game folder.

    Three required mods are only distributed on Nexus Mods (Visual Holsters, Visible
    Bullets, Nova Optics). Nexus only hands out direct download links to Premium
    accounts, so:
      * If you supply a Nexus API key from a Premium account, those are downloaded
        automatically too.
      * Otherwise the script opens each mod page in your browser, you click "Manual
        Download", and the script picks the archive up out of your Downloads folder and
        installs it for you.
      * Or you can pre-download them yourself and drop the archives into the
        "ManualDownloads" folder next to this script.

    Everything it overwrites is backed up first, and -Uninstall puts it all back.

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

.PARAMETER Uninstall
    Remove everything this script installed and restore the backed-up originals.

.PARAMETER Force
    Skip the "press Enter to continue" confirmations.

.EXAMPLE
    .\Install-CyberpunkVR.ps1

.EXAMPLE
    .\Install-CyberpunkVR.ps1 -NexusApiKey "abc123..." -Force

.EXAMPLE
    .\Install-CyberpunkVR.ps1 -Uninstall

.NOTES
    Mod page : https://www.nexusmods.com/cyberpunk2077/mods/30093
    Source   : https://github.com/dariulone/cyberpunk-vr-port
    Requires : Windows, PowerShell 5.1+, Cyberpunk 2077 v2.31, an OpenXR runtime.
#>

[CmdletBinding()]
param(
    [string] $GamePath,
    [string] $NexusApiKey = $env:NEXUS_API_KEY,
    [string] $DownloadsPath,
    [switch] $SkipNexus,
    [switch] $Uninstall,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is ~10x faster without it

$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$StateDirName = '_CyberpunkVR_Installer'
$UserAgent    = 'CyberpunkVR-Installer/1.0'
$NexusGame    = 'cyberpunk2077'

# --------------------------------------------------------------------------------------
# What gets installed, in order. Every one of these archives extracts to the game root.
# --------------------------------------------------------------------------------------

$GitHubComponents = @(
    @{ Name = 'RED4ext';            Repo = 'WopsS/RED4ext';               Pattern = '^red4ext-[\d.]+\.zip$' }
    @{ Name = 'Cyber Engine Tweaks';Repo = 'maximegmd/CyberEngineTweaks'; Pattern = '^cet_.*\.zip$' }
    @{ Name = 'redscript';          Repo = 'jac3km4/redscript';           Pattern = 'windows\.zip$' }
    @{ Name = 'TweakXL';            Repo = 'psiberx/cp2077-tweak-xl';     Pattern = '^TweakXL-.*\.zip$' }
    @{ Name = 'ArchiveXL';          Repo = 'psiberx/cp2077-archive-xl';   Pattern = '^ArchiveXL-.*\.zip$' }
    @{ Name = 'Codeware';           Repo = 'psiberx/cp2077-codeware';     Pattern = '^Codeware-.*\.zip$' }
    @{ Name = 'Equipment-EX';       Repo = 'psiberx/cp2077-equipment-ex'; Pattern = '^EquipmentEx-.*\.zip$' }
)

# Installed last, after every dependency is in place.
$VrPort = @{ Name = 'Cyberpunk VR Port'; Repo = 'dariulone/cyberpunk-vr-port'; Pattern = '^CyberpunkVRPort-.*\.zip$' }

$NexusComponents = @(
    @{ Name = 'Visual Holsters (Automatic Clothes Swap)'; ModId = 21936 }
    @{ Name = 'Visible Bullets (Projectile Restoration)'; ModId = 22251 }
    @{ Name = 'Nova Optics';                              ModId = 29190 }
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
            if ($v -and $v -match '(\d+\.\d+)') { return $Matches[1] }
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
        $junk = @($files | Where-Object { $_.Extension -notmatch '(?i)^\.(dll|asi|exe|archive|xl|reds|lua|json|ini|toml)$' })
        if ($dirs.Count -eq 1 -and $files.Count -eq $junk.Count) {
            $current = $dirs[0].FullName
            continue
        }
        return $current
    }
    return $current
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
        $token = ($component.Name -split '[ (]')[0]
        $hit = Get-ChildItem $manualDir -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -match '(?i)^\.(zip|7z|rar)$' -and $_.BaseName -replace '[^a-z0-9]','' -match ($token -replace '[^a-z0-9]','') } |
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
        Write-Note "$($component.Name) skipped. The VR port will not work correctly without it."
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
        if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue; $removed++ }
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
    foreach ($d in @('red4ext\plugins', 'bin\x64\plugins\cyber_engine_tweaks\mods', 'r6\scripts', 'archive\pc\mod')) {
        $p = Join-Path $gameRoot $d
        if (Test-Path $p) {
            Get-ChildItem $p -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending |
                Where-Object { -not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue) } |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
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
Write-Host "  Cyberpunk 2077 VR Port - automatic installer" -ForegroundColor Magenta
Write-Host "  https://www.nexusmods.com/cyberpunk2077/mods/30093" -ForegroundColor DarkGray
Write-Host ""

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Stop-WithError "PowerShell 5.1 or newer is required. Yours is $($PSVersionTable.PSVersion)."
}

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
    if ($version -eq '2.31') { Write-Ok "Game version $version (matches what the mod targets)" }
    else { Write-Note "Game version reads as $version. This mod targets 2.31 - expect problems on other versions." }
} else {
    Write-Note "Could not read the game version. The mod targets 2.31."
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
Write-Host "   From GitHub (fully automatic):" -ForegroundColor Gray
$GitHubComponents | ForEach-Object { Write-Host "     - $($_.Name)" -ForegroundColor DarkGray }
Write-Host "     - $($VrPort.Name)" -ForegroundColor DarkGray
if (-not $SkipNexus) {
    Write-Host "   From Nexus ($(if ($usePremium) { 'automatic' } else { 'browser handoff' })):" -ForegroundColor Gray
    $NexusComponents | ForEach-Object { Write-Host "     - $($_.Name)" -ForegroundColor DarkGray }
}
Write-Host ""
Write-Host "   Anything overwritten is backed up. Re-run later to update; -Uninstall to revert." -ForegroundColor DarkGray

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
    Files       = @()
    Versions    = [ordered]@{}
}
New-Item -ItemType Directory -Path $state.BackupDir -Force | Out-Null

$failed = @()

try {
    # --- Remove a stale dxgi.dll from an earlier VR build --------------------------------
    $dxgi = Join-Path $GamePath 'bin\x64\dxgi.dll'
    if (Test-Path $dxgi) {
        Write-Head "Clearing previous VR build"
        $bk = Join-Path $state.BackupDir 'bin\x64\dxgi.dll'
        New-Item -ItemType Directory -Path (Split-Path $bk) -Force | Out-Null
        Move-Item $dxgi $bk -Force
        Write-Ok "Existing bin\x64\dxgi.dll moved to backup (the mod requires this)"
    }

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
    @{ Path = 'bin\x64\dxgi.dll';                                         What = 'VR proxy (head tracking / stereo)' }
    @{ Path = 'red4ext\plugins\CyberpunkVR_Hands\CyberpunkVR_Hands.dll';  What = 'VR hands / avatar plugin' }
    @{ Path = 'red4ext\RED4ext.dll';                                      What = 'RED4ext' }
    @{ Path = 'bin\x64\plugins\cyber_engine_tweaks.asi';                  What = 'Cyber Engine Tweaks' }
    @{ Path = 'engine\tools\scc.exe';                                     What = 'redscript compiler' }
    @{ Path = 'red4ext\plugins\ArchiveXL\ArchiveXL.dll';                  What = 'ArchiveXL' }
    @{ Path = 'red4ext\plugins\TweakXL\TweakXL.dll';                      What = 'TweakXL' }
    @{ Path = 'red4ext\plugins\Codeware\Codeware.dll';                    What = 'Codeware' }
)
$missing = @()
foreach ($e in $expected) {
    if (Test-Path (Join-Path $GamePath $e.Path)) { Write-Ok "$($e.What)" }
    else { Write-Bad "missing: $($e.Path)  ($($e.What))"; $missing += $e.What }
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
    Write-Host "   Install them by hand, then re-run this script." -ForegroundColor Gray
}

Write-Host ""
Write-Host "  BEFORE YOU PLAY" -ForegroundColor Yellow
Write-Host "   1. Launch the game flat (no VR) once so CET and redscript finish setting up." -ForegroundColor Gray
Write-Host "   2. In Settings > Graphics set the preset to Low, and turn OFF:" -ForegroundColor Gray
Write-Host "      Film Grain, Chromatic Aberration, Motion Blur, Lens Flare," -ForegroundColor Gray
Write-Host "      Depth of Field and Frame Generation." -ForegroundColor Gray
Write-Host "   3. Start your OpenXR runtime (SteamVR / Oculus / Virtual Desktop / WMR) FIRST." -ForegroundColor Gray
Write-Host "   4. Run bin\x64\Cyberpunk2077.exe and pick render resolution + runtime in the launcher." -ForegroundColor Gray
Write-Host "   5. In game: F10 opens the VR menu, F7 recenters your view." -ForegroundColor Gray
Write-Host ""
Write-Host "   Re-run this script any time to update. Run with -Uninstall to revert." -ForegroundColor DarkGray
Write-Host ""

if (-not $Force) { Read-Host "Press Enter to close" | Out-Null }
