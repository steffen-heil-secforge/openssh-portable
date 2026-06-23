<#
.SYNOPSIS
    Installs the locally-built static OpenSSH_for_Windows 10.0p2 client suite
    (adds "Match localnetwork" support; statically linked - no libcrypto.dll)
    over an existing OpenSSH install, backing up the originals.

.DESCRIPTION
    Replaces every *.exe sitting next to this script (ssh, scp, sftp, ssh-add,
    ssh-agent, ssh-keygen, ssh-keyscan, ssh-pkcs11-helper, ssh-sk-helper) in
    -TargetDir (default: inbox OpenSSH at %WINDIR%\System32\OpenSSH), but only
    for files that already exist there. Each original is backed up to a file
    named after the version it actually contains, e.g. "scp.exe.9.5p2.bak"
    (the version is read from the existing ssh.exe, since the suite is uniform).

    Inbox files are owned by TrustedInstaller, so admin rights are required -
    this script SELF-ELEVATES (UAC) automatically.

    Launch with: right-click the .ps1 -> "Run with PowerShell".
    (Double-clicking a .ps1 only opens it in the editor - a Windows default.)

.PARAMETER TargetDir
    Folder whose binaries to replace. Default: inbox OpenSSH.

.PARAMETER Uninstall
    Restore every versioned backup (*.exe.*.bak) and remove the backups.
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

if (-not (Test-Path -LiteralPath $TargetDir)) { Fail "Target directory not found: $TargetDir" }

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

# ---------------- Install ----------------
$srcSsh = Join-Path $PSScriptRoot 'ssh.exe'
$dstSsh = Join-Path $TargetDir 'ssh.exe'
if (-not (Test-Path -LiteralPath $srcSsh)) { Fail "Source ssh.exe not found next to this script: $srcSsh" }
if (-not (Test-Path -LiteralPath $dstSsh)) { Fail "No existing ssh.exe at $dstSsh (is OpenSSH installed there?)." }

$newVer = Get-SshVersion $srcSsh
$oldVer = Get-SshVersion $dstSsh
Info "New version (these files) : $newVer"
Info "Old version (target)      : $oldVer"
Info "Target directory          : $TargetDir"
Write-Host ''

$srcExes  = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.exe')
$nInst = 0; $nSkip = 0
foreach ($e in $srcExes) {
    $name = $e.Name
    $dst  = Join-Path $TargetDir $name
    if (-not (Test-Path -LiteralPath $dst)) { Info "skip   $name  (not present in target)"; $nSkip++; continue }
    Grant-Write $dst
    if ($oldVer -ne $newVer) {
        $bak = Join-Path $TargetDir ("$name.$oldVer.bak")
        if (-not (Test-Path -LiteralPath $bak)) {
            Copy-Item $dst $bak -Force
            if (-not (Test-Path -LiteralPath $bak)) { Fail "Backup copy failed: $bak" }
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
if ($nSkip -gt 0) { Info "($nSkip source exe(s) were not present in the target and were skipped.)" }
if ($oldVer -ne $newVer) { Info "Originals backed up as <name>.$oldVer.bak in $TargetDir" }
Info "To revert: re-run with -Uninstall"
Pause-IfElevated
exit 0
