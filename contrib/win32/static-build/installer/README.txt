OpenSSH_for_Windows 10.0p2 - static client suite (with "Match localnetwork")
==============================================================================

Contents
--------
  The full x64 client suite, OpenSSH_for_Windows_10.0p2, LibreSSL 4.2.0,
  all STATICALLY linked - NO libcrypto.dll required:

    ssh.exe  scp.exe  sftp.exe  ssh-add.exe  ssh-agent.exe
    ssh-keygen.exe  ssh-keyscan.exe  ssh-pkcs11-helper.exe  ssh-sk-helper.exe

  ssh.exe adds support for the ssh_config "Match localnetwork" criterion on
  Windows (via a getifaddrs() implementation over GetAdaptersAddresses()).
  The other tools are rebuilt at the same version so the suite is uniform
  (avoids 10.0 ssh.exe spawning a 9.5 ssh-sk-helper/ssh-pkcs11-helper, etc.).

  Install-OpenSSH.ps1  Installer/uninstaller (replaces all of the above).

Install (replaces matching binaries in the inbox %WINDIR%\System32\OpenSSH)
-----------------------------------------------------------------------
  Right-click  Install-OpenSSH.ps1  ->  "Run with PowerShell".
  The script self-elevates (you'll get a UAC prompt) - no need to open an
  admin console yourself.

  NOTE: double-clicking a .ps1 only OPENS it in the editor (a Windows
  default); use "Run with PowerShell" (or run it from a console) to launch.

  Each existing binary is backed up first, named after the version it
  contains (read from the installed ssh.exe), e.g.  ssh.exe.9.5p2.bak ,
  scp.exe.9.5p2.bak , ...

  Only files that already exist in the target are replaced; nothing new
  is added there.

Install elsewhere
-----------------
  .\Install-OpenSSH.ps1 -TargetDir "C:\Tools\OpenSSH"

Revert
------
  .\Install-OpenSSH.ps1 -Uninstall
  (restores the original versioned backup and removes it)

Quick test without installing (per-shell, no admin)
---------------------------------------------------
  $env:PATH = "L:\Development\tools\OpenSSH_for_windows_10.0p2;$env:PATH"
  ssh -V
  # Match localnetwork demo:
  "Match localnetwork 127.0.0.0/8`n    Compression yes" | Set-Content cfg.txt
  ssh -G -F cfg.txt dummy | findstr /I compression   # -> compression yes

Notes
-----
  * Windows Update / "Optional Features" repair may restore the inbox 9.5p2
    client; just re-run the installer if that happens.
  * This is a locally-built binary, not a signed Microsoft release.
