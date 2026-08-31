#pragma once

#define DOSP_VERSION "2.0.0"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <winsock2.h>
#include <windows.h>

#include <ISmmPlugin.h>
#include "tier0/vcrmode.h"

class DoSProtect : public ISmmPlugin, public IConCommandBaseAccessor
{
public:
    bool Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlen, bool late);
    bool Unload(char *error, size_t maxlen);
    bool RegisterConCommandBase(ConCommandBase *pCommandBase);

    const char *GetAuthor();
    const char *GetName();
    const char *GetDescription();
    const char *GetURL();
    const char *GetLicense();
    const char *GetVersion();
    const char *GetDate();
    const char *GetLogTag();
};

PLUGIN_GLOBALVARS();
