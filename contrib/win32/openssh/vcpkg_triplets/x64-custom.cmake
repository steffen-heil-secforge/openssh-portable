set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_ENV_PASSTHROUGH __VCVARSALL_SPECTRE)
set(VCPKG_CXX_FLAGS "/guard:cf /W3")
set(VCPKG_C_FLAGS "/guard:cf /W3")
set(VCPKG_LINKER_FLAGS "/guard:cf /DYNAMICBASE /CETCOMPAT")

# STATIC BUILD (L:-local): link libcrypto statically into the binaries so
# there is no libcrypto.dll dependency. static CRT (/MT) matches ssh.exe.
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)

if(${PORT} MATCHES "zlib")
	set(VCPKG_CXX_FLAGS "${VCPKG_C_FLAGS} /sdl")
	set(VCPKG_C_FLAGS "${VCPKG_C_FLAGS} /sdl")
endif()
