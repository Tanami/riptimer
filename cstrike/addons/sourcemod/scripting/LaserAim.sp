#include <sourcemod>
#include <sdktools>
//------------------------------------------------------------------------------------------------------------------------------------
public Plugin:myinfo =
{
	name = "Laser Aim",
	author = "flipp[E]r",
	description = "Creates a Laser Beam with Flashbang",
	version = "1.3",
	url = "http://www.sourcemod.net/"
};
//------------------------------------------------------------------------------------------------------------------------------------
#define MAX_CLIENTS		64
new bool:HasLaser[MAX_CLIENTS];
new bool:UsingLaser[MAX_CLIENTS];
new Cooldown[MAX_CLIENTS];
new Float:Distance[MAX_CLIENTS];
new bool:g_lateLoaded;
//------------------------------------------------------------------------------------------------------------------------------------
new g_sprite;
new g_glow;
//------------------------------------------------------------------------------------------------------------------------------------
new Handle:g_CvarRed = INVALID_HANDLE;
new Handle:g_CvarBlue = INVALID_HANDLE;
new Handle:g_CvarGreen = INVALID_HANDLE;
new Handle:g_CvarTrans = INVALID_HANDLE;
new Handle:g_CvarLife = INVALID_HANDLE;
new Handle:g_CvarWidth = INVALID_HANDLE;
new Handle:g_CvarDotWidth = INVALID_HANDLE;
new Handle:g_CvarRand = INVALID_HANDLE;
//------------------------------------------------------------------------------------------------------------------------------------
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max){
	g_lateLoaded = late;

	return APLRes_Success;
}
//------------------------------------------------------------------------------------------------------------------------------------
public OnPluginStart()
{
	RegConsoleCmd("sm_laser",	Command_Laser,	"Toggle laser");

	g_CvarRed = CreateConVar("sm_laser_aim_red", "150", "Amount Of Red In The Beam");
	g_CvarGreen = CreateConVar("sm_laser_aim_green", "0", "Amount Of Green In The Beam");
	g_CvarBlue = CreateConVar("sm_laser_aim_blue", "0", "Amount Of Blue In The Beams");
	g_CvarTrans = CreateConVar("sm_laser_aim_alpha", "100", "Amount Of Transparency In Beam");

	g_CvarLife = CreateConVar("sm_laser_aim_life", "0.1", "Life of the Beam");
	g_CvarWidth = CreateConVar("sm_laser_aim_width", "3", "Width of the Beam");
	g_CvarDotWidth = CreateConVar("sm_laser_aim_dot_width", "0.25", "Width of the Dot");
	g_CvarRand = CreateConVar("sm_laser_aim_rand", "0", "Random Beam Colors");
	
	//late loaded
	if(g_lateLoaded)
	{
		for(new i=1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i))
			{
				HasLaser[i] = true;
				UsingLaser[i] = false;
				Distance[i] = 0.0;
				Cooldown[i] = 0;
			}
		}
	}
}
//------------------------------------------------------------------------------------------------------------------------------------
public OnMapStart()
{
	g_sprite = PrecacheModel("materials/sprites/laser.vmt");
	g_glow = PrecacheModel("sprites/redglow1.vmt");
}
//------------------------------------------------------------------------------------------------------------------------------------
public OnClientConnected(client)
{
	if (client && !IsFakeClient(client))
	{
		HasLaser[client] = true;
		UsingLaser[client] = false;
		Distance[client] = 0.0;
		Cooldown[client] = 0;
	}
}
//------------------------------------------------------------------------------------------------------------------------------------
public Action:Command_Laser(client, args)
{
	if (client && IsClientInGame(client) && !IsFakeClient(client))
	{
		if (HasLaser[client] == true)
		{
			HasLaser[client] = false;
			PrintToChat(client, "Laser: \x04Disabled\x01.");
		}
		else if (HasLaser[client] == false)
		{
			HasLaser[client] = true;
			PrintToChat(client, "Laser: \x04Enabled\x01.");
		}
	}
	return Plugin_Handled;
}
//------------------------------------------------------------------------------------------------------------------------------------
public OnGameFrame()
{
	for (new i=1; i<=MaxClients; i++)
	{
		//new client = GetClientOfUserId(i);
		if(IsClientInGame(i) && IsClientConnected(i) && IsPlayerAlive(i))
		{
			new String:s_playerWeapon[32];
			GetClientWeapon(i, s_playerWeapon, sizeof(s_playerWeapon));

			new iButtons = GetClientButtons(i);
			if((HasLaser[i]) && (GetClientTeam(i) > 1)) {
				if ((iButtons & IN_ATTACK2)) {
					if(StrEqual("weapon_knife", s_playerWeapon)) {
						UsingLaser[i] = true;
						CreateBeam(i);
					}
				} else {
					UsingLaser[i] = false;
				}
				if ((iButtons & IN_USE)) {
					if (UsingLaser[i] == true) {
						if (Cooldown[i] == 0) {
							Cooldown[i] = 70;
							CreateTimer(0.0, Timer_Display, i);
						}
					}
				}
			}
			if ((HasLaser[i]) && (Cooldown[i] > 0)) {
				--Cooldown[i];
			}
		}
	}
}
//------------------------------------------------------------------------------------------------------------------------------------
public Action:CreateBeam(any:client)
{
	new Float:f_playerViewOrigin[3];
	new Float:percentage;
	GetClientAbsOrigin(client, f_playerViewOrigin);
	if(GetClientButtons(client) & IN_DUCK)
		f_playerViewOrigin[2] += 47;
	else
		f_playerViewOrigin[2] += 64;

	new Float:f_playerViewDestination[3];
	GetPlayerEye(client, f_playerViewDestination);

	new Float:distance = GetVectorDistance( f_playerViewOrigin, f_playerViewDestination );

	if(GetClientButtons(client) & IN_DUCK)
		percentage = 0.22 / ( distance / 100 );
	else
		percentage = 0.15 / ( distance / 100 );

	new Float:f_newPlayerViewOrigin[3];
	f_newPlayerViewOrigin[0] = f_playerViewOrigin[0] + ( ( f_playerViewDestination[0] - f_playerViewOrigin[0] ) * percentage );
	f_newPlayerViewOrigin[1] = f_playerViewOrigin[1] + ( ( f_playerViewDestination[1] - f_playerViewOrigin[1] ) * percentage ) - 0.08;
	f_newPlayerViewOrigin[2] = f_playerViewOrigin[2] + ( ( f_playerViewDestination[2] - f_playerViewOrigin[2] ) * percentage );

	new color[4];
	color[0] = GetConVarInt( g_CvarRed ); 
	color[1] = GetConVarInt( g_CvarGreen );
	color[2] = GetConVarInt( g_CvarBlue );
	color[3] = GetConVarInt( g_CvarTrans );
	if (GetConVarInt(g_CvarRand)) {
		color[0] = GetRandomInt(0, 255);
		color[1] = GetRandomInt(0, 255);
		color[2] = GetRandomInt(0, 255);
		color[3] = GetRandomInt(0, 255);
	}
	new Float:life;
	life = GetConVarFloat( g_CvarLife );

	new Float:width;
	width = GetConVarFloat( g_CvarWidth );
	new Float:dotWidth;
	dotWidth = GetConVarFloat( g_CvarDotWidth );

	TE_SetupBeamPoints( f_newPlayerViewOrigin, f_playerViewDestination, g_sprite, 0, 0, 0, life, width, width, 1, 0.0, color, 0 );
	TE_SendToAll();

	TE_SetupGlowSprite( f_playerViewDestination, g_glow, life, dotWidth, color[3] );
	TE_SendToAll();
	
	if (UsingLaser[client] == true) {
		new Float:newdistance = GetVectorDistance( f_playerViewOrigin, f_playerViewDestination );
		Distance[client] = newdistance;
	}
	
	return Plugin_Continue;
}

public Action:Timer_Display(Handle:timer, any:client)
{
	PrintToChat(client, "Distance: %.2f", Distance[client]);
	return Plugin_Stop;
}
//------------------------------------------------------------------------------------------------------------------------------------
bool:GetPlayerEye(client, Float:pos[3])
{
	new Float:vAngles[3], Float:vOrigin[3];
	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);

	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if(TR_DidHit(trace))
	{
		TR_GetEndPosition(pos, trace);
		CloseHandle(trace);
		return true;
	}
	CloseHandle(trace);
	return false;
}
//------------------------------------------------------------------------------------------------------------------------------------
public bool:TraceEntityFilterPlayer(entity, contentsMask)
{
	return entity > GetMaxClients();
}
