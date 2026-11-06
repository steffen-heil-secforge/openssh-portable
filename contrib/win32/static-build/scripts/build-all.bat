@echo off
rem Builds the release client exes (no ssh-agent) into %ROOT%\bin\x64\Release.
setlocal EnableDelayedExpansion
call "%~dp0env.bat" || exit /b 1
set "INCLUDE=%VCI%\include;%INCLUDE%"
set "LIB=%VCI%\lib;%LIB%"
rem /sdl turns v145's C4703/C4701 false positives (sftp-client.c, ssh-keygen.c)
rem into errors; _CL_ is appended after the project options.
set "_CL_=/wd4703 /wd4701"
cd /d "%SLN%"

echo === regen config.h + crtheaders.h ===
del "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h" 2>nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SLN%\config.ps1" -Config_h_vs "%SLN%\config.h.vs" -Config_h "%ROOT%\config.h" -VCIncludePath "%INCLUDE%" -OutCRTHeader "%ROOT%\contrib\win32\win32compat\inc\crtheaders.h"
if errorlevel 1 ( echo ERROR: config.ps1 failed & exit /b 1 )

for %%P in (openbsd_compat win32iocompat libssh ssh scp sftp ssh-add keygen ssh-keyscan ssh-pkcs11-helper ssh-sk-helper) do (
    echo === building %%P ===
    msbuild %%P.vcxproj %COMMON%
    if !ERRORLEVEL! NEQ 0 ( echo ERROR: build of %%P failed & exit /b 1 )
)
echo === produced exes in %ROOT%\bin\x64\Release ===
dir /b "%ROOT%\bin\x64\Release\*.exe"
echo BUILD_OK
