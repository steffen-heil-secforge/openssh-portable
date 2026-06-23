@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set ROOT=L:\Development\openssh-portable
set SLN=%ROOT%\contrib\win32\openssh
rem inject vcpkg headers/libs so projects that rely on the vcpkg MSBuild
rem integration (e.g. openbsd_compat) resolve openssl/zlib with it disabled
set "INCLUDE=%SLN%\vcpkg_installed\x64-custom\x64-custom\include;%INCLUDE%"
set "LIB=%SLN%\vcpkg_installed\x64-custom\x64-custom\lib;%LIB%"
cd /d %SLN%
set COMMON=/p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v145 /p:SpectreMitigation=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:WholeProgramOptimization=false /p:VcpkgEnabled=false /p:VcpkgEnableManifest=false /p:SolutionDir=%SLN%\ /v:minimal /nologo

echo === regenerate config.h + crtheaders.h ===
del "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h" 2>nul
powershell.exe -ExecutionPolicy Bypass -File "%SLN%\config.ps1" -Config_h_vs "%SLN%\config.h.vs" -Config_h "%ROOT%\config.h" -VCIncludePath "%INCLUDE%" -OutCRTHeader "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h"

echo === [1/4] openbsd_compat ===
msbuild openbsd_compat.vcxproj %COMMON%
echo OPENBSD_EXIT=%ERRORLEVEL%
echo === [2/4] posix_compat ===
msbuild win32iocompat.vcxproj %COMMON%
echo POSIX_EXIT=%ERRORLEVEL%
echo === [3/4] libssh ===
msbuild libssh.vcxproj %COMMON%
echo LIBSSH_EXIT=%ERRORLEVEL%
echo === [4/4] ssh.exe ===
msbuild ssh.vcxproj %COMMON%
echo SSH_EXIT=%ERRORLEVEL%
echo === artifact ===
dir /b "%SLN%\bin\x64\Release\ssh.exe" 2>nul
dir /b "%ROOT%\bin\x64\Release\ssh.exe" 2>nul
