#ifndef _INCLUDE_METAMOD_SOURCE_DOSPROTECT_MAIN_H
#define _INCLUDE_METAMOD_SOURCE_DOSPROTECT_MAIN_H

#define DOSP_VERSION "2.0.0-dev.3"

#include "platform_wrappers.h"

#include <ISmmPlugin.h>
#include "tier0/vcrmode.h"

class DoSProtect :
    public ISmmPlugin,
    public IConCommandBaseAccessor
{
public:
    bool Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlen, bool late);
    bool Unload(char *error, size_t maxlen);
    bool RegisterConCommandBase(ConCommandBase *pCommandBase);

public:
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

#endif
