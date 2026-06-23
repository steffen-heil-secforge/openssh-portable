@echo off
set "PATH=C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd;%PATH%"
set VCPKG_ROOT=L:\Development\vcpkg
set VCPKG_DISABLE_METRICS=1
set VCPKG_VISUAL_STUDIO_PATH=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools
set VCPKG_PLATFORM_TOOLSET=v145
set OV=L:\Development\openssh-portable\contrib\win32\openssh
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul

echo === bootstrapping vcpkg ===
if not exist "%VCPKG_ROOT%\vcpkg.exe" call "%VCPKG_ROOT%\bootstrap-vcpkg.bat" -disableMetrics
"%VCPKG_ROOT%\vcpkg.exe" version
git --version

echo === manifest install in %OV% (triplet x64-custom) ===
cd /d %OV%
"%VCPKG_ROOT%\vcpkg.exe" install ^
  --triplet x64-custom ^
  --overlay-ports="%OV%\vcpkg_overlay_ports" ^
  --overlay-triplets="%OV%\vcpkg_triplets" ^
  --x-install-root="%OV%\vcpkg_installed\x64-custom"
echo VCPKG_EXIT=%ERRORLEVEL%
echo === installed libs ===
dir /b "%OV%\vcpkg_installed\x64-custom\x64-custom\lib" 2>nul
