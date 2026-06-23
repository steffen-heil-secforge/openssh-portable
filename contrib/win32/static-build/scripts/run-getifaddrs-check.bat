@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
cd /d L:\Development\openssh-portable\contrib\win32\win32compat
echo === compile+link getifaddrs_check.c + getifaddrs.c (x64) ===
cl /nologo /W3 /D_WIN32_WINNT=0x601 /DWIN32 /D_CRT_DECLARE_NONSTDC_NAMES=0 getifaddrs_check.c getifaddrs.c ws2_32.lib iphlpapi.lib /Fe:getifaddrs_check.exe
echo BUILD_EXIT=%ERRORLEVEL%
echo === run ===
getifaddrs_check.exe
echo RUN_EXIT=%ERRORLEVEL%
del getifaddrs_check.exe getifaddrs_check.obj getifaddrs.obj 2>nul
