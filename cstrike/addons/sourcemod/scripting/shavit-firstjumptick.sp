#include <sourcemod>
#include <sdktools>
#include <clientprefs>
 
#undef REQUIRE_PLUGIN
#include <shavit>
 
#pragma newdecls required
#pragma semicolon 1

Handle gH_FirstJumpTickCookie;
Handle gH_CookieSet;

bool gB_FirstJumpTick[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "[shavit] First Jump Tick",
	author = "Blank & Fixed by Nairda",
	description = "Print which tick first jump was at",
	version = "1.1d",
	url = ""
}

chatstrings_t gS_ChatStrings;

public void OnAllPluginsLoaded()
{
	HookEvent("player_jump", OnPlayerJump);
}

public void OnPluginStart()
{
	LoadTranslations("shavit-firstjumptick.phrases");

	RegConsoleCmd("sm_fjt", Command_FirstJumpTick, "Toggles Jump Tick Printing");
	RegConsoleCmd("sm_jumptick", Command_FirstJumpTick, "Toggles Jump Tick Printing");
	RegConsoleCmd("sm_tick", Command_FirstJumpTick, "Toggles Jump Tick Printing");
	RegConsoleCmd("sm_jt", Command_FirstJumpTick, "Toggles Jump Tick Printing");

	gH_FirstJumpTickCookie = RegClientCookie("FJT_enabled", "FJT_enabled", CookieAccess_Protected);
	gH_CookieSet = RegClientCookie("FJT_default", "FJT_default", CookieAccess_Protected);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(AreClientCookiesCached(i))
		{
			OnClientCookiesCached(i);
		}
	}
}

public void OnClientCookiesCached(int client)
{
	char sCookie[8];
	GetClientCookie(client, gH_CookieSet, sCookie, sizeof(sCookie));

	if(StringToInt(sCookie) == 0)
	{
		SetCookie(client, gH_FirstJumpTickCookie, false);
		SetCookie(client, gH_CookieSet, true);
	}

	GetClientCookie(client, gH_FirstJumpTickCookie, sCookie, sizeof(sCookie));
	gB_FirstJumpTick[client] = view_as<bool>(StringToInt(sCookie));
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
}

public Action Command_FirstJumpTick(int client, int args)
{
	if(!gB_FirstJumpTick[client])
	{
		gB_FirstJumpTick[client] = true;
		SetCookie(client, gH_FirstJumpTickCookie, gB_FirstJumpTick[client]);
		Shavit_PrintToChat(client, "%T", "FirstJumpTickEnabled", client, gS_ChatStrings.sVariable);
	}

	else
	{
		gB_FirstJumpTick[client] = false;
		SetCookie(client, gH_FirstJumpTickCookie, gB_FirstJumpTick[client]);
		Shavit_PrintToChat(client, "%T", "FirstJumpTickDisabled", client, gS_ChatStrings.sVariable);
	}
}

public Action OnPlayerJump(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsValidClient(client))
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(GetHUDTarget(i) != client)
			{
				continue;
			}

			PrintJumpTick(i, client);
		}
	}

	return Plugin_Continue;
}

int GetHUDTarget(int client)
{
	int target = client;

	if(IsValidClient(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(!IsValidClientIndex(iTarget))
			{
				target = iTarget;
			}
		}
	}

	return target;
}

void PrintJumpTick(int client, int target)
{  
	if(gB_FirstJumpTick[client])
	{
		if(Shavit_InsideZone(target, Zone_Start, -1))
		{
			Shavit_PrintToChat(client, "%T", "ZeroTick", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		}    
		else if(Shavit_GetTimerStatus(target) == Timer_Running && Shavit_GetClientJumps(target) == 1)
		{
			Shavit_PrintToChat(client, "%T", "PrintFirstJumpTick", client, gS_ChatStrings.sVariable, RoundToFloor((Shavit_GetClientTime(target) * 100)), gS_ChatStrings.sText);
		}
	}
}

stock void SetCookie(int client, Handle hCookie, int n)
{
	char sCookie[64];

	IntToString(n, sCookie, sizeof(sCookie));
	SetClientCookie(client, hCookie, sCookie);
}

// We don't want the -1 client id bug. Thank Volvo™ for this
stock bool IsValidClientIndex(int client)
{
	return (0 < client <= MaxClients);
}
