# Paneguin
<img src="./assets/paneguin.png" width="150" height="100" />

Paneguin bootstraps a Linux desktop inside WSL and connects to it from Windows over XRDP.

## What This Repo Does

- Installs or reuses a supported WSL distro
- Sets up XRDP plus a desktop environment inside Linux
- Applies the Windows RDP minimize fix if you want it
- Creates per-user Windows launcher scripts and a desktop shortcut
- Includes optional helpers for packaging the GUI installer as an EXE

## Supported Desktops

- `kde`
- `xfce`
- `mate`
- `lxqt`

## Supported Distro Families

- Ubuntu and Debian
- Fedora
- openSUSE

APT-based distros are the most tested.

## Recommended Install Flow

### 1. Run machine-level setup

Open an elevated PowerShell window and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup.ps1
```

If you prefer the GUI, run it from your normal Windows user session. It will prompt for elevation only when it needs it:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup-gui.ps1
```

### 2. Install the per-user launcher

If you used `setup.ps1`, run this in your normal user context:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\Install-Paneguin-Launcher.ps1
```

That creates:

- `%USERPROFILE%\Scripts\Launch-Paneguin.ps1`
- `%USERPROFILE%\Scripts\Launch-Paneguin.bat`
- `%USERPROFILE%\Scripts\Paneguin.exe`
- `%USERPROFILE%\Desktop\Paneguin.lnk`

The installer compiles a `Paneguin.exe` by default using [ps2exe](https://github.com/MScholtes/PS2EXE). The desktop shortcut points at the `.exe`, which means you can **pin it to the taskbar** like any other app. If ps2exe is not installed, pass `-InstallPs2ExeIfMissing` to have the installer fetch it automatically:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\Install-Paneguin-Launcher.ps1 -InstallPs2ExeIfMissing
```

To skip the `.exe` and fall back to the plain PowerShell shortcut (no taskbar pinning), pass `-SkipExe`:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\Install-Paneguin-Launcher.ps1 -SkipExe
```

The launcher installer will try to auto-detect the Linux username for the selected distro. If needed, you can still pass `-Distro` and `-Username` explicitly.

### 3. Launch the desktop

Use the desktop shortcut, pin `Paneguin.exe` to your taskbar, or run:

```powershell
& "$env:USERPROFILE\Scripts\Paneguin.exe"
```

## Repo Layout

- `setup.ps1`: interactive elevated installer for the machine-level setup
- `setup-gui.ps1`: Windows Forms wrapper around the same flow
- `windows\Install-Paneguin-Launcher.ps1`: creates the per-user launchers and shortcut
- `windows\Launch-Paneguin.ps1`: template for the installed launcher
- `wsl\setup.sh`: Linux-side XRDP and desktop-environment setup
- `build-exe.ps1`: builds the optional GUI EXE with `ps2exe`
- `package-release.ps1`: assembles a single-folder release and optional zip
- `build-release.bat`: convenience wrapper for the build-and-package flow

## Optional Packaging

The EXE wrapper is optional convenience, not the primary install path.

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\build-exe.ps1 -InstallPs2ExeIfMissing -NoConsole
.\package-release.ps1 -ZipRelease
```

The release output is written to `dist\`.

## Included Fixes

- optional Chrome wrapper and URL-handler registration
- optional host-only XRDP restriction for the Windows machine
- `xdg-open` / default-browser handling
- Windows RDP minimize fix
- XRDP disconnected-session persistence settings
- session repair helper at `~/bin/paneguin-repair`

## Notes

- The GUI flow should be started from your normal Windows user session so it can install the launcher back into that same profile after the elevated setup finishes.
- The optional host-only XRDP restriction works best with default WSL networking. On unusual mirrored or bridged setups it may block launch until you rerun setup without that option.
- Running `windows\Install-Paneguin-Launcher.ps1` manually remains the supported fallback if that final step does not happen automatically.

## License

This project is licensed under the MIT License. See `LICENSE`.

