<#
    Install-HPGoF.ps1
    Manual installer for "Harry Potter and the Goblet of Fire" (EA, 2005).

    Replicates what the disc's AutoRun installer does, but without running it
    (the retail installer hangs on modern Windows). The game ships on TWO discs:
      - Disc 1: 0compressed.zip  (data.big, music.big, the executable, ...)
      - Disc 2: 1compressed.zip  (speech.big, movies.big)
    BOTH must be installed. Disc 2 holds the voice and cutscene audio; skip it
    and the game plays music only.

    This script extracts both payloads, copies the support files, writes the
    registry entries, applies a high-DPI compatibility flag, detects the host's
    native display resolution and applies it to the game, and creates Desktop +
    Start Menu shortcuts.

    Each source may be a drive letter ("E:"), a disc-root folder, an .iso, or a
    raw .bin/.cue disc image (as distributed by archive.org) - the script mounts
    or converts as needed. If a source is omitted it auto-detects a mounted disc
    carrying the matching payload.

    Resolution: the game is hard-coded to 800x600 and has no video options. It
    uses Chip's D3D9 wrapper (d3d9.dll + d3d9.ini), downloaded from its official
    GitHub release, to run at the host resolution. Pass -Resolution WxH to
    override, or -SkipResolution to leave the game at 800x600.

    It installs the disc's own executable as-is. That executable is SafeDisc-
    protected and will NOT launch on Windows 10/11 by itself; obtaining a
    DRM-free build for the copy you own is out of scope here (see README).

    Parameters
    ----------
    -Source          Disc 1 (0compressed.zip): drive, folder, .iso, or .bin/.cue.
    -Source2         Disc 2 (1compressed.zip): drive, folder, .iso, or .bin/.cue.
    -Dest            Install directory. Default: C:\Games\Harry Potter and the Goblet of Fire
    -Resolution      Force a resolution, e.g. "2560x1440". Default: auto-detect.
    -SkipResolution  Do not install the D3D9 wrapper; leave the game at 800x600.

    Usage:   powershell -File Install-HPGoF.ps1 -Source D:\HPGOFDisc1.iso -Source2 D:\HPGOFDisc2.iso
             powershell -File Install-HPGoF.ps1 -Source HPGOFDisc1_Na.cue -Source2 HPGOFDisc2_Na.cue
#>

[CmdletBinding()]
param(
    [string]$Source,
    [string]$Source2,
    [string]$Dest = 'C:\Games\Harry Potter and the Goblet of Fire',
    [string]$Resolution,
    [switch]$SkipResolution
)

$ErrorActionPreference = 'Stop'

