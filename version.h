/* $OpenBSD: version.h,v 1.110 2026/08/10 23:27:30 djm Exp $ */

#define SSH_WINDOWS_VERSION "OpenSSH_for_Windows_10.5"
#define SSH_WINDOWS_BANNER " Win32-OpenSSH-GitHub"
#define SSH_VERSION	SSH_WINDOWS_VERSION SSH_WINDOWS_BANNER

#define SSH_PORTABLE	"p1"
/* secforge build marker: shown by `-V` only (SSH_RELEASE); the wire banner
 * (SSH_VERSION) is deliberately left unchanged. */
#define SSH_SECFORGE_BUILD " secforge.2+pr859.pr860"
#define SSH_RELEASE	SSH_WINDOWS_VERSION SSH_PORTABLE SSH_WINDOWS_BANNER SSH_SECFORGE_BUILD
