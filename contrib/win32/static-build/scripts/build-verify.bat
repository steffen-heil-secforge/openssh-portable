@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set ROOT=L:\Development\openssh-portable
set SLN=%ROOT%\contrib\win32\openssh
set VCB=%SLN%\vcpkg_installed\x64-custom\x64-custom\bin
cd /d %SLN%
set COMMON=/p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v145 /p:SpectreMitigation=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:VcpkgEnabled=false /p:VcpkgEnableManifest=false /p:SolutionDir=%SLN%\ /v:minimal /nologo

echo === regen config.h + crtheaders.h ===
del "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h" 2>nul
powershell.exe -ExecutionPolicy Bypass -File "%SLN%\config.ps1" -Config_h_vs "%SLN%\config.h.vs" -Config_h "%ROOT%\config.h" -VCIncludePath "%INCLUDE%" -OutCRTHeader "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h"

echo === build libs + ssh.exe (verifies pragma-free link via Iphlpapi.lib in ssh.vcxproj) ===
msbuild openbsd_compat.vcxproj %COMMON%
echo OPENBSD_EXIT=%ERRORLEVEL%
msbuild win32iocompat.vcxproj %COMMON%
echo POSIX_EXIT=%ERRORLEVEL%
msbuild libssh.vcxproj %COMMON%
echo LIBSSH_EXIT=%ERRORLEVEL%
msbuild ssh.vcxproj %COMMON%
echo SSH_EXIT=%ERRORLEVEL%

echo === build unittest-win32compat (compiles getifaddrs_tests.c, links Iphlpapi.lib) ===
msbuild unittest-win32compat.vcxproj %COMMON%
echo UNITTEST_BUILD_EXIT=%ERRORLEVEL%

echo === run getifaddrs unit test ===
set UTDIR=%ROOT%\bin\x64\Release\unittest-win32compat
copy /Y "%VCB%\*.dll" "%UTDIR%\" >nul 2>&1
"%UTDIR%\unittest-win32compat.exe"
echo UNITTEST_RUN_EXIT=%ERRORLEVEL%
