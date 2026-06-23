@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsamd64_arm64.bat" >nul
set ROOT=L:\Development\openssh-portable
set SLN=%ROOT%\contrib\win32\openssh
echo TARGET_ARCH=%VSCMD_ARG_TGT_ARCH%

echo === [1] standalone compile+link getifaddrs.c for ARM64 ===
cd /d %ROOT%\contrib\win32\win32compat
cl /nologo /W3 /D_WIN32_WINNT=0x0A00 /DWIN32 /D_CRT_DECLARE_NONSTDC_NAMES=0 getifaddrs_check.c getifaddrs.c ws2_32.lib iphlpapi.lib /Fe:getifaddrs_arm64.exe
echo ARM64_LINK_EXIT=%ERRORLEVEL%
del getifaddrs_arm64.exe *.obj 2>nul

echo === [2] build posix_compat.lib for ARM64 (all win32compat incl. getifaddrs.c) ===
cd /d %SLN%
del "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h" 2>nul
powershell.exe -ExecutionPolicy Bypass -File "%SLN%\config.ps1" -Config_h_vs "%SLN%\config.h.vs" -Config_h "%ROOT%\config.h" -VCIncludePath "%INCLUDE%" -OutCRTHeader "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h"
msbuild win32iocompat.vcxproj /p:Configuration=Release /p:Platform=ARM64 /p:PlatformToolset=v145 /p:SpectreMitigation=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:VcpkgEnabled=false /p:VcpkgEnableManifest=false /p:SolutionDir=%SLN%\ /v:minimal /nologo
echo ARM64_POSIXCOMPAT_EXIT=%ERRORLEVEL%
dir /b "%SLN%\lib\ARM64\Release\posix_compat.lib" 2>nul
