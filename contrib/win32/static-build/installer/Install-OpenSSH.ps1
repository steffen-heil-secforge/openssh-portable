<#
.SYNOPSIS
    Installs the locally-built static OpenSSH_for_Windows client suite
    (adds "Match localnetwork" support; statically linked - no libcrypto.dll).

.DESCRIPTION
    Copies every *.exe sitting next to this script (ssh, scp, sftp, ssh-add,
    ssh-agent, ssh-keygen, ssh-keyscan, ssh-pkcs11-helper, ssh-sk-helper) into
    -TargetDir (default: %WINDIR%\System32\OpenSSH), creating the directory if
    needed. Any pre-existing exe is backed up as "<name>.<oldver>.bak" first.

    Also removes the "OpenSSH.Client" Windows Capability (if present) so
    Windows Update cannot silently overwrite the binaries.

    Inbox files are owned by TrustedInstaller, so admin rights are required -
    this script SELF-ELEVATES (UAC) automatically.

    Launch with: right-click the .ps1 -> "Run with PowerShell".
    (Double-clicking a .ps1 only opens it in the editor - a Windows default.)

.PARAMETER TargetDir
    Install folder. Default: inbox OpenSSH (%WINDIR%\System32\OpenSSH).
    A custom folder must be outside %WINDIR% and empty or contain only a
    previous install; its ACL is reset so that only SYSTEM and Administrators
    can write to it (it is put on the system PATH).

.PARAMETER Uninstall
    Restore every versioned backup (*.exe.*.bak) and remove the backups.
    Does not touch the system PATH or the OpenSSH.Client capability.
#>
[CmdletBinding()]
param(
    [string]$TargetDir = (Join-Path $env:WINDIR 'System32\OpenSSH'),
    [switch]$Uninstall,
    [switch]$Elevated   # internal: set on the self-elevated relaunch (controls pause)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Pause-IfElevated { if ($Elevated) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null } }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; Pause-IfElevated; exit 1 }
function Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Ok($msg)   { Write-Host $msg -ForegroundColor Green }

# ---------------- self-elevate to Administrator (UAC) ----------------
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host 'Requesting administrator privileges (UAC prompt)...' -ForegroundColor Yellow
    $hostExe = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),'-Elevated')
    if ($Uninstall) { $argList += '-Uninstall' }
    $argList += @('-TargetDir', ('"{0}"' -f $TargetDir))
    try {
        Start-Process -FilePath $hostExe -ArgumentList $argList -Verb RunAs | Out-Null
    } catch {
        Write-Host "Elevation was cancelled or failed: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host 'Press Enter to close' | Out-Null
    }
    exit
}

