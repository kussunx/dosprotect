
#include "extension.h"

#if SOURCE_ENGINE >= 3
#define CallGlobalChangeCallback CallGlobalChangeCallbacks
SH_DECL_HOOK3_void(ICvar, CallGlobalChangeCallback, SH_NOATTRIB, false, ConVar *, const char *, float);
ICvar *icvar = NULL;
ConVar *pConVar_dosp_enable = NULL;
#endif

DoSProtect g_DoSProtect;
SourceHook::List<DoSCount *> m_pDoSAddr;
bool g_recvfrom_hooked = false;
int (*g_real_recvfrom_ptr)(int , char *, int , int , struct sockaddr *, int *);

PLUGIN_EXPOSE(DoSProtect, g_DoSProtect);

void AddDoSCount(int ip1, int ip2, int ip3, int ip4)
{
	SourceHook::List<DoSCount *>::iterator iter;
	DoSCount *pInfo;
	for(iter=m_pDoSAddr.begin(); iter!=m_pDoSAddr.end(); iter++)
	{
		pInfo = (*iter);
		if(ip1 == pInfo->ip[0] && ip2 == pInfo->ip[1] && ip3 == pInfo->ip[2] && ip4 == pInfo->ip[3])
		{
			pInfo->count++;
			return;
		}
	}
	DoSCount *d = new DoSCount;
	d->ip[0] = ip1;
	d->ip[1] = ip2;
	d->ip[2] = ip3;
	d->ip[3] = ip4;
	d->count = 1;
	m_pDoSAddr.push_back(d);
}

void UnHookRecvFrom()
{
	if(g_recvfrom_hooked)
	{
		g_pVCR->Hook_recvfrom = g_real_recvfrom_ptr;
		g_recvfrom_hooked = false;
		META_CONPRINT("[-] DoS Attack Protect - Disable\n");
	}
}

int MyRecvFromHook(int s, char *buf, int len, int flags, struct sockaddr *from, int *fromlen)
{
	int ret = g_real_recvfrom_ptr(s,buf,len,flags,from,fromlen);
	if(ret == 0)
	{
		AddDoSCount((unsigned char)from->sa_data[2],(unsigned char)from->sa_data[3],(unsigned char)from->sa_data[4],(unsigned char)from->sa_data[5]);
		return 25;
	}
	return ret;
}

void ReHookRecvFrom()
{
	if(!g_recvfrom_hooked)
	{
		g_real_recvfrom_ptr = g_pVCR->Hook_recvfrom;
		g_pVCR->Hook_recvfrom = &MyRecvFromHook;
		g_recvfrom_hooked = true;
		META_CONPRINT("[-] DoS Attack Protect - Enable\n");
	}
}

void ClearDosAddrList()
{
	SourceHook::List<DoSCount *>::iterator iter;
	DoSCount *pInfo;
	for(iter=m_pDoSAddr.begin(); iter!=m_pDoSAddr.end(); iter++)
	{
		pInfo = (*iter);
		delete pInfo;
	}
	m_pDoSAddr.clear();
}
void dosp_status_CommandCallback()
{
	if(g_recvfrom_hooked)
	{
		META_CONPRINT("[-] DoS Attack Protect - Enable\n");
	} else {
		META_CONPRINT("[-] DoS Attack Protect - Disable\n");
	}
	META_CONPRINT(" Attacker IP\t|\tPacket\n--------------------------------\n");
	SourceHook::List<DoSCount *>::iterator iter;
	DoSCount *pInfo;
	for(iter=m_pDoSAddr.begin(); iter!=m_pDoSAddr.end(); iter++)
	{
		pInfo = (*iter);
		META_CONPRINTF(" %d.%d.%d.%d\t|\t%d\n",pInfo->ip[0],pInfo->ip[1],pInfo->ip[2],pInfo->ip[3],pInfo->count);
	}
	META_CONPRINT("--------------------------------\n");
}

#if SOURCE_ENGINE >= 3
void OnDoSPEnableChange(ConVar *var, const char *pOldValue, float flOldValue)
{
	if(var != pConVar_dosp_enable)
		return;

#else
void OnDoSPEnableChange(ConVar *var, char const *pOldValue)
{
#endif

	if(strcmp(var->GetString(), pOldValue) == 0)
		return;

	if(var->GetInt() == 1)
	{
		ReHookRecvFrom();
	} else {
		UnHookRecvFrom();
	}
}

bool DoSProtect::Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlen, bool late)
{	
	PLUGIN_SAVEVARS();

	ReHookRecvFrom();

	new ConVar("dosp_version",DOSP_VERSION,FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY,"DoS Protect Version");

	new ConCommand("dosp_status",dosp_status_CommandCallback, "", 0);

#if SOURCE_ENGINE >= 3
	GET_V_IFACE_CURRENT(GetEngineFactory, icvar, ICvar, CVAR_INTERFACE_VERSION);
	g_pCVar = icvar;
	pConVar_dosp_enable = new ConVar("dosp_enable","1",0,"   1 = Enable DoS Protect (default), 0 = Disable DoS Protect");
	SH_ADD_HOOK_STATICFUNC(ICvar, CallGlobalChangeCallback, icvar, OnDoSPEnableChange, false);
	ConVar_Register(0, this);
#else
	new ConVar("dosp_enable","1",0,"   1 = Enable DoS Protect (default), 0 = Disable DoS Protect",OnDoSPEnableChange);
	ConCommandBaseMgr::OneTimeInit(this);
#endif

	return true;
}

bool DoSProtect::Unload(char *error, size_t maxlen)
{
	#if SOURCE_ENGINE >= 3
	SH_REMOVE_HOOK_STATICFUNC(ICvar, CallGlobalChangeCallbacks, icvar, OnDoSPEnableChange, false);
	#endif

	UnHookRecvFrom();

	ClearDosAddrList();

	return true;
}

bool DoSProtect::RegisterConCommandBase(ConCommandBase *pCommandBase)
{
	META_REGCVAR(pCommandBase);

	return true;
} 

const char *DoSProtect::GetLicense()
{
	return "www.ZombieX2,net";
}

const char *DoSProtect::GetVersion()
{
	return DOSP_VERSION;
}

const char *DoSProtect::GetDate()
{
	return __DATE__;
}

const char *DoSProtect::GetLogTag()
{
	return "DOSP";
}

const char *DoSProtect::GetAuthor()
{
	return "ZombieX2.net";
}

const char *DoSProtect::GetDescription()
{
	return "Prevent DoS attack cause server lag";
}

const char *DoSProtect::GetName()
{
	return "DoS Protect";
}

const char *DoSProtect::GetURL()
{
	return "http://www.ZombieX2.net/";
}
