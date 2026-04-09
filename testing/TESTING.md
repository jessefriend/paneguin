# Testing Guide

This repo has two different test goals, and they use two different checkpoints.

## Start Here

If you want to test the real user install path, including distro installation from `setup.ps1`, use:

- `clean-wsl-no-distro`

If you want fast, repeatable automation across lots of options, use:

- `clean-wsl-base`

The difference is simple:

- `clean-wsl-no-distro` means WSL is installed, but no Linux distro has been installed yet.
- `clean-wsl-base` means the distro already exists and has already completed its first Linux username/password setup.

Why this matters:

- `setup.ps1` really does install the distro when it is missing.
- That first Linux user-creation step is still interactive, so it is not a great fit for the fully repeatable Hyper-V matrix.
- The matrix is meant to be fast, so it reuses already initialized distros.

## Recommended Order

If you are starting from zero, do the testing in this order:

1. Build a clean Windows VM.
2. Enable nested virtualization on that VM.
3. Install Windows updates in the guest.
4. Install WSL in the guest, but do not install a distro yet.
5. Capture `clean-wsl-no-distro`.
6. Run a fresh-install smoke test from that checkpoint.
7. Finish the Linux first-run username/password setup when prompted.
8. Install and initialize any additional distros you want in the long-running matrix.
9. Capture `clean-wsl-base`.
10. Run the repeatable automated matrix from `clean-wsl-base`.
11. Run the manual GUI and desktop-launch checks.

## Step 1: Prepare The VM

Create a Windows 11 Hyper-V VM for testing.

On the host, enable nested virtualization:

```powershell
Stop-VM -Name "WSL-Test-01" -Force
Set-VMProcessor -VMName "WSL-Test-01" -ExposeVirtualizationExtensions $true
Start-VM -Name "WSL-Test-01"
```

Inside the guest:

1. Finish Windows setup.
2. Install Windows updates.
3. Create a local admin account you can use for PowerShell Direct.
4. Install WSL.
5. Stop before installing any distro.

At this point, the guest is ready for your first checkpoint.

## Step 2: Capture `clean-wsl-no-distro`

Shut the guest down, then on the host run:

```powershell
.\testing\New-HyperVBaseCheckpoint.ps1 -VMName "WSL-Test-01" -CheckpointName "clean-wsl-no-distro" -ReplaceExisting
```

This is the checkpoint you use when you want to prove that `setup.ps1` can really install the distro itself.

## Step 3: Run The Fresh-Install Smoke Test

Restore `clean-wsl-no-distro`, start the VM, sign in normally, and run this inside the guest:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\testing\smoke-test.ps1 -Distro Ubuntu -DesktopEnv xfce
```

Important:

- Do not pass `-ReuseExistingDistro` here.
- This is the run that exercises the distro-install branch in `setup.ps1`.
- If WSL opens a first-run Linux prompt, finish the Linux username/password creation before returning to PowerShell.

If you want a second fresh-install check for another distro, revert to `clean-wsl-no-distro` and repeat with a different `-Distro`.

## Step 4: Build `clean-wsl-base`

Now prepare the reusable automation checkpoint.

Inside the guest:

1. Install every distro you want in the automated matrix.
2. Launch each distro once.
3. Finish the Linux first-run username/password setup for each one.
4. If you want a real positive test for Chrome integration, install Chrome inside at least one distro.
5. Shut the guest down.

On the host:

```powershell
.\testing\New-HyperVBaseCheckpoint.ps1 -VMName "WSL-Test-01" -CheckpointName "clean-wsl-base" -ReplaceExisting
```

This checkpoint is for repeatable automation, not for testing the first-time distro install branch.

## Step 5: Run The Repeatable Matrix

The easiest entry point is:

```powershell
.\testing\Run-FullLab.ps1 -VMName "WSL-Test-01"
```

That wrapper:

- checks that `clean-wsl-base` exists
- prompts for the guest VM credential if you do not pass one
- runs the Hyper-V matrix harness

If you want it to refresh `clean-wsl-base` first:

```powershell
.\testing\Run-FullLab.ps1 -VMName "WSL-Test-01" -RefreshCheckpoint
```

If you only want to refresh the checkpoint and stop:

```powershell
.\testing\Run-FullLab.ps1 -VMName "WSL-Test-01" -RefreshCheckpoint -CheckpointOnly
```

## Step 6: Run A Bigger Matrix

For a broader automated sweep:

```powershell
.\testing\Run-FullLab.ps1 `
  -VMName "WSL-Test-01" `
  -MatrixProfile cartesian `
  -CartesianDistros Ubuntu, FedoraLinux-42, openSUSE-Tumbleweed `
  -CartesianDesktopEnvironments xfce, mate, lxqt, kde `
  -CartesianVariants basic, chrome, xrdp-guard, kde-fallback
```

What that does:

- generates a larger case matrix automatically
- reuses the initialized distros from `clean-wsl-base`
- writes logs and reports under `testing\artifacts\`

Report files:

- `summary.json`
- `summary.csv`
- `summary.html`

## Which Script Should I Use?

Use `testing\smoke-test.ps1` when:

- you are inside the guest VM
- you want to test the CLI installer directly
- you want to test the real fresh-install path from `clean-wsl-no-distro`

Use `testing\Run-FullLab.ps1` when:

- you are on the Hyper-V host
- you already have `clean-wsl-base`
- you want the easiest repeatable automation entry point

Use `testing\Invoke-HyperVTestMatrix.ps1` when:

- you want lower-level control than `Run-FullLab.ps1`
- you want to pass a custom matrix JSON file
- you want to call the matrix harness directly

Use `testing\New-HyperVBaseCheckpoint.ps1` when:

- you want to create or refresh `clean-wsl-no-distro`
- you want to create or refresh `clean-wsl-base`

## What Is Automated And What Is Not

Automated:

- running `setup.ps1`
- running the launcher installer
- validating expected WSL-side files
- validating optional XRDP host-only protection
- validating packaging output when requested
- collecting host and guest logs

Still manual:

- the first Linux username/password setup on a brand-new distro
- the Windows Forms GUI path
- confirming the actual RDP desktop opens successfully in MSTSC

## Manual Checks You Should Still Do

After the automated runs, I would still do these by hand:

1. Run `.\setup-gui.ps1` from a normal user session and complete a full install.
2. Run `.\setup-gui.ps1` from an elevated session and confirm the launcher warning is shown.
3. Launch `%USERPROFILE%\Desktop\Paneguin.lnk` and confirm the desktop actually opens.
4. Build the packaged release and test the packaged flow in a clean VM snapshot.

Package build commands:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\build-exe.ps1 -InstallPs2ExeIfMissing -NoConsole
.\package-release.ps1 -ZipRelease
```

Expected artifacts:

- `dist\Paneguin.exe`
- `dist\release\Run-Paneguin.bat`
- `dist\release.zip`

## Practical Minimum

If you only want the shortest useful coverage, do this:

1. Create `clean-wsl-no-distro`.
2. Run one fresh-install smoke test with `Ubuntu`.
3. Create `clean-wsl-base`.
4. Run `.\testing\Run-FullLab.ps1 -VMName "WSL-Test-01"`.
5. Manually test the GUI once.
6. Manually launch the installed desktop once.