# OpenSSH version actually contained in an ssh.exe (from -V), e.g. "9.5p2".
# Captured via cmd so $ErrorActionPreference='Stop' doesn't turn ssh's stderr
# write into a thrown NativeCommandError. Falls back to FileVersion, then "unknown".
function Get-SshVersion {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $out = (cmd.exe /c "`"$Path`" -V 2>&1" | Out-String)
        if ($out -match 'OpenSSH_for_Windows_([0-9]+\.[0-9]+p[0-9]+)') { return $Matches[1] }
        if ($out -match 'OpenSSH[_ ]([0-9][0-9.]*p[0-9]+)')           { return $Matches[1] }
    } catch { }
    try {
        $fv = (Get-Item $Path).VersionInfo.FileVersion
        if ($fv) { return ($fv -replace '[^0-9A-Za-z._-]', '_') }
    } catch { }
    return 'unknown'
}

# take ownership + grant Administrators full control (SID = locale independent)
function Grant-Write {
    param([Parameter(Mandatory)][string]$Path)
    takeown /f "$Path" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "takeown failed for $Path (exit $LASTEXITCODE)." }
    icacls "$Path" /grant "*S-1-5-32-544:F" | Out-Null   # *S-1-5-32-544 = BUILTIN\Administrators
    if ($LASTEXITCODE -ne 0) { Fail "icacls grant failed for $Path (exit $LASTEXITCODE)." }
}

# Well-known SIDs (locale independent).
$SidSystem   = 'S-1-5-18'
$SidAdmins   = 'S-1-5-32-544'
$SidUsers    = 'S-1-5-32-545'
$SidTrustedI = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'   # NT SERVICE\TrustedInstaller
$TrustedSids = @($SidSystem, $SidAdmins, $SidTrustedI)

$DefaultDir = Join-Path $env:WINDIR 'System32\OpenSSH'
$TargetDir  = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetDir).TrimEnd('\')
$IsDefault  = $TargetDir -ieq [System.IO.Path]::GetFullPath($DefaultDir).TrimEnd('\')

# True if only SYSTEM / Administrators / TrustedInstaller own the directory and
# hold any write-type right on it. Anything else would let a non-admin plant
# binaries in a directory on the system PATH (privilege escalation).
function Test-AdminOnlyWritable {
    param([Parameter(Mandatory)][string]$Path)
    $acl   = Get-Acl -LiteralPath $Path
    $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    if ($TrustedSids -notcontains $owner) { return $false }
    # WriteData, AppendData, WriteExtendedAttributes, DeleteSubdirectoriesAndFiles,
    # WriteAttributes, Delete, ChangePermissions, TakeOwnership, GENERIC_ALL, GENERIC_WRITE
    $writeMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
    foreach ($r in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        if ($r.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        if (([int]$r.FileSystemRights -band $writeMask) -eq 0) { continue }
        if ($TrustedSids -notcontains $r.IdentityReference.Value) { return $false }
    }
    return $true
}

# A custom TargetDir must be a dedicated folder: we take it over and replace its
# ACL, so refuse anything that could be a shared/system directory.
function Assert-DedicatedTarget {
    param([Parameter(Mandatory)][string]$Path)
    $winDir = [System.IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')
    if ($Path -ieq $winDir -or $Path.StartsWith("$winDir\", [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Custom -TargetDir must not be inside $winDir (use the default or a dedicated folder elsewhere)."
    }
    if ([System.IO.Path]::GetPathRoot($Path).TrimEnd('\') -ieq $Path) { Fail "-TargetDir must not be a drive root: $Path" }
    if (Test-Path -LiteralPath $Path) {
        $foreign = @(Get-ChildItem -LiteralPath $Path -Force |
                     Where-Object { $_.PSIsContainer -or ($_.Name -notmatch '\.exe$' -and $_.Name -notmatch '\.exe\..+\.bak$') })
        if ($foreign.Count -gt 0) {
            Fail "-TargetDir $Path contains other files/folders (e.g. '$($foreign[0].Name)'); use an empty, dedicated folder."
        }
    }
}

# Owner Administrators; no inheritance; SYSTEM + Administrators full control,
# Users read/execute; existing files re-inherit that ACL.
function Protect-TargetDir {
    param([Parameter(Mandatory)][string]$Path)
    icacls "$Path" /setowner "*$SidAdmins" /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "icacls setowner failed for $Path (exit $LASTEXITCODE)." }
    icacls "$Path" /reset | Out-Null      # drop explicit ACEs (e.g. granted to the creating user)
    if ($LASTEXITCODE -ne 0) { Fail "icacls reset failed for $Path (exit $LASTEXITCODE)." }
    icacls "$Path" /inheritance:r /grant:r "*$($SidSystem):(OI)(CI)F" "*$($SidAdmins):(OI)(CI)F" "*$($SidUsers):(OI)(CI)RX" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "icacls lock-down failed for $Path (exit $LASTEXITCODE)." }
    if (@(Get-ChildItem -LiteralPath $Path -Force).Count -gt 0) {
        icacls (Join-Path $Path '*') /reset /T /C | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "icacls reset of existing files in $Path failed (exit $LASTEXITCODE)." }
    }
}

# ---------------- Uninstall ----------------
if ($Uninstall) {
    $baks = @(Get-ChildItem -LiteralPath $TargetDir -Filter '*.exe.*.bak' -ErrorAction SilentlyContinue |
              Sort-Object CreationTimeUtc)
    if ($baks.Count -eq 0) { Fail "No backups (*.exe.*.bak) found in $TargetDir." }
    $restored = @{}
    foreach ($b in $baks) {
        if ($b.Name -match '^(.+\.exe)\..+\.bak$') {
            $orig = $Matches[1]
            $dst  = Join-Path $TargetDir $orig
            if (-not $restored.ContainsKey($orig)) {   # oldest backup wins (Sort above)
                Grant-Write $dst
                Copy-Item $b.FullName $dst -Force
                Ok "restored $orig"
                $restored[$orig] = $true
            }
            Remove-Item $b.FullName -Force
        }
    }
    Ok "Uninstall complete. ssh.exe is now $(Get-SshVersion (Join-Path $TargetDir 'ssh.exe'))."
    Pause-IfElevated
    exit 0
}

# ---------------- Install: prepare target directory ----------------
if (-not $IsDefault) { Assert-DedicatedTarget $TargetDir }
if (-not (Test-Path -LiteralPath $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Info "Created target directory: $TargetDir"
    if ($IsDefault) {   # inherits System32's ACL; only make sure the owner is not the user account
        icacls "$TargetDir" /setowner "*$SidAdmins" | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "icacls setowner failed for $TargetDir (exit $LASTEXITCODE)." }
    }
}
# The default inbox folder inherits System32's ACL (TrustedInstaller) - leave it.
# A custom folder would inherit e.g. C:\'s ACL, where every user may modify
# subfolders - lock it down before it goes on the system PATH.
if (-not $IsDefault) {
    Protect-TargetDir $TargetDir
    Ok "Restricted write access on $TargetDir to SYSTEM and Administrators"
}
if (-not (Test-AdminOnlyWritable $TargetDir)) {
    Fail "$TargetDir is writable by non-administrators (or not owned by an administrator); refusing to install it on the system PATH."
}

# ---------------- ensure TargetDir is in the system PATH ----------------
$regPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$sysPath  = (Get-ItemProperty -LiteralPath $regPath -Name Path).Path
$entries  = $sysPath -split ';' | Where-Object { $_ -ne '' }
$already  = $entries | Where-Object { $_ -eq $TargetDir -or $_ -eq $TargetDir.TrimEnd('\') }
if (-not $already) {
    $newPath = ($entries + $TargetDir) -join ';'
    Set-ItemProperty -LiteralPath $regPath -Name Path -Value $newPath
    # broadcast WM_SETTINGCHANGE so the running session picks it up without a reboot
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
    Ok "Added $TargetDir to system PATH"
} else {
    Info "PATH already contains $TargetDir"
}

# ---------------- remove Windows Capability (prevents Windows Update overwrite) ----------------
foreach ($capName in @('OpenSSH.Client~~~~0.0.1.0')) {
    try {
        $cap = Get-WindowsCapability -Online -Name $capName -ErrorAction SilentlyContinue
        if ($cap -and $cap.State -eq 'Installed') {
            Info "Removing Windows Capability: $capName ..."
            Remove-WindowsCapability -Online -Name $capName | Out-Null
            Ok "Removed $capName"
        }
    } catch {
        Info "Could not remove capability $capName (may not exist): $($_.Exception.Message)"
    }
}

# ---------------- Install ----------------
$srcSsh = Join-Path $PSScriptRoot 'ssh.exe'
$dstSsh = Join-Path $TargetDir 'ssh.exe'
if (-not (Test-Path -LiteralPath $srcSsh)) { Fail "Source ssh.exe not found next to this script: $srcSsh" }

$newVer = Get-SshVersion $srcSsh
$oldVer = if (Test-Path -LiteralPath $dstSsh) { Get-SshVersion $dstSsh } else { $null }
Info "New version (these files) : $newVer"
if ($oldVer) { Info "Old version (target)      : $oldVer" } else { Info "No existing binaries in target (fresh install)" }
Info "Target directory          : $TargetDir"
Write-Host ''

$srcExes = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.exe')
$nInst = 0
foreach ($e in $srcExes) {
    $name = $e.Name
    $dst  = Join-Path $TargetDir $name
    if (Test-Path -LiteralPath $dst) {
        Grant-Write $dst
        if ($oldVer -and $oldVer -ne $newVer) {
            $bak = Join-Path $TargetDir ("$name.$oldVer.bak")
            if (-not (Test-Path -LiteralPath $bak)) {
                Copy-Item $dst $bak -Force
                if (-not (Test-Path -LiteralPath $bak)) { Fail "Backup copy failed: $bak" }
            }
        }
    }
    Copy-Item $e.FullName $dst -Force
    Ok "install $name"
    $nInst++
}

$check = Get-SshVersion $dstSsh
if ($check -ne $newVer) { Fail "Verification failed: ssh.exe reads '$check', expected '$newVer'." }

Write-Host ''
Ok "SUCCESS - installed $nInst binaries as OpenSSH_for_Windows $newVer (static, no libcrypto.dll)."
if ($oldVer -and $oldVer -ne $newVer) { Info "Originals backed up as <name>.$oldVer.bak in $TargetDir" }
Info "To revert: re-run with -Uninstall"
Pause-IfElevated
exit 0
