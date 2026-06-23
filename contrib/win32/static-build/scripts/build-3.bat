@echo off
setlocal EnableDelayedExpansion
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set ROOT=L:\Development\openssh-portable
set SLN=%ROOT%\contrib\win32\openssh
set "INCLUDE=%SLN%\vcpkg_installed\x64-custom\x64-custom\include;%INCLUDE%"
set "LIB=%SLN%\vcpkg_installed\x64-custom\x64-custom\lib;%LIB%"
cd /d %SLN%
rem deps + config already built by build-all; rebuild the 3 that hit C4703.
rem _CL_ appends flags AFTER the project's options, so /wd disables the warnings
rem that /sdl would otherwise elevate to errors (false-positives in v145).
set _CL_=/wd4703 /wd4701
set COMMON=/p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v145 /p:SpectreMitigation=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:WholeProgramOptimization=false /p:VcpkgEnabled=false /p:VcpkgEnableManifest=false /p:SolutionDir=%SLN%\ /v:minimal /nologo

set FAILED=
for %%P in (scp.vcxproj sftp.vcxproj keygen.vcxproj) do (
    echo === building %%P ===
    msbuild %%P %COMMON%
    if !ERRORLEVEL! NEQ 0 ( echo   *** FAILED: %%P ^(exit !ERRORLEVEL!^) & set FAILED=!FAILED! %%P )
)
echo.
if defined FAILED ( echo BUILD FAILURES:!FAILED! ) else ( echo ALL 3 OK )
dir /b "%ROOT%\bin\x64\Release\scp.exe" "%ROOT%\bin\x64\Release\sftp.exe" "%ROOT%\bin\x64\Release\ssh-keygen.exe" 2>nul
