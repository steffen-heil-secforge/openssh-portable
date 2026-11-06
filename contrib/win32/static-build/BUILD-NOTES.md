# Windows static x64 build notes (secforge build)

The `secforge-build` branch = upstream `latestw_all` + our pending upstream PRs
+ this build environment. It captures everything needed to reproduce the
**statically linked x64** Windows client suite published as the
`v*-secforge*` releases (single-file binaries, no `libcrypto.dll`).

Pending upstream PRs carried on this branch:
- PowerShell/openssh-portable#859 - `Match localnetwork` / `getifaddrs()`
- PowerShell/openssh-portable#860 - report failed async `connect()` via
  `getsockopt(SO_ERROR)` (IPv6 -> IPv4 fallback)

> These are **local build choices, not for upstream.** The clean feature changes
> live on their PR branches. Microsoft ships LibreSSL as a DLL; this branch
> links it statically. Keep that separate.

## Release naming

Tag `v<upstream>-secforge[.<n>]+<prs>`, e.g.:

| Build                                   | Tag                                  |
|-----------------------------------------|--------------------------------------|
| first build on a given upstream version | `v10.5p1-secforge+pr859.pr860`       |
| second build on the same upstream       | `v10.5p1-secforge.2+pr859.pr860`     |
| third ...                               | `v10.5p1-secforge.3+pr859.pr860`     |

- `<upstream>` = `SSH_WINDOWS_VERSION` + `SSH_PORTABLE` from `version.h`.
- `.<n>` counts rebuilds on the same upstream version (omitted for the first);
  it restarts when the upstream version changes.
- `+<prs>` (SemVer build metadata, dot-separated, one `+` only) lists the
  carried PRs; drop a PR from it once upstream has merged it.
- Set `SSH_SECFORGE_BUILD` in `version.h` to the same suffix (without
  `v<upstream>-`), e.g. `" secforge.2+pr859.pr860"`; `ssh -V` then shows
  `OpenSSH_for_Windows_10.5p1 Win32-OpenSSH-GitHub secforge.2+pr859.pr860, ...`.
  The wire banner (`SSH_VERSION`) is never changed.
- Zip: `OpenSSH_for_Windows_<tag without v>-static-x64.zip`, containing
  exactly: `ssh.exe scp.exe sftp.exe ssh-add.exe ssh-keygen.exe
  ssh-keyscan.exe ssh-pkcs11-helper.exe ssh-sk-helper.exe` +
  `Install-OpenSSH.ps1` + `README.txt`. **No `ssh-agent.exe`** - the agent is
  not part of the release (the installer copies every `*.exe` next to it, so
  do not put one there).

## What diverges from the feature branch (and why)

| File | Change | Why |
|------|--------|-----|
| `contrib/win32/openssh/vcpkg_triplets/x64-custom.cmake` | LibreSSL built **static** (was dynamic); `/Qspectre` removed | Static libcrypto → no `libcrypto.dll`. Spectre-mitigated libs aren't installed for the toolset, so `/Qspectre` is dropped (it makes CMake's VS generator demand them). |
| `contrib/win32/openssh/config.h.vs` | `#define HAVE_EVP_DIGESTSIGN` / `HAVE_EVP_DIGESTVERIFY` | Static LibreSSL 4.2.0 exports these; without the defines, `openbsd-compat/openssl-compat.c` also defines them → `LNK2005` duplicate symbols. (The dynamic build hides this via the import lib.) |
| `contrib/win32/openssh/Directory.Build.targets` | New: prepends the vcpkg `include`/`lib` dirs to `IncludePath`/`LibraryPath` | The manual build disables the vcpkg MSBuild integration (`VcpkgEnabled=false`), and `openbsd_compat.vcxproj` doesn't list the vcpkg include path itself, so it can't find `openssl/*.h` without this. |

Everything else is passed as **MSBuild command-line overrides** (see the
scripts) so the `.vcxproj` files stay unmodified.

## Environment (what these scripts assume)

- Windows host driven from WSL; build done on a real drive (`L:`), not the
  `\\wsl.localhost` UNC path (MSBuild/CMake choke on UNC cwd).
