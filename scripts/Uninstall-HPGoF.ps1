<#
    Uninstall-HPGoF.ps1
    Reverts everything Install-HPGoF.ps1 changed.

    Removes the Desktop and Start Menu shortcuts, the high-DPI compatibility
    flag, and the game's registry key. Game files are left in place unless you
    pass -RemoveFiles.

    Parameters
    ----------
    -Dest         Install directory. Default: C:\Program Files (x86)\Electronic Arts\Harry Potter and the Goblet of Fire
    -RemoveFiles  Also delete the install directory.

    Usage:  right-click > Run with PowerShell
            powershell -File Uninstall-HPGoF.ps1 -RemoveFiles
#>

[CmdletBinding()]
param(
    [string]$Dest = "${env:ProgramFiles(x86)}\Electronic Arts\Harry Potter and the Goblet of Fire",
    [switch]$RemoveFiles
)

$ErrorActionPreference = 'Stop'

# self-elevate: removing the HKLM key needs admin
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Dest',"`"$Dest`"")
    if ($RemoveFiles) { $a += '-RemoveFiles' }
    Start-Process powershell -Verb RunAs -ArgumentList $a
    return
}

Write-Host "Harry Potter and the Goblet of Fire - uninstall" -ForegroundColor Cyan

# shortcuts
foreach ($dir in @([Environment]::GetFolderPath('Desktop'),
                    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))) {
    $lnk = Join-Path $dir 'Harry Potter and the Goblet of Fire.lnk'
    if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host "  removed shortcut: $lnk" -ForegroundColor Green }
}

# high-DPI compatibility flag
$exe    = Join-Path $Dest 'gof_f.exe'
$layers = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
if ((Test-Path $layers) -and (Get-ItemProperty $layers).PSObject.Properties.Name -contains $exe) {
    Remove-ItemProperty $layers -Name $exe
    Write-Host "  removed compatibility flag" -ForegroundColor Green
}

# registry key
$k = 'HKLM:\SOFTWARE\WOW6432Node\Electronic Arts\Harry Potter and the Goblet of Fire'
if (Test-Path $k) { Remove-Item $k -Recurse -Force; Write-Host "  removed registry key" -ForegroundColor Green }

# game files
if ($RemoveFiles -and (Test-Path $Dest)) {
    Remove-Item $Dest -Recurse -Force
    Write-Host "  deleted install directory: $Dest" -ForegroundColor Green
} elseif (Test-Path $Dest) {
    Write-Host "  left game files in place ($Dest); pass -RemoveFiles to delete them" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Uninstall complete." -ForegroundColor Cyan
