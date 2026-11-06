<#
.SYNOPSIS
    Packages and checks a secforge release from bin\x64\Release (after build-all.bat).

.DESCRIPTION
    Stages exactly the release exes + installer + README into
    <repo>\release\OpenSSH_for_Windows_<tag without v>-static-x64\ and zips it.
    Before zipping it checks that:
      - every exe is present and ssh-agent.exe is not,
      - no exe imports libcrypto*.dll (dumpbin /dependents),
      - "ssh -V" reports the version and build marker named by the tag,
      - "Match localnetwork" works (127.0.0.0/8 matches, 203.0.113.0/24 not).

.PARAMETER Tag
    Release tag, e.g. v10.5p1-secforge+pr859.pr860 (see BUILD-NOTES.md).
#>
param([Parameter(Mandatory)][string]$Tag)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
Set-Location -LiteralPath ([System.IO.Path]::GetTempPath())   # cmd.exe cannot use a UNC cwd (e.g. when started from WSL)

if ($Tag -notmatch '^v(\d+\.\d+p\d+)-(secforge(\.\d+)?\+[0-9a-z]+(\.[0-9a-z]+)*)$') {
    Fail "Tag '$Tag' does not match v<ver>-secforge[.<n>]+<prs> (e.g. v10.5p1-secforge+pr859.pr860)."
}
$ver = $Matches[1]; $marker = $Matches[2]

$root  = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$bin   = Join-Path $root 'bin\x64\Release'
$inst  = Join-Path $PSScriptRoot '..\installer'
$name  = "OpenSSH_for_Windows_$($Tag.Substring(1))-static-x64"
$stage = Join-Path $root "release\$name"
$zip   = Join-Path $root "release\$name.zip"
$exes  = @('ssh.exe','scp.exe','sftp.exe','ssh-add.exe','ssh-keygen.exe',
           'ssh-keyscan.exe','ssh-pkcs11-helper.exe','ssh-sk-helper.exe')

# ---- stage ----
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
foreach ($e in $exes) {
    $src = Join-Path $bin $e
    if (-not (Test-Path -LiteralPath $src)) { Fail "missing build output: $src" }
    Copy-Item -LiteralPath $src -Destination $stage
}
Copy-Item -LiteralPath (Join-Path $inst 'Install-OpenSSH.ps1') -Destination $stage
Copy-Item -LiteralPath (Join-Path $inst 'README.txt') -Destination $stage
if (Test-Path -LiteralPath (Join-Path $stage 'ssh-agent.exe')) { Fail 'ssh-agent.exe must not be part of the release' }

# ---- no libcrypto DLL dependency ----
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$dumpbin = Get-ChildItem -Path (Join-Path $vs 'VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe') | Select-Object -Last 1
if (-not $dumpbin) { Fail 'dumpbin.exe not found' }
foreach ($e in $exes) {
    $deps = (& $dumpbin.FullName /nologo /dependents (Join-Path $stage $e) | Out-String)
    if ($deps -match '(?i)libcrypto|libssl|zlib.*\.dll|fido2\.dll|cbor\.dll') { Fail "$e imports a third-party DLL:`n$deps" }
}
Write-Host 'OK  no third-party DLL imports' -ForegroundColor Green

# ---- version / marker ----
$ssh = Join-Path $stage 'ssh.exe'
$v = (cmd.exe /c "`"$ssh`" -V 2>&1" | Out-String).Trim()
$want = "OpenSSH_for_Windows_$ver Win32-OpenSSH-GitHub $marker,"
if (-not $v.StartsWith($want)) { Fail "ssh -V is '$v', expected it to start with '$want'" }
Write-Host "OK  $v" -ForegroundColor Green

# ---- Match localnetwork ----
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "secforge-pkg-$PID"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    foreach ($case in @(@('127.0.0.0/8', 'yes'), @('203.0.113.0/24', 'no'))) {
        $cfg = Join-Path $tmp 'cfg'
        Set-Content -Path $cfg -Value "Match localnetwork $($case[0])`n    Compression yes" -Encoding ascii
        $out = (cmd.exe /c "`"$ssh`" -G -F `"$cfg`" dummy 2>&1" | Out-String)
        if ($out -match 'not supported') { Fail "Match localnetwork not supported: $out" }
        $got = if ($out -match '(?m)^compression (\S+)') { $Matches[1] } else { '?' }
        if ($got -ne $case[1]) { Fail "Match localnetwork $($case[0]): compression $got, expected $($case[1])" }
    }
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'OK  Match localnetwork' -ForegroundColor Green

# ---- zip ----
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
Write-Host "OK  $zip"
Write-Host "    SHA256 $hash"
Write-Host 'PACKAGE_OK'
