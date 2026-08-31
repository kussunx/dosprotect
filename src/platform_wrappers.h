#ifndef _INCLUDE_SOURCEMOD_PLATFORM_H_
#define _INCLUDE_SOURCEMOD_PLATFORM_H_

#if defined WIN32 && !defined snprintf
#define snprintf _snprintf
#endif

#if defined WIN32 || defined WIN64
#define PLATFORM_WINDOWS
#if !defined WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#if !defined snprintf
#define snprintf _snprintf
#endif
#if !defined stat
#define stat _stat
#endif
#define strcasecmp strcmpi
#define strncasecmp strnicmp
#include <winsock2.h>
#include <windows.h>
#include <direct.h>
#define PLATFORM_LIB_EXT "dll"
#define PLATFORM_MAX_PATH MAX_PATH
#define PLATFORM_SEP_CHAR '\\'
#define PLATFORM_SEP_ALTCHAR '/'
#define PLATFORM_EXTERN_C extern "C" __declspec(dllexport)
#if defined _MSC_VER && _MSC_VER >= 1400
#define SUBPLATFORM_SECURECRT
#endif
#elif defined __linux__ || defined __APPLE__
#if defined __linux__
#define PLATFORM_LINUX
#elif defined __APPLE__
#define PLATFORM_APPLE
#endif
#define PLATFORM_POSIX
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <sys/socket.h>
#if defined PLATFORM_APPLE
#include <sys/syslimits.h>
#endif
#define PLATFORM_MAX_PATH PATH_MAX
#define PLATFORM_LIB_EXT "so"
#define PLATFORM_SEP_CHAR '/'
#define PLATFORM_SEP_ALTCHAR '\\'
#define PLATFORM_EXTERN_C extern "C" __attribute__((visibility("default")))
#endif

#endif
