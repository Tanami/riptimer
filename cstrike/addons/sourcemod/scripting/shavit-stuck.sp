#include <sourcemod>
#include <sdktools>
#include <shavit>

public Plugin myinfo = 
{
	name = "!stuck",
	author = "theSaint",
	description = "Unstuck player if he is stuck in textures",
	version = "1.0",
	url = "http://ggeasy.pl"
};

float LastVecPosition[MAXPLAYERS+1][3];
float CurrentVecPosition[MAXPLAYERS+1][3];
int Tries[MAXPLAYERS+1];
bool InProgress[MAXPLAYERS+1];
ConVar g_hStuckDistance;
float g_iStuckDistance;
ConVar g_hStuckEnabled;
int g_iStuckEnabled;


public void OnPluginStart()
{
	RegConsoleCmd("sm_stuck", Command_Stuck, "Unstuck player if he is stuck in textures");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	//Convar to enable and disable !stuck
	g_hStuckEnabled = CreateConVar("sm_stuck_enabled", "1.0", "Determine if !stuck command is avalivable", _, true, 0.0, true, 1.0);
	HookConVarChange(g_hStuckEnabled, CVarChange);
	g_iStuckEnabled = GetConVarInt(g_hStuckEnabled);
	
	//Convar for changeing stuck distance
	g_hStuckDistance = CreateConVar("sm_stuck_distance", "10.0", "Distance to move after writing !stuck", _, true, 0.0, true, 99.0);
	HookConVarChange(g_hStuckDistance, CVarChange);
	g_iStuckDistance = GetConVarFloat(g_hStuckDistance);
	
	// Auto execute the config!
	AutoExecConfig(true, "stuck");
}

public CVarChange(Handle convar, const char[] oldValue, const char[] newValue) 
{	
	g_iStuckDistance = GetConVarFloat(g_hStuckDistance);
	g_iStuckEnabled = GetConVarInt(g_hStuckEnabled);
}

public Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{		
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	GetClientAbsOrigin(client, LastVecPosition[client]);
	GetClientAbsOrigin(client, CurrentVecPosition[client]);
	Tries[client] = 0;
	InProgress[client] = false;
}

public Action Command_Stuck(int client, int args)
{
	if(!IsValidClient(client,true) || InProgress[client])
	{
		return Plugin_Handled;
	}
	
	if(g_iStuckEnabled == 0)
	{
		PrintToChat(client, "Command !stuck is currently disabled, probably becouse buggy nature of the map.");
		return Plugin_Handled;
	}
	
	if(Shavit_InsideZone(client, Zone_Start, -1))
	{
		PrintToChat(client, "You can't use !stuck while in start zone!");
		return Plugin_Handled;
	}

	InProgress[client] = true;
	GetClientAbsOrigin(client, CurrentVecPosition[client]);
	
	CreateTimer(0.1, timer_Stuck, client);
	return Plugin_Handled;
}

public Action timer_Stuck(Handle timer, int client)
{
	float NewVecPosition[3];
	GetClientAbsOrigin(client, NewVecPosition);
	float distance;
	
	distance = GetVectorDistance(CurrentVecPosition[client], NewVecPosition, true);
	
	if (distance != 0)
	{
		InProgress[client] = false;
		PrintToChat(client, "You can't use \"!stuck\" while in move...");
		return Plugin_Handled;
	}
	

	GetClientAbsOrigin(client, CurrentVecPosition[client]);
	distance = GetVectorDistance(CurrentVecPosition[client], LastVecPosition[client], true);
	
	if (distance > 10000)
	{
		LastVecPosition[client][0] = CurrentVecPosition[client][0];
		LastVecPosition[client][1] = CurrentVecPosition[client][1];
		LastVecPosition[client][2] = CurrentVecPosition[client][2];
	}
	
	NewVecPosition[0] = LastVecPosition[client][0];
	NewVecPosition[1] = LastVecPosition[client][1];
	NewVecPosition[2] = LastVecPosition[client][2];
	
	if (Tries[client] == 0)
	{
		NewVecPosition[0] = LastVecPosition[client][0] - g_iStuckDistance;
	}
	
	if (Tries[client] == 1)
	{
		NewVecPosition[0] = LastVecPosition[client][0] + g_iStuckDistance;
	}
	
	if (Tries[client] == 2)
	{
		NewVecPosition[1] = LastVecPosition[client][1] - g_iStuckDistance;
	}
	
	if (Tries[client] == 3)
	{
		NewVecPosition[1] = LastVecPosition[client][1] + g_iStuckDistance;
	}
	
	if (Tries[client] == 4)
	{
		NewVecPosition[2] = LastVecPosition[client][2] - g_iStuckDistance;
	}
	
	if (Tries[client] == 5)
	{
		NewVecPosition[2] = LastVecPosition[client][2] + g_iStuckDistance;
	}
	
	if (Tries[client]!=5) Tries[client]++;
	else Tries[client] = 0;
	
	//PrintToChatAll("Tries[Client] = %i , client = %i g_iStuckDistance = %f", Tries[client],client,g_iStuckDistance);
	
	TeleportEntity(client, NewVecPosition, NULL_VECTOR, NULL_VECTOR);
	PrintToChat(client, "You didn't unstuck? Don't worry, try to write \"!stuck\" again!");
	InProgress[client] = false;

	return Plugin_Handled;
}

//Already definied in shavit
/*stock bool IsValidClient(int client, bool bAlive = false) // when bAlive is false = technical checks, when it's true = gameplay checks
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}*/
