#ifndef _INCLUDE_METAMOD_SOURCE_DoSProtect_MAIN_H
#define _INCLUDE_METAMOD_SOURCE_DoSProtect_MAIN_H

#define		DOSP_VERSION		"1.0.0.0"

#include "platform_wrappers.h"

#include <ISmmPlugin.h>
#include "tier0/vcrmode.h"
#include <sh_list.h>

struct DoSCount
{
	int ip[4];
	unsigned int count;
};

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
