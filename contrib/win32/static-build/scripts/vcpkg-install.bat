@echo off
rem Builds the static dependencies (zlib, libcbor, libressl, libfido2) for
rem triplet x64-custom into contrib\win32\openssh\vcpkg_installed (manifest mode).
setlocal
call "%~dp0env.bat" || exit /b 1
if not defined VCPKG_ROOT ( echo ERROR: vcpkg checkout not found - set VCPKG_ROOT & exit /b 1 )
where git >nul 2>&1 || ( echo ERROR: git not on PATH - vcpkg manifest mode needs it & exit /b 1 )
set VCPKG_DISABLE_METRICS=1
set "VCPKG_VISUAL_STUDIO_PATH=%VSINSTALL%"

echo === vcpkg at %VCPKG_ROOT% ===
if not exist "%VCPKG_ROOT%\vcpkg.exe" call "%VCPKG_ROOT%\bootstrap-vcpkg.bat" -disableMetrics
if not exist "%VCPKG_ROOT%\vcpkg.exe" ( echo ERROR: vcpkg bootstrap failed & exit /b 1 )
"%VCPKG_ROOT%\vcpkg.exe" version

echo === manifest install in %SLN% (triplet x64-custom) ===
cd /d "%SLN%"
"%VCPKG_ROOT%\vcpkg.exe" install --triplet x64-custom --overlay-ports="%SLN%\vcpkg_overlay_ports" --overlay-triplets="%SLN%\vcpkg_triplets" --x-install-root="%SLN%\vcpkg_installed\x64-custom"
if errorlevel 1 ( echo ERROR: vcpkg install failed & exit /b 1 )
for %%L in (libcrypto.lib zs.lib fido2.lib cbor.lib) do if not exist "%VCI%\lib\%%L" ( echo ERROR: %%L missing in %VCI%\lib & exit /b 1 )
if exist "%VCI%\bin\libcrypto*.dll" ( echo ERROR: libcrypto DLL built - the triplet is not static & exit /b 1 )
echo VCPKG_OK
