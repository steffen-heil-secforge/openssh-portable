OpenSSH_for_Windows - secforge static client suite
==================================================

Contents
--------
  The full x64 client suite (version: see  ssh -V ), LibreSSL,
  all STATICALLY linked - NO libcrypto.dll required:

    ssh.exe  scp.exe  sftp.exe  ssh-add.exe  ssh-agent.exe
    ssh-keygen.exe  ssh-keyscan.exe  ssh-pkcs11-helper.exe  ssh-sk-helper.exe

  Changes over the official build (pending upstream PRs, see ssh -V suffix):
    * pr859: ssh_config "Match localnetwork" works on Windows (getifaddrs()
      implementation over GetAdaptersAddresses()).
    * pr860: a refused connect falls back to the next address (e.g. IPv6 ->
      IPv4) instead of failing with "Connection to UNKNOWN port -1".
  The other tools are rebuilt at the same version so the suite is uniform
  (avoids a new ssh.exe spawning an old inbox ssh-sk-helper/ssh-pkcs11-helper).

  Install-OpenSSH.ps1  Installer/uninstaller (replaces all of the above).

Install (into %WINDIR%\System32\OpenSSH)
-----------------------------------------
  Right-click  Install-OpenSSH.ps1  ->  "Run with PowerShell".
  The script self-elevates (you'll get a UAC prompt) - no need to open an
  admin console yourself.

  NOTE: double-clicking a .ps1 only OPENS it in the editor (a Windows
  default); use "Run with PowerShell" (or run it from a console) to launch.

  The installer:
    * creates the target directory if it does not exist (fresh install),
    * adds the target directory to the system PATH if it is missing,
    * removes the "OpenSSH.Client" Windows Capability (if installed), so
      Windows Update / "Optional Features" cannot overwrite the binaries,
    * copies all exes above into the target. Each existing binary is backed
      up first, named after the version it contains (read from the installed
      ssh.exe), e.g.  ssh.exe.9.5p2.bak , scp.exe.9.5p2.bak , ...

Install elsewhere
-----------------
  .\Install-OpenSSH.ps1 -TargetDir "C:\Program Files\OpenSSH-secforge"

  The folder is put on the system PATH, so no non-administrator may be able
  to change or replace it. The installer refuses the folder unless:
    * it is outside %WINDIR% and not a drive root,
    * its parent is writable only by administrators (e.g. C:\Program Files;
      NOT C:\ or C:\Tools, where every user may create/rename folders),
    * no path component is a junction / symbolic link,
    * it is empty or contains only a previous install (*.exe, *.exe.*.bak).
  Its ACL is then reset to: owner Administrators, SYSTEM + Administrators
  full control, Users read/execute.

Revert
------
  .\Install-OpenSSH.ps1 -Uninstall
  (restores the original versioned backup and removes it; does NOT re-add
  the "OpenSSH.Client" Windows Capability or remove the PATH entry - re-add
  the capability via "Optional Features" if you want the inbox client back)

Quick test without installing (per-shell, no admin)
---------------------------------------------------
  $env:PATH = "<folder containing this README>;$env:PATH"
  ssh -V
  # Match localnetwork demo:
  "Match localnetwork 127.0.0.0/8`n    Compression yes" | Set-Content cfg.txt
  ssh -G -F cfg.txt dummy | findstr /I compression   # -> compression yes

Notes
-----
  * Should the inbox client come back anyway (e.g. a feature update re-adds
    the capability), just re-run the installer.
  * This is a locally-built binary, not a signed Microsoft release.
