@echo off
setlocal EnableDelayedExpansion
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set ROOT=L:\Development\openssh-portable
set SLN=%ROOT%\contrib\win32\openssh
set "INCLUDE=%SLN%\vcpkg_installed\x64-custom\x64-custom\include;%INCLUDE%"
set "LIB=%SLN%\vcpkg_installed\x64-custom\x64-custom\lib;%LIB%"
cd /d %SLN%
set COMMON=/p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v145 /p:SpectreMitigation=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:WholeProgramOptimization=false /p:VcpkgEnabled=false /p:VcpkgEnableManifest=false /p:SolutionDir=%SLN%\ /v:minimal /nologo

echo === regen config.h + crtheaders.h ===
del "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h" 2>nul
powershell.exe -ExecutionPolicy Bypass -File "%SLN%\config.ps1" -Config_h_vs "%SLN%\config.h.vs" -Config_h "%ROOT%\config.h" -VCIncludePath "%INCLUDE%" -OutCRTHeader "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h"

set FAILED=
for %%P in (openbsd_compat.vcxproj win32iocompat.vcxproj libssh.vcxproj ssh.vcxproj scp.vcxproj sftp.vcxproj ssh-add.vcxproj ssh-agent.vcxproj keygen.vcxproj ssh-keyscan.vcxproj ssh-pkcs11-helper.vcxproj ssh-sk-helper.vcxproj) do (
    echo === building %%P ===
    msbuild %%P %COMMON%
    if !ERRORLEVEL! NEQ 0 ( echo   *** FAILED: %%P ^(exit !ERRORLEVEL!^) & set FAILED=!FAILED! %%P )
)

echo.
if defined FAILED ( echo BUILD FAILURES:!FAILED! ) else ( echo ALL BUILDS OK )
echo === produced exes in bin\x64\Release ===
dir /b "%ROOT%\bin\x64\Release\*.exe"