- Repo copy at `L:\Development\openssh-portable`.
- **VS 2018 Build Tools** (`...\Microsoft Visual Studio\18\BuildTools`) — only
  toolsets `v141` and `v145` are installed (the projects pin `v143`, which is
  absent → override to `v145`).
- **VS 2018 Community** present too — used for its bundled **git** (vcpkg
  manifest mode needs git) and the **ARM64 cross compiler**.
- vcpkg checkout at `L:\Development\vcpkg` (see below).

## Build pipeline (scripts in `scripts/`)

1. **Provision vcpkg** (one-time): `git clone https://github.com/microsoft/vcpkg`,
   `git checkout a345bbdc68cdfda65603e24413b21afb28f110fb` (the
   `builtin-baseline` from `contrib/win32/openssh/vcpkg.json`), keep `.git`
   (classic mode was removed in the 2026 vcpkg tool → **manifest mode only**,
   which resolves the baseline via git). Put it on `L:` and `bootstrap-vcpkg.bat`.
2. **`vcpkg-install.bat`** — manifest install of `zlib`/`libcbor`/`libressl`/`libfido2`
   for triplet `x64-custom` (now fully static) into `…\vcpkg_installed\x64-custom`.
3. **`build-all.bat`** — generates `config.h`/`crtheaders.h` (via `config.ps1`)
   and builds `openbsd_compat`, `posix_compat`, `libssh`, then the 8 client exes.
4. **`build-3.bat`** — rebuilds `scp`/`sftp`/`keygen` with `_CL_=/wd4703 /wd4701`
   (see gotchas).
5. **`build-verify.bat`** — builds + runs `unittest-win32compat` (getifaddrs tests).
6. **`build-arm64.bat`** — compiles `getifaddrs.c` and `posix_compat.lib` for ARM64.
7. **`run-getifaddrs-check.bat`**, **`smoke-static.bat`** — runtime/feature checks.

### MSBuild overrides used everywhere
```
/p:PlatformToolset=v145                 (project pins v143, not installed)
/p:SpectreMitigation=false              (Spectre libs not installed)
/p:WholeProgramOptimization=false       (LTCG hits LNK1000 on the 23MB static libcrypto)
/p:WindowsTargetPlatformVersion=10.0.26100.0
/p:VcpkgEnabled=false /p:VcpkgEnableManifest=false   (use the prebuilt vcpkg_installed)
/p:SolutionDir=<...>\contrib\win32\openssh\
```

## Gotchas (chronological)

- **`v143` toolset missing** → `/p:PlatformToolset=v145`.
- **`MSB8040` Spectre libs required** → `/p:SpectreMitigation=false` and drop
  `/Qspectre` from the triplet (for the vcpkg ports).
- **vcpkg classic mode removed** (2026 tool) → manifest mode → needs git +
  `.git` in `VCPKG_ROOT`; used the VS Community bundled git.
- **`LNK1000 IMAGE::BuildImage`** when statically linking the 23 MB libcrypto →
  `/p:WholeProgramOptimization=false` (disable LTCG).
- **`LNK2005`** `EVP_DigestSign`/`Verify` duplicated → `HAVE_EVP_DIGESTSIGN`/
  `HAVE_EVP_DIGESTVERIFY` in `config.h.vs`.
- **`C4703`** (uninitialized pointer) in `sftp-client.c`/`ssh-keygen.c`, elevated
  to errors by `/sdl` under v145 → `set _CL_=/wd4703 /wd4701` (note:
  `/p:SDLCheck=false` does NOT work — `SDLCheck` is `ClCompile` item metadata,
  not a global property).
- **openbsd_compat can't find `openssl/*.h`** with the vcpkg integration off →
  `Directory.Build.targets` injects the include/lib paths.

## Installer

`installer/Install-OpenSSH.ps1` (+ `README.txt`, ship both in the zip) —
self-elevating installer that installs the binaries into
`%WINDIR%\System32\OpenSSH` (creating it if needed), adds it to the system
`PATH`, removes the `OpenSSH.Client` Windows Capability, and backs up existing
binaries as `<name>.<version>.bak`. Uses the SID `*S-1-5-32-544` for `icacls` (the name
"Administrators" fails on non-English Windows, error 1332). The binaries
themselves are **not** in git — see the GitHub releases.
