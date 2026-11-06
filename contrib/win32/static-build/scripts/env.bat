@echo off
rem Common environment for the static build scripts: "call env.bat || exit /b 1".
rem Sets ROOT (repo root), SLN, VCI (vcpkg install dir), VCPKG_ROOT, COMMON
rem (MSBuild overrides) and the x64 MSVC environment (vcvars64).

for %%I in ("%~dp0..\..\..\..") do set "ROOT=%%~fI"
set "SLN=%ROOT%\contrib\win32\openssh"
set "VCI=%SLN%\vcpkg_installed\x64-custom\x64-custom"

rem vcpkg checkout: %VCPKG_ROOT%, else ..\vcpkg or ..\..\vcpkg next to the tree
if not defined VCPKG_ROOT if exist "%ROOT%\..\vcpkg\.git" for %%I in ("%ROOT%\..\vcpkg") do set "VCPKG_ROOT=%%~fI"
if not defined VCPKG_ROOT if exist "%ROOT%\..\..\vcpkg\.git" for %%I in ("%ROOT%\..\..\vcpkg") do set "VCPKG_ROOT=%%~fI"

rem newest Visual Studio (any edition, incl. Build Tools) with the x64 C++ tools
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" ( echo ERROR: vswhere.exe not found - is Visual Studio installed? & exit /b 1 )
set "VSINSTALL="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSINSTALL=%%I"
if not defined VSINSTALL ( echo ERROR: no Visual Studio with x64 C++ tools found & exit /b 1 )
call "%VSINSTALL%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 ( echo ERROR: vcvars64.bat failed & exit /b 1 )

rem MSBuild overrides (see BUILD-NOTES.md): Spectre libs not installed, LTCG
rem hits LNK1000 on the static libcrypto, vcpkg integration off (prebuilt VCI).
set COMMON=/p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v145 /p:SpectreMitigation=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /p:WholeProgramOptimization=false /p:VcpkgEnabled=false /p:VcpkgEnableManifest=false /p:SolutionDir=%SLN%\ /m /v:minimal /nologo
exit /b 0