# --- self-elevate: registry (HKLM) and ISO mounting need admin ----------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting administrator rights..." -ForegroundColor Yellow
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Source)         { $a += @('-Source',"`"$Source`"") }
    if ($Source2)        { $a += @('-Source2',"`"$Source2`"") }
    $a += @('-Dest',"`"$Dest`"")
    if ($Resolution)     { $a += @('-Resolution',$Resolution) }
    if ($SkipResolution) { $a += '-SkipResolution' }
    Start-Process powershell -Verb RunAs -ArgumentList $a
    return
}

$script:toDismount = @()   # ISO image paths to dismount at the end
$script:toDelete   = @()   # temp .iso files (converted from .bin) to delete

# True physical screen resolution, independent of Windows DPI scaling.
function Get-NativeResolution {
    Add-Type -Name ScrCaps -Namespace HPGoF -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
[DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
[DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr dc, int idx);
'@ -ErrorAction SilentlyContinue
    $dc = [HPGoF.ScrCaps]::GetDC([IntPtr]::Zero)
    try {
        [pscustomobject]@{
            Width  = [HPGoF.ScrCaps]::GetDeviceCaps($dc, 118)   # DESKTOPHORZRES
            Height = [HPGoF.ScrCaps]::GetDeviceCaps($dc, 117)   # DESKTOPVERTRES
        }
    } finally { [void][HPGoF.ScrCaps]::ReleaseDC([IntPtr]::Zero, $dc) }
}

# Convert a raw MODE1/2352 .bin CD image to a 2048-byte/sector .iso.
function Convert-BinToIso {
    param([string]$Bin, [string]$Iso)
    Write-Host "  converting $([IO.Path]::GetFileName($Bin)) to ISO..."
    $in = [IO.File]::OpenRead($Bin); $out = [IO.File]::Create($Iso)
    try {
        $sector = 2352; $userOff = 16; $userLen = 2048
        $buf = New-Object byte[] ($sector * 4096)
        while ($true) {
            # fill the buffer completely so each chunk ends on a sector boundary
            $read = 0
            while ($read -lt $buf.Length) {
                $r = $in.Read($buf, $read, $buf.Length - $read)
                if ($r -le 0) { break }
                $read += $r
            }
            if ($read -eq 0) { break }
            $n = [math]::Floor($read / $sector)
            for ($i = 0; $i -lt $n; $i++) { $out.Write($buf, ($i * $sector) + $userOff, $userLen) }
            if ($read -lt $buf.Length) { break }
        }
    } finally { $in.Dispose(); $out.Dispose() }
}

# Resolve a source spec to a readable filesystem root, mounting/converting as
# needed and registering any cleanup.
function Resolve-Disc {
    param([string]$Spec)
    if (-not $Spec) { return $null }
    $ext = [IO.Path]::GetExtension($Spec).ToLower()

    if ($ext -eq '.bin' -or $ext -eq '.cue') {
        $bin = $Spec
        if ($ext -eq '.cue') {
            $m = (Get-Content $Spec | Select-String -Pattern 'FILE\s+"(.+?)"' | Select-Object -First 1)
            if ($m) { $bin = Join-Path (Split-Path (Resolve-Path $Spec)) $m.Matches[0].Groups[1].Value }
        }
        $iso = Join-Path $env:TEMP ("hpgof_" + [IO.Path]::GetFileNameWithoutExtension($bin) + ".iso")
        Convert-BinToIso -Bin (Resolve-Path $bin) -Iso $iso
        $script:toDelete += $iso
        $Spec = $iso; $ext = '.iso'
    }

    if ($ext -eq '.iso') {
        $img = (Resolve-Path $Spec).Path
        $mnt = Mount-DiskImage -ImagePath $img -PassThru
        Start-Sleep -Seconds 2
        $script:toDismount += $img
        return "$(($mnt | Get-Volume).DriveLetter):\"
    }
    if ($Spec -match '^[A-Za-z]:?$') { return "$($Spec.TrimEnd(':')):\" }
    return $Spec   # already a folder root
}

# Find a mounted volume whose root contains the named payload zip.
function Find-Disc {
    param([string]$ZipName)
    Get-Volume |
        Where-Object { $_.DriveLetter } |
        ForEach-Object { "$($_.DriveLetter):\" } |
        Where-Object { Test-Path (Join-Path $_ $ZipName) } |
        Select-Object -First 1
}

# Extract every file from a payload zip on the disc root into the install dir.
function Expand-Payload {
    param([string]$Root, [string]$ZipName, [string]$Dest)
    $zp = Join-Path $Root $ZipName
    if (-not (Test-Path $zp)) { return 0 }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zp)
    try {
        foreach ($e in $zip.Entries) {
            if (-not $e.Name) { continue }
            $t = Join-Path $Dest $e.FullName
            New-Item -ItemType Directory -Force (Split-Path $t) | Out-Null
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $t, $true)
        }
        return $zip.Entries.Count
    } finally { $zip.Dispose() }
}

# Downloads Chip's D3D9 wrapper and writes it into the game folder configured
# for the given resolution and the nearest aspect-ratio preset.
function Set-GameResolution {
    param([string]$Dest, [int]$Width, [int]$Height)
    $ratio   = $Width / $Height
    $presets = @{ 1 = 1.778; 2 = 1.600; 3 = 2.370; 4 = 2.389; 5 = 2.400; 6 = 3.200 }
    $aspect  = ($presets.GetEnumerator() | Sort-Object { [math]::Abs($_.Value - $ratio) } | Select-Object -First 1).Key

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ua  = @{ 'User-Agent' = 'hp4-installer' }
    $api = 'https://api.github.com/repos/Chip-Biscuit/Harry-Potter-and-the-Goblet-of-Fire-PC-Fix/releases/latest'
    $url = ((Invoke-RestMethod $api -Headers $ua).assets |
                Where-Object { $_.name -like '*.zip' } | Select-Object -First 1).browser_download_url
    if (-not $url) { throw "Could not find the D3D9 fix download in the latest release." }

    $zip = Join-Path $env:TEMP 'hp4fix.zip'
    $out = Join-Path $env:TEMP 'hp4fix_extract'
    Invoke-WebRequest $url -OutFile $zip -Headers $ua
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $out)

    $dll = Get-ChildItem $out -Recurse -Filter d3d9.dll | Select-Object -First 1
    $ini = Get-ChildItem $out -Recurse -Filter d3d9.ini | Select-Object -First 1
    if (-not ($dll -and $ini)) { throw "D3D9 fix archive did not contain d3d9.dll/d3d9.ini." }

    $c = Get-Content $ini.FullName -Raw
    $c = [regex]::Replace($c, '(?im)^(\s*width\s*=\s*)\d+',                  "`${1}$Width")
    $c = [regex]::Replace($c, '(?im)^(\s*height\s*=\s*)\d+',                 "`${1}$Height")
    $c = [regex]::Replace($c, '(?im)^(\s*fullscreenaspectratio\s*=\s*)\d+',  "`${1}$aspect")
    [IO.File]::WriteAllText((Join-Path $Dest 'd3d9.ini'), $c)
    Copy-Item $dll.FullName (Join-Path $Dest 'd3d9.dll') -Force
    return "$Width`x$Height (aspect preset $aspect)"
}

Write-Host "Harry Potter and the Goblet of Fire - manual install" -ForegroundColor Cyan

try {
    New-Item -ItemType Directory -Force $Dest | Out-Null

    # --- 1. Disc 1 (0compressed.zip) -----------------------------------------
    $disc1 = Resolve-Disc $Source
    if (-not ($disc1 -and (Test-Path (Join-Path $disc1 '0compressed.zip')))) { $disc1 = Find-Disc '0compressed.zip' }
    if (-not ($disc1 -and (Test-Path (Join-Path $disc1 '0compressed.zip')))) {
        throw "Disc 1 not found (no 0compressed.zip). Provide it with -Source."
    }
    Write-Host "  disc 1: $disc1" -ForegroundColor Green
    $n1 = Expand-Payload -Root $disc1 -ZipName '0compressed.zip' -Dest $Dest
    Write-Host "  extracted $n1 files from 0compressed.zip" -ForegroundColor Green
    foreach ($item in 'Support','eauninstall.exe','gof_icon.ico') {
        $src = Join-Path $disc1 $item
        if (Test-Path $src) { Copy-Item $src $Dest -Recurse -Force }
    }

    # --- 2. Disc 2 (1compressed.zip = speech.big + movies.big) ----------------
    $disc2 = Resolve-Disc $Source2
    if (-not ($disc2 -and (Test-Path (Join-Path $disc2 '1compressed.zip')))) { $disc2 = Find-Disc '1compressed.zip' }
    if ($disc2 -and (Test-Path (Join-Path $disc2 '1compressed.zip'))) {
        Write-Host "  disc 2: $disc2" -ForegroundColor Green
        $n2 = Expand-Payload -Root $disc2 -ZipName '1compressed.zip' -Dest $Dest
        Write-Host "  extracted $n2 files from 1compressed.zip (speech + movies)" -ForegroundColor Green
        $sup2 = Join-Path $disc2 'Support'
        if (Test-Path $sup2) { Copy-Item $sup2 $Dest -Recurse -Force }
    } else {
        Write-Warning "  Disc 2 not found: speech.big and movies.big will be MISSING"
        Write-Warning "  (the game will play music only - no voices or cutscene audio)."
        Write-Warning "  Provide disc 2 with -Source2 and re-run."
    }

    # --- 3. registry entries the game reads ----------------------------------
    $k = 'HKLM:\SOFTWARE\WOW6432Node\Electronic Arts\Harry Potter and the Goblet of Fire\1.0'
    New-Item -Path $k -Force | Out-Null
    Set-ItemProperty $k -Name 'Install Dir'  -Value "$Dest\"
    Set-ItemProperty $k -Name 'CD Drive'     -Value $disc1
    Set-ItemProperty $k -Name 'Locale'       -Value 'en_US'
    Set-ItemProperty $k -Name 'DisplayName'  -Value 'Harry Potter and the Goblet of Fire'
    Set-ItemProperty $k -Name 'Language'     -Value 1 -Type DWord
    Set-ItemProperty $k -Name 'LanguageName' -Value 'English US'
    Write-Host "  wrote registry entries" -ForegroundColor Green

    # --- 4. high-DPI compatibility flag --------------------------------------
    $exe    = Join-Path $Dest 'gof_f.exe'
    $layers = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    if (-not (Test-Path $layers)) { New-Item $layers -Force | Out-Null }
    Set-ItemProperty $layers -Name $exe -Value '~ HIGHDPIAWARE'
    Write-Host "  set high-DPI compatibility flag" -ForegroundColor Green

    # --- 5. detect host resolution and apply it to the game ------------------
    if ($SkipResolution) {
        Write-Host "  resolution: skipped (game stays at 800x600)" -ForegroundColor Gray
    } else {
        try {
            if ($Resolution -match '^\s*(\d+)\s*[xX]\s*(\d+)\s*$') {
                $w = [int]$Matches[1]; $h = [int]$Matches[2]
            } else {
                $nat = Get-NativeResolution; $w = $nat.Width; $h = $nat.Height
            }
            if ($w -gt 0 -and $h -gt 0) {
                $applied = Set-GameResolution -Dest $Dest -Width $w -Height $h
                Write-Host "  applied resolution: $applied" -ForegroundColor Green
            } else { throw "could not determine a valid resolution" }
        } catch {
            Write-Warning "  resolution step skipped ($($_.Exception.Message)). Game will run at 800x600."
        }
    }

    # --- 6. shortcuts ---------------------------------------------------------
    $ws = New-Object -ComObject WScript.Shell
    foreach ($dir in @([Environment]::GetFolderPath('Desktop'),
                        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))) {
        $lnk = $ws.CreateShortcut((Join-Path $dir 'Harry Potter and the Goblet of Fire.lnk'))
        $lnk.TargetPath       = $exe
        $lnk.WorkingDirectory = $Dest
        $lnk.IconLocation     = (Join-Path $Dest 'gof_icon.ico')
        $lnk.Description       = 'Harry Potter and the Goblet of Fire'
        $lnk.Save()
    }
    Write-Host "  created Desktop and Start Menu shortcuts" -ForegroundColor Green

    Write-Host ""
    Write-Host "Installed to: $Dest" -ForegroundColor Cyan
    Write-Host "Note: the disc executable is SafeDisc-protected and will not launch on" -ForegroundColor DarkYellow
    Write-Host "Windows 10/11 on its own (see the SafeDisc note in the README)." -ForegroundColor DarkYellow
}
finally {
    foreach ($img in $script:toDismount) { Dismount-DiskImage -ImagePath $img -ErrorAction SilentlyContinue | Out-Null }
    foreach ($f   in $script:toDelete)   { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    if ($script:toDismount) { Write-Host "  dismounted disc image(s)" }
}
