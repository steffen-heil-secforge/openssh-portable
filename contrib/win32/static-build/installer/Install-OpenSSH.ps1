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
    A custom folder must be outside %WINDIR% and either not exist yet (it is
    created) or be admin-only already and contain only a previous install of
    these files; it must sit in a parent that only administrators can write to (e.g.
    "$env:ProgramFiles\OpenSSH-secforge"); no path component may be a junction.
    Its ACL is reset so that only SYSTEM and Administrators can write to it
    (it is put on the system PATH).

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
    takeown /f "$Path" /a | Out-Null   # /a: owner = Administrators group, not the user account
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

# Access-mask bits (FileSystemRights + generic rights).
$MaskWrite   = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
               # WriteData, AppendData/AddSubdirectory, WriteEA, DeleteChild, WriteAttributes,
               # Delete, WriteDAC, WriteOwner, GENERIC_ALL, GENERIC_WRITE
$MaskReplace = 0x40 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000
               # DeleteChild, Delete, WriteDAC, WriteOwner, GENERIC_ALL: enough to rename/replace the folder

# True if $Path is owned by SYSTEM / Administrators / TrustedInstaller and no
# other principal holds any of the $Mask rights on it (inherit-only ACEs ignored).
function Test-TrustedOnly {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][long]$Mask)
    $acl   = Get-Acl -LiteralPath $Path
    $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    if ($TrustedSids -notcontains $owner) { return $false }
    foreach ($r in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        if ($r.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        if (([long][int]$r.FileSystemRights -band $Mask) -eq 0) { continue }
        if ($TrustedSids -notcontains $r.IdentityReference.Value) { return $false }
    }
    return $true
}

function Test-ReparsePoint {
    param([Parameter(Mandatory)][string]$Path)
    return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

# TargetDir goes on the system PATH, so no non-admin may be able to swap it
# out: no ancestor may be a junction/symlink, the parent must be writable only
# by admins (nobody else can create or re-create TargetDir in it), and no
# higher ancestor may be renamable/re-ACLable by a non-admin.
function Assert-SafeAncestors {
    param([Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { Fail "Parent folder does not exist: $parent" }
    if (-not (Test-TrustedOnly $parent $MaskWrite)) {
        Fail "Parent folder $parent is writable by non-administrators; use a folder under an admin-only location such as $env:ProgramFiles."
    }
    $a = $parent
    while ($a) {
        if (Test-ReparsePoint $a) { Fail "Path component $a is a junction/symbolic link; refusing." }
        if (-not (Test-TrustedOnly $a $MaskReplace)) { Fail "Folder $a can be renamed or re-permissioned by non-administrators; refusing." }
        $a = Split-Path -Parent $a
    }
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
}

# Owner Administrators; no inheritance; SYSTEM + Administrators full control,
# Users read/execute. Applied to the folder itself only (/L: never a link target).
function Lock-Folder {
    param([Parameter(Mandatory)][string]$Path)
    icacls "$Path" /setowner "*$SidAdmins" /L | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "icacls setowner failed for $Path (exit $LASTEXITCODE)." }
    icacls "$Path" /inheritance:r /grant:r "*$($SidSystem):(OI)(CI)F" "*$($SidAdmins):(OI)(CI)F" "*$($SidUsers):(OI)(CI)RX" /L | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "icacls lock-down failed for $Path (exit $LASTEXITCODE)." }
}

# Prepare a custom TargetDir. The ancestor check guarantees that only admins
# can create or replace TargetDir. A missing folder is created and locked
# before anything is put into it. An existing folder is never taken over: it
# must already be admin-only (else someone else may hold handles or have
# planted content) and may contain only what this installer puts there.
function Protect-TargetDir {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$ExeNames)
    Assert-DedicatedTarget $Path
    Assert-SafeAncestors $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
        Info "Created target directory: $Path"
        Lock-Folder $Path
        Ok "Restricted write access on $Path to SYSTEM and Administrators"
        return
    }
    if (Test-ReparsePoint $Path) { Fail "-TargetDir $Path is a junction/symbolic link; refusing." }
    if (-not (Test-TrustedOnly $Path $MaskWrite)) {
        Fail "Existing -TargetDir $Path is writable by non-administrators (or not owned by one); delete it or choose a new folder - the installer creates and locks it."
    }
    foreach ($c in @(Get-ChildItem -LiteralPath $Path -Force)) {
        $ok = -not $c.PSIsContainer -and
              -not ($c.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
              (($ExeNames -contains $c.Name) -or
               ($c.Name -match '^(.+\.exe)\..+\.bak$' -and $ExeNames -contains $Matches[1]))
        if (-not $ok) { Fail "-TargetDir $Path contains '$($c.Name)', which this installer did not put there; use a new folder." }
    }
    # Already admin-only, so nobody else can interfere now: still replace its ACL
    # (it may carry inheritable write grants for new files) and make existing
    # files inherit it again (they may carry their own write grants).
    Lock-Folder $Path
    foreach ($c in @(Get-ChildItem -LiteralPath $Path -Force)) {
        icacls "$($c.FullName)" /setowner "*$SidAdmins" /L | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "icacls setowner failed for $($c.FullName) (exit $LASTEXITCODE)." }
        icacls "$($c.FullName)" /reset /L | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "icacls reset failed for $($c.FullName) (exit $LASTEXITCODE)." }
    }
    Ok "Restricted write access on $Path to SYSTEM and Administrators"
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
# The default inbox folder inherits System32's ACL (TrustedInstaller) - leave it.
# A custom folder would inherit e.g. C:\'s ACL, where every user may modify
# subfolders - lock it down before it goes on the system PATH.
if ($IsDefault) {
    Assert-SafeAncestors $TargetDir
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir | Out-Null
        Info "Created target directory: $TargetDir"
        icacls "$TargetDir" /setowner "*$SidAdmins" | Out-Null   # owner must not be the user account
        if ($LASTEXITCODE -ne 0) { Fail "icacls setowner failed for $TargetDir (exit $LASTEXITCODE)." }
    }
} else {
    Protect-TargetDir $TargetDir @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.exe' | ForEach-Object Name)
}
if ((Test-ReparsePoint $TargetDir) -or -not (Test-TrustedOnly $TargetDir $MaskWrite)) {
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

# Every installed binary must be admin-only (it is run via the system PATH).
foreach ($e in $srcExes) {
    $dst = Join-Path $TargetDir $e.Name
    icacls "$dst" /setowner "*$SidAdmins" /L | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "icacls setowner failed for $dst (exit $LASTEXITCODE)." }
    if (-not (Test-TrustedOnly $dst $MaskWrite)) { Fail "$dst is writable by non-administrators after install - check the ACL of $TargetDir." }
}

$check = Get-SshVersion $dstSsh
if ($check -ne $newVer) { Fail "Verification failed: ssh.exe reads '$check', expected '$newVer'." }

Write-Host ''
Ok "SUCCESS - installed $nInst binaries as OpenSSH_for_Windows $newVer (static, no libcrypto.dll)."
if ($oldVer -and $oldVer -ne $newVer) { Info "Originals backed up as <name>.$oldVer.bak in $TargetDir" }
Info "To revert: re-run with -Uninstall"
Pause-IfElevated
exit 0
