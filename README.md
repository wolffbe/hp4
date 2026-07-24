# Harry Potter and the Goblet of Fire — Windows 10/11 Installer

PowerShell scripts that install EA's 2005 game *Harry Potter and the Goblet of
Fire* on modern Windows, where the original disc installer hangs and never
completes.

## The problem

The disc's AutoRun installer freezes indefinitely (observed stuck on
`eauninstall.exe` at 0% CPU) on Windows 10/11 and never finishes.
`Install-HPGoF.ps1` bypasses it by extracting the game payloads directly and
writing the same files, registry values, and shortcuts the installer would have.

The game ships on **two discs**, and both are required:

- **Disc 1** — `0compressed.zip`: `data.big`, `music.big`, the executable, support files
- **Disc 2** — `1compressed.zip`: `speech.big`, `movies.big`

Disc 2 holds the **voice and cutscene audio**. Install Disc 1 only and the game
plays music with no speech — so pass both discs.

## Getting the game

These scripts contain no game files. You need copies of the retail discs you own.
Disc images are archived here:

- https://archive.org/details/harry-potter-and-the-goblet-of-fire-windows-pc-game

Each `-Source` may be a drive letter, a disc-root folder, an `.iso`, or a raw
`.bin`/`.cue` image (the format archive.org distributes) — the script mounts or
converts as needed.

## Usage

```powershell
# Install from both discs. Sources can be .iso, .bin/.cue, a mounted drive,
# or a folder:
powershell -ExecutionPolicy Bypass -File scripts\Install-HPGoF.ps1 -Source HPGOFDisc1_Na.cue -Source2 HPGOFDisc2_Na.cue

# ...or from two mounted discs / ISOs:
powershell -ExecutionPolicy Bypass -File scripts\Install-HPGoF.ps1 -Source E:\ -Source2 F:\

# To revert everything:
powershell -ExecutionPolicy Bypass -File scripts\Uninstall-HPGoF.ps1 -RemoveFiles
```

The default install directory is
`C:\Program Files (x86)\Electronic Arts\Harry Potter and the Goblet of Fire`
(override with `-Dest`).

If a source is omitted, the script auto-detects a mounted disc carrying the
matching payload.

Both scripts self-elevate (UAC prompt) because they write machine-wide registry
keys.

## What the scripts do

### `scripts/Install-HPGoF.ps1`
- Resolves each source (drive, folder, `.iso`, or `.bin`/`.cue`), mounting or
  converting disc images as needed.
- Extracts `0compressed.zip` (Disc 1) **and** `1compressed.zip` (Disc 2) into the
  install folder, and warns if Disc 2 is missing (music-only result).
- Copies the loose support files (`Support\`, `eauninstall.exe`, icon).
- Writes the game's registry entries (install dir, CD drive, locale, language).
- Sets a high-DPI compatibility flag.
- Creates Desktop and Start Menu shortcuts.

### `scripts/Uninstall-HPGoF.ps1`
- Removes the shortcuts, compatibility flag, and registry key.
- Deletes the install directory when run with `-RemoveFiles`.

## Note: SafeDisc DRM

The disc's `gof_f.exe` is protected with SafeDisc 4.60, whose kernel driver
(`secdrv.sys`) Microsoft disabled and later removed from Windows because of a
privilege-escalation vulnerability
([KB3086255](https://support.microsoft.com/kb/3086255)). With no driver to
authenticate against, the protected executable exits immediately (code 1) on
Windows 10/11, and no compatibility shim can revive a driver that isn't present.

These scripts install the disc's executable as-is and do not touch its copy
protection. Getting the game to launch past SafeDisc is up to you and out of
scope for this repository — see
[PCGamingWiki](https://www.pcgamingwiki.com/wiki/Harry_Potter_and_the_Goblet_of_Fire).

## Troubleshooting

- **Game window is blurry.** The high-DPI flag should handle this; if not, set
  `gof_f.exe` → Properties → Compatibility → Change high DPI settings → Override
  scaling by Application.
- **No mouse in menus.** Expected — the game has no mouse support. Use the
  keyboard, and run `GofControls.exe` in the install folder to configure a
  gamepad.

## Recommended additional fixes

The game is hard-coded to 800×600 with no video options. **Chip's**
(Fix Enhancers) excellent
[Harry-Potter-and-the-Goblet-of-Fire-PC-Fix](https://github.com/Chip-Biscuit/Harry-Potter-and-the-Goblet-of-Fire-PC-Fix)
— built on Elisha Riedlinger's
[d3d8to9 / DirectX wrapper](https://github.com/elishacloud/dxwrapper) work —
adds custom resolutions and aspect ratios. This installer does not apply it;
download it from that repository's releases, set your resolution in its
`d3d9.ini`, and drop `d3d9.dll` + `d3d9.ini` next to `gof_f.exe` in the
install folder.

## Credits

- **Chip / Fix Enhancers** for the D3D9 resolution fix linked above.
- Compatibility research: [PCGamingWiki](https://www.pcgamingwiki.com/wiki/Harry_Potter_and_the_Goblet_of_Fire).

## Legal

This repository contains only scripts — no game files, binaries, or cracks. It
is intended for owners of a legitimate copy of the game, to install software
they have licensed on current hardware. It does not modify, remove, or
circumvent the disc's copy protection.

## License

[MIT](LICENSE)
