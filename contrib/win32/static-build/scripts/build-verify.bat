@echo off
rem Builds and runs unittest-win32compat (getifaddrs + SO_ERROR connect tests).
rem Needs admin: the harness copies test files to C:\ProgramData\ssh.
setlocal
call "%~dp0env.bat" || exit /b 1
set "INCLUDE=%VCI%\include;%INCLUDE%"
set "LIB=%VCI%\lib;%LIB%"
cd /d "%SLN%"
msbuild unittest-win32compat.vcxproj %COMMON%
if errorlevel 1 ( echo ERROR: unittest build failed & exit /b 1 )
"%ROOT%\bin\x64\Release\unittest-win32compat\unittest-win32compat.exe"
echo UNITTEST_RUN_EXIT=%ERRORLEVEL%
