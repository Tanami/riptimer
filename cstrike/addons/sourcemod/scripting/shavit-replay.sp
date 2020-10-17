/*
 * shavit's Timer - Replay Bot
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <tf2>
#include <tf2_stocks>

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"
#define REPLAY_FORMAT_FINAL "{SHAVITREPLAYFORMAT}{FINAL}"
#define REPLAY_FORMAT_SUBVERSION 0x04
#define CELLS_PER_FRAME 8 // origin[3], angles[2], buttons, flags, movetype
#define FRAMES_PER_WRITE 100 // amounts of frames to write per read/write call

// #define DEBUG

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 262144

enum struct centralbot_cache_t
{
	int iClient;
	int iStyle;
	ReplayStatus iReplayStatus;
	int iTrack;
	int iPlaybackSerial;
}

enum struct replaystrings_t
{
	char sClanTag[MAX_NAME_LENGTH];
	char sNameStyle[MAX_NAME_LENGTH];
	char sCentralName[MAX_NAME_LENGTH];
	char sCentralStyle[MAX_NAME_LENGTH];
	char sCentralStyleTag[MAX_NAME_LENGTH];
	char sUnloaded[MAX_NAME_LENGTH];
}

enum struct framecache_t
{
	int iFrameCount;
	float fTime;
	bool bNewFormat;
	int iReplayVersion;
	char sReplayName[MAX_NAME_LENGTH];
}

enum
{
	iBotShooting_Attack1 = (1 << 0),
	iBotShooting_Attack2 = (1 << 1)
}

// custom cvar settings
char gS_ForcedCvars[][][] =
{
	{ "bot_quota", "{expected_bots}" },
	{ "tf_bot_quota", "{expected_bots}" },
	{ "bot_stop", "1" },
	{ "bot_quota_mode", "normal" },
	{ "tf_bot_quota_mode", "normal" },
	{ "mp_limitteams", "0" },
	{ "bot_join_after_player", "0" },
	{ "tf_bot_join_after_player", "0" },
	{ "bot_chatter", "off" },
	{ "bot_flipout", "1" },
	{ "bot_zombie", "1" },
	{ "mp_autoteambalance", "0" },
	{ "bot_controllable", "0" }
};

// game type
EngineVersion gEV_Type = Engine_Unknown;

// cache
char gS_ReplayFolder[PLATFORM_MAX_PATH];

int gI_ReplayTick[STYLE_LIMIT][TRACKS_SIZE];

// this is the global index for replay bot client to serial client mappings
int gI_ReplayBotClient[STYLE_LIMIT][TRACKS_SIZE];

int trackClient[MAXPLAYERS+1];

ArrayList gA_Frames[STYLE_LIMIT][TRACKS_SIZE];

float gF_StartTick[STYLE_LIMIT][TRACKS_SIZE];

ReplayStatus gRS_ReplayStatus[STYLE_LIMIT][TRACKS_SIZE];

framecache_t gA_FrameCache[STYLE_LIMIT][TRACKS_SIZE];

bool gB_ForciblyStopped = false;
Handle gH_ReplayTimers[STYLE_LIMIT][TRACKS_SIZE];

bool gB_Button[MAXPLAYERS+1];
int gI_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
int gI_Track[MAXPLAYERS+1];
float gF_LastInteraction[MAXPLAYERS+1];

bool gB_Late = false;

// forwards
Handle gH_OnReplayStart = null;
Handle gH_OnReplayEnd = null;

// server specific
float gF_Tickrate = 0.0;
char gS_Map[160];
int gI_ExpectedBots = 0;
centralbot_cache_t gA_CentralCache;

// how do i call this
bool gB_HideNameChange = false;
bool gB_DontCallTimer = false;
bool gB_HijackFrame[MAXPLAYERS+1];
float gF_HijackedAngles[MAXPLAYERS+1][2];

// plugin cvars
ConVar gCV_Enabled = null;
ConVar gCV_ReplayDelay = null;
ConVar gCV_TimeLimit = null;
ConVar gCV_DefaultTeam = null;
ConVar gCV_CentralBot = null;
ConVar gCV_BotShooting = null;
ConVar gCV_BotPlusUse = null;
ConVar gCV_BotWeapon = null;
ConVar gCV_PlaybackCanStop = null;
ConVar gCV_PlaybackCooldown = null;

// timer settings
int gI_Styles = 0;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];
stylesettings_t gA_StyleSettings[STYLE_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

// replay settings
replaystrings_t gS_ReplayStrings;

// admin menu
TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

// database related things
Database gH_SQL = null;
char gS_MySQLPrefix[32];

public Plugin myinfo =
{
	name = "[shavit] Replay Bot",
	author = "shavit",
	description = "A replay bot for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_DeleteReplay", Native_DeleteReplay);
	CreateNative("Shavit_GetReplayBotCurrentFrame", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetClientFrameCount", Native_GetClientFrameCount);
	CreateNative("Shavit_GetReplayBotFirstFrame", Native_GetReplayBotFirstFrame);
	CreateNative("Shavit_GetReplayBotIndex", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetReplayBotStyle", Native_GetReplayBotStyle);
	CreateNative("Shavit_GetReplayBotTrack", Native_GetReplayBotTrack);
	CreateNative("Shavit_GetReplayBotType", Native_GetReplayBotType);
	CreateNative("Shavit_GetReplayData", Native_GetReplayData);
	CreateNative("Shavit_GetReplayFrames", Native_GetReplayFrames);
	CreateNative("Shavit_GetReplayFrameCount", Native_GetReplayFrameCount);
	CreateNative("Shavit_GetReplayLength", Native_GetReplayLength);
	CreateNative("Shavit_GetReplayName", Native_GetReplayName);
	CreateNative("Shavit_GetReplayTime", Native_GetReplayTime);
	CreateNative("Shavit_HijackAngles", Native_HijackAngles);
	CreateNative("Shavit_IsReplayDataLoaded", Native_IsReplayDataLoaded);
	CreateNative("Shavit_ReloadReplay", Native_ReloadReplay);
	CreateNative("Shavit_ReloadReplays", Native_ReloadReplays);
	CreateNative("Shavit_Replay_DeleteMap", Native_Replay_DeleteMap);
	CreateNative("Shavit_SetReplayData", Native_SetReplayData);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-replay");

	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if(!LibraryExists("shavit-wr"))
	{
		SetFailState("shavit-wr is required for the plugin to work.");
	}
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-replay.phrases");

	// forwards
	gH_OnReplayStart = CreateGlobalForward("Shavit_OnReplayStart", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplayEnd = CreateGlobalForward("Shavit_OnReplayEnd", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	// game specific
	gEV_Type = GetEngineVersion();
	gF_Tickrate = (1.0 / GetTickInterval());

	FindConVar((gEV_Type != Engine_TF2)? "bot_quota":"tf_bot_quota").Flags &= ~FCVAR_NOTIFY;
	FindConVar("bot_stop").Flags &= ~FCVAR_CHEAT;

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		ConVar hCvar = FindConVar(gS_ForcedCvars[i][0]);

		if(hCvar != null)
		{
			if(StrEqual(gS_ForcedCvars[i][1], "{expected_bots}"))
			{
				UpdateBotQuota(0);
			}	

			else
			{
				hCvar.SetString(gS_ForcedCvars[i][1]);
			}

			hCvar.AddChangeHook(OnForcedConVarChanged);
		}
	}

	// late load
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && !IsFakeClient(i))
		{
			OnClientPutInServer(i);
		}
	}

	// plugin convars
	gCV_Enabled = CreateConVar("shavit_replay_enabled", "1", "Enable replay bot functionality?", 0, true, 0.0, true, 1.0);
	gCV_ReplayDelay = CreateConVar("shavit_replay_delay", "5.0", "Time to wait before restarting the replay after it finishes playing.", 0, true, 0.0, true, 10.0);
	gCV_TimeLimit = CreateConVar("shavit_replay_timelimit", "7200.0", "Maximum amount of time (in seconds) to allow saving to disk.\nDefault is 7200 (2 hours)\n0 - Disabled");
	gCV_DefaultTeam = CreateConVar("shavit_replay_defaultteam", "3", "Default team to make the bots join, if possible.\n2 - Terrorists/RED\n3 - Counter Terrorists/BLU", 0, true, 2.0, true, 3.0);
	gCV_CentralBot = CreateConVar("shavit_replay_centralbot", "1", "Have one central bot instead of one bot per replay.\nTriggered with !replay.\nRestart the map for changes to take effect.\nThe disabled setting is not supported - use at your own risk.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_BotShooting = CreateConVar("shavit_replay_botshooting", "3", "Attacking buttons to allow for bots.\n0 - none\n1 - +attack\n2 - +attack2\n3 - both", 0, true, 0.0, true, 3.0);
	gCV_BotPlusUse = CreateConVar("shavit_replay_botplususe", "1", "Allow bots to use +use?", 0, true, 0.0, true, 1.0);
	gCV_BotWeapon = CreateConVar("shavit_replay_botweapon", "", "Choose which weapon the bot will hold.\nLeave empty to use the default.\nSet to \"none\" to have none.\nExample: weapon_usp");
	gCV_PlaybackCanStop = CreateConVar("shavit_replay_pbcanstop", "1", "Allow players to stop playback if they requested it?", 0, true, 0.0, true, 1.0);
	gCV_PlaybackCooldown = CreateConVar("shavit_replay_pbcooldown", "10.0", "Cooldown in seconds to apply for players between each playback they request/stop.\nDoes not apply to RCON admins.", 0, true, 0.0);

	gCV_CentralBot.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// admin menu
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(gH_AdminMenu);
	}

	// hooks
	HookEvent("player_spawn", Player_Event, EventHookMode_Pre);
	HookEvent("player_death", Player_Event, EventHookMode_Pre);
	HookEvent("player_connect", BotEvents, EventHookMode_Pre);
	HookEvent("player_disconnect", BotEvents, EventHookMode_Pre);
	HookEventEx("player_connect_client", BotEvents, EventHookMode_Pre);

	// name change suppression
	HookUserMessage(GetUserMessageId("SayText2"), Hook_SayText2, true);

	// commands
	RegAdminCmd("sm_deletereplay", Command_DeleteReplay, ADMFLAG_RCON, "Open replay deletion menu.");
	RegConsoleCmd("sm_replay", Command_Replay, "Opens the central bot menu. For admins: 'sm_replay stop' to stop the playback.");

	// database
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = GetTimerDatabaseHandle();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	OnMapStart();
}

void UpdateBotQuota(int quota)
{
	ConVar hCvar = FindConVar("bot_quota");

	if(hCvar == null)
	{
		hCvar = FindConVar("tf_bot_quota");
	}

	hCvar.IntValue = gI_ExpectedBots = quota;
}

public void OnForcedConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char sName[32];
	convar.GetName(sName, 32);

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		if(StrEqual(sName, gS_ForcedCvars[i][0]))
		{
			if(StrEqual(gS_ForcedCvars[i][1], "{expected_bots}"))
			{
				convar.IntValue = gI_ExpectedBots;
			}

			else if(!StrEqual(newValue, gS_ForcedCvars[i][1]))
			{
				convar.SetString(gS_ForcedCvars[i][1]);
			}

			break;
		}
	}
}

public void OnAdminMenuCreated(Handle topmenu)
{
	if(gH_AdminMenu == null || (topmenu == gH_AdminMenu && gH_TimerCommands != INVALID_TOPMENUOBJECT))
	{
		return;
	}

	gH_TimerCommands = gH_AdminMenu.AddCategory("Timer Commands", CategoryHandler, "shavit_admin", ADMFLAG_RCON);
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		FormatEx(buffer, maxlength, "%T:", "TimerCommands", param);
	}

	else if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "TimerCommands", param);
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	if((gH_AdminMenu = GetAdminTopMenu()) != null)
	{
		if(gH_TimerCommands == INVALID_TOPMENUOBJECT)
		{
			gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands");

			if(gH_TimerCommands == INVALID_TOPMENUOBJECT)
			{
				OnAdminMenuCreated(topmenu);
			}
		}
		
		gH_AdminMenu.AddItem("sm_deletereplay", AdminMenu_DeleteReplay, gH_TimerCommands, "sm_deletereplay", ADMFLAG_RCON);
	}
}

public void AdminMenu_DeleteReplay(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteReplayAdminMenu");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteReplay(param, 0);
	}
}

void UnloadReplay(int style, int track)
{
	if(gCV_CentralBot.BoolValue && gA_CentralCache.iStyle == style && gA_CentralCache.iTrack == track)
	{
		StopCentralReplay(0);
	}

	gA_Frames[style][track].Clear();
	gA_FrameCache[style][track].iFrameCount = 0;
	gA_FrameCache[style][track].fTime = 0.0;
	gA_FrameCache[style][track].bNewFormat = true;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");
	gI_ReplayTick[style][track] = -1;

	if(gI_ReplayBotClient[style][track] != 0)
	{
		UpdateReplayInfo(gI_ReplayBotClient[style][track], style, 0.0, track);
	}
}

public int Native_DeleteReplay(Handle handler, int numParams)
{
	char sMap[160];
	GetNativeString(1, sMap, 160);

	int iStyle = GetNativeCell(2);
	int iTrack = GetNativeCell(3);

	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", iTrack);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, iStyle, gS_Map, (iTrack > 0)? sTrack:"");

	if(!FileExists(sPath) || !DeleteFile(sPath))
	{
		return false;
	}

	if(StrEqual(sMap, gS_Map))
	{
		UnloadReplay(iStyle, iTrack);
	}

	return true;
}

public int Native_GetReplayBotFirstFrame(Handle handler, int numParams)
{
	SetNativeCellRef(2, gF_StartTick[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_GetReplayBotCurrentFrame(Handle handler, int numParams)
{
	return gI_ReplayTick[GetNativeCell(1)][GetNativeCell(2)];
}

// TODO: needs TRACK
public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	if(gCV_CentralBot.BoolValue)
	{
		return gA_CentralCache.iClient;
	}

	return gI_ReplayBotClient[GetNativeCell(1)][0];
}

public int Native_IsReplayDataLoaded(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);

	if(gCV_CentralBot.BoolValue)
	{
		return view_as<int>(gA_CentralCache.iClient != -1 && gA_CentralCache.iReplayStatus != Replay_Idle && gA_FrameCache[style][track].iFrameCount > 0);
	}

	return view_as<int>(ReplayEnabled(style) && gA_FrameCache[style][Track_Main].iFrameCount > 0);
}

// i think this shit is only for the central replay bot?
// is any of this shit breaking replay bots??
public int Native_ReloadReplay(Handle handler, int numParams)
{
}
public int Native_ReloadReplays(Handle handler, int numParams)
{
}

public int Native_SetReplayData(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	delete gA_PlayerFrames[client];

	ArrayList frames = view_as<ArrayList>(CloneHandle(GetNativeCell(2)));
	gA_PlayerFrames[client] = frames.Clone();
	delete frames;

	gI_PlayerFrames[client] = gA_PlayerFrames[client].Length;
}

public int Native_GetReplayData(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	ArrayList frames = null;

	if(gA_PlayerFrames[client] != null)
	{
		ArrayList temp = gA_PlayerFrames[client].Clone();
		frames = view_as<ArrayList>(CloneHandle(temp, handler));
		delete temp;
	}

	return view_as<int>(frames);
}

public int Native_GetReplayFrames(Handle handler, int numParams)
{
	int track = GetNativeCell(1);
	int style = GetNativeCell(2);
	ArrayList frames = null;

	if(gA_Frames[style][track] != null)
	{
		ArrayList temp = gA_Frames[style][track].Clone();
		frames = view_as<ArrayList>(CloneHandle(temp, handler));
		delete temp;
	}

	return view_as<int>(frames);
}

public int Native_GetReplayFrameCount(Handle handler, int numParams)
{
	return gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].iFrameCount;
}

public int Native_GetClientFrameCount(Handle handler, int numParams)
{
	return gA_PlayerFrames[GetNativeCell(1)].Length;
}

public int Native_GetReplayLength(Handle handler, int numParams)
{
	return view_as<int>(GetReplayLength(GetNativeCell(1), GetNativeCell(2)));
}

public int Native_GetReplayName(Handle handler, int numParams)
{
	return SetNativeString(3, gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].sReplayName, GetNativeCell(4));
}

public int Native_GetReplayTime(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);

	if(style < 0 || track < 0)
	{
		return view_as<int>(0.0);
	}

	if(gCV_CentralBot.BoolValue)
	{
		if(gA_CentralCache.iReplayStatus == Replay_End)
		{
			return view_as<int>(GetReplayLength(style, track));
		}
	}

	else if(gRS_ReplayStatus[style][track] == Replay_End)
	{
		return view_as<int>(GetReplayLength(style, track));
	}

	return view_as<int>(float(gI_ReplayTick[style][track]) / gF_Tickrate * gA_StyleSettings[style].fTimescale);
}

public int Native_HijackAngles(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	gB_HijackFrame[client] = true;
	gF_HijackedAngles[client][0] = view_as<float>(GetNativeCell(2));
	gF_HijackedAngles[client][1] = view_as<float>(GetNativeCell(3));
}

public int Native_GetReplayBotStyle(Handle handler, int numParams)
{
	return (gCV_CentralBot.BoolValue && gA_CentralCache.iReplayStatus == Replay_Idle)? -1:GetReplayStyle(GetNativeCell(1));
}

public int Native_GetReplayBotTrack(Handle handler, int numParams)
{
	return GetReplayTrack(GetNativeCell(1));
}

public int Native_GetReplayBotType(Handle handler, int numParams)
{
	return view_as<int>((gCV_CentralBot.BoolValue)? Replay_Central:Replay_Legacy);
}

public int Native_Replay_DeleteMap(Handle handler, int numParams)
{
	char sMap[160];
	GetNativeString(1, sMap, 160);

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		for(int j = 0; j < ((gCV_CentralBot.BoolValue)? TRACKS_SIZE:1); j++)
		{
			char sTrack[4];
			FormatEx(sTrack, 4, "_%d", j);

			char sPath[PLATFORM_MAX_PATH];
			FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, i, sMap, (j > 0)? sTrack:"");

			if(FileExists(sPath))
			{
				DeleteFile(sPath);
			}
		}
	}

	if(StrEqual(gS_Map, sMap, false))
	{
		OnMapStart();
	}
}

public Action Cron(Handle Timer)
{
	if(!gCV_Enabled.BoolValue)
	{
		UpdateBotQuota(0);

		return Plugin_Continue;
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			if(!gCV_CentralBot.BoolValue && gI_ReplayBotClient[i][j] != 0)
			{
				// PrintToServer("Cron: %d %d", i, j);
				UpdateReplayInfo(gI_ReplayBotClient[i][j], i, GetReplayLength(i, j), j);
			}
		}
	}

	return Plugin_Continue;
}

bool LoadStyling()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-replay.cfg");

	KeyValues kv = new KeyValues("shavit-replay");
	
	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.GetString("clantag", gS_ReplayStrings.sClanTag, MAX_NAME_LENGTH, "<EMPTY CLANTAG>");
	kv.GetString("namestyle", gS_ReplayStrings.sNameStyle, MAX_NAME_LENGTH, "<EMPTY NAMESTYLE>");
	kv.GetString("centralname", gS_ReplayStrings.sCentralName, MAX_NAME_LENGTH, "<EMPTY CENTRALNAME>");
	kv.GetString("centralstyle", gS_ReplayStrings.sCentralStyle, MAX_NAME_LENGTH, "<EMPTY CENTRALSTYLE>");
	kv.GetString("centralstyletag", gS_ReplayStrings.sCentralStyleTag, MAX_NAME_LENGTH, "<EMPTY CENTRALSTYLETAG>");
	kv.GetString("unloaded", gS_ReplayStrings.sUnloaded, MAX_NAME_LENGTH, "<EMPTY UNLOADED>");

	char sFolder[PLATFORM_MAX_PATH];
	kv.GetString("replayfolder", sFolder, PLATFORM_MAX_PATH, "{SM}/data/replaybot");

	delete kv;

	if(StrContains(sFolder, "{SM}") != -1)
	{
		ReplaceString(sFolder, PLATFORM_MAX_PATH, "{SM}/", "");
		BuildPath(Path_SM, sFolder, PLATFORM_MAX_PATH, "%s", sFolder);
	}
	
	strcopy(gS_ReplayFolder, PLATFORM_MAX_PATH, sFolder);

	return true;
}

public void OnMapStart()
{
	if(!LoadStyling())
	{
		SetFailState("Could not load the replay bots' configuration file. Make sure it exists (addons/sourcemod/configs/shavit-replay.cfg) and follows the proper syntax!");
	}

	// VERY RARE CASE
	// this is required to not cause replays to break if we change map before playback starts, after it is requested
	for(int i = 0; i < STYLE_LIMIT; i++)
	{
		for (int j = 0; j < TRACKS_SIZE; j++)
		{
			gH_ReplayTimers[i][j] = null;
		}
	}

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}

	gA_CentralCache.iClient = -1;
	gA_CentralCache.iStyle = -1;
	gA_CentralCache.iReplayStatus = Replay_Idle;
	gA_CentralCache.iTrack = Track_Main;
	gA_CentralCache.iPlaybackSerial = 0;

	gB_ForciblyStopped = false;

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	char sTempMap[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", gS_Map);

	if(!FileExists(sTempMap))
	{
		if(!FileExists("maps/base.nav"))
		{
			SetFailState("Plugin startup FAILED: \"maps/base.nav\" does not exist.");
		}

		File_Copy("maps/base.nav", sTempMap);

		ForceChangeLevel(gS_Map, ".nav file generate");

		return;
	}

	ServerCommand((gEV_Type != Engine_TF2)? "bot_kick":"tf_bot_kick all");
	UpdateBotQuota(0);

	if(!DirExists(gS_ReplayFolder))
	{
		CreateDirectory(gS_ReplayFolder, 511);
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		// PrintToServer("incr %d", i);
		if(!ReplayEnabled(i))
		{
			continue;
		}

		char sPath[PLATFORM_MAX_PATH];
		FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d", gS_ReplayFolder, i);

		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}

		char uPath[PLATFORM_MAX_PATH];
		FormatEx(uPath, PLATFORM_MAX_PATH, "%s/by-steamid/%d", gS_ReplayFolder, i);

		if(!DirExists(uPath))
		{
			CreateDirectory(uPath, 511);
		}


		bool loaded = false;

		PrintToServer("debug %d for %d", BonusReplayEnabled(i), i);

		if (BonusReplayEnabled(i)) {
			UpdateBotQuota(gI_ExpectedBots + 2);
			for(int j = 0; j < 2; j++)
			{
				gI_ReplayTick[i][j] = -1;
				gF_StartTick[i][j] = -65535.0;
				gRS_ReplayStatus[i][j] = Replay_Idle;

				delete gA_Frames[i][j];
				gA_Frames[i][j] = new ArrayList(CELLS_PER_FRAME);
				gA_FrameCache[i][j].iFrameCount = 0;
				gA_FrameCache[i][j].fTime = 0.0;
				gA_FrameCache[i][j].bNewFormat = true;
				strcopy(gA_FrameCache[i][j].sReplayName, MAX_NAME_LENGTH, "invalid");

				loaded = DefaultLoadReplay(i, j);

				ServerCommand((gEV_Type != Engine_TF2)? "bot_add":"tf_bot_add");

				if(loaded)
				{
					gI_ReplayTick[i][j] = 0;
					gRS_ReplayStatus[i][j] = Replay_Start;

					delete gH_ReplayTimers[i][j];

					DataPack pack = new DataPack();
					gH_ReplayTimers[i][j] = CreateDataTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, pack, TIMER_FLAG_NO_MAPCHANGE);
					pack.WriteCell(i);
					pack.WriteCell(j);
				}
				else {
					PrintToServer("NOT LOADED");
				}
			}
		}
		else {
			UpdateBotQuota(gI_ExpectedBots + 1);
			int j = 0;
			gI_ReplayTick[i][j] = -1;
			gF_StartTick[i][j] = -65535.0;
			gRS_ReplayStatus[i][j] = Replay_Idle;

			delete gA_Frames[i][j];
			gA_Frames[i][j] = new ArrayList(CELLS_PER_FRAME);
			gA_FrameCache[i][j].iFrameCount = 0;
			gA_FrameCache[i][j].fTime = 0.0;
			gA_FrameCache[i][j].bNewFormat = true;
			strcopy(gA_FrameCache[i][j].sReplayName, MAX_NAME_LENGTH, "invalid");

			loaded = DefaultLoadReplay(i, j);

			ServerCommand((gEV_Type != Engine_TF2)? "bot_add":"tf_bot_add");

			if(loaded)
			{
				gI_ReplayTick[i][j] = 0;
				gRS_ReplayStatus[i][j] = Replay_Start;

				delete gH_ReplayTimers[i][j];

				DataPack pack = new DataPack();
				gH_ReplayTimers[i][j] = CreateDataTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, pack, TIMER_FLAG_NO_MAPCHANGE);
				pack.WriteCell(i);
				pack.WriteCell(j);
			}
			else {
				PrintToServer("NOT LOADED");
			}			
		}


	}

	CreateTimer(3.0, Cron, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(i, gA_StyleSettings[i]);
		Shavit_GetStyleStrings(i, sClanTag, gS_StyleStrings[i].sClanTag, sizeof(stylestrings_t::sClanTag));
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));
		Shavit_GetStyleStrings(i, sShortName, gS_StyleStrings[i].sShortName, sizeof(stylestrings_t::sShortName));
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessagePrefix, gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageWarning, gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	Shavit_GetChatStrings(sMessageVariable2, gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	Shavit_GetChatStrings(sMessageStyle, gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));
}

bool DefaultLoadReplay(int style, int track)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"");
	// PrintToServer("DefaultLoadReplay: %s", sPath);
	return LoadReplay(style, track, sPath);
}

bool LoadCurrentReplayFormat(File file, int version, int style, int track)
{
	// PrintToServer("LoadCurrentReplayFormat: %d %d", style, track);
	gA_FrameCache[style][track].iReplayVersion = version;

	// replay file integrity and preframes
	if(gA_FrameCache[style][track].iReplayVersion >= 0x03)
	{
		char sMap[160];
		file.ReadString(sMap, 160);

		int iStyle = 0;
		file.ReadUint8(iStyle);

		int iTrack = 0;
		file.ReadUint8(iTrack);

		if(!StrEqual(sMap, gS_Map, false) || iStyle != style || iTrack != track)
		{
			delete file;
			
			return false;
		}

		// whenever this is implemented
		// file.ReadInt32(gA_FrameCache[style][track].iPreframes);
		file.Seek(4, SEEK_CUR);
	}

	int iTemp = 0;
	file.ReadInt32(iTemp);
	gA_FrameCache[style][track].iFrameCount = iTemp;

	if(gA_Frames[style][track] == null)
	{
		gA_Frames[style][track] = new ArrayList(CELLS_PER_FRAME);
	}

	gA_Frames[style][track].Resize(iTemp);

	file.ReadInt32(iTemp);
	gA_FrameCache[style][track].fTime = view_as<float>(iTemp);

	int iSteamID = 0;

	if(gA_FrameCache[style][track].iReplayVersion >= 0x04)
	{
		file.ReadInt32(iSteamID);
	}
	
	else
	{
		char sAuthID[32];
		file.ReadString(sAuthID, 32);
		ReplaceString(sAuthID, 32, "[U:1:", "");
		ReplaceString(sAuthID, 32, "]", "");
		iSteamID = StringToInt(sAuthID);
	}

	char sQuery[192];
	FormatEx(sQuery, 192, "SELECT name FROM %susers WHERE auth = %d;", gS_MySQLPrefix, iSteamID);

	DataPack hPack = new DataPack();
	hPack.WriteCell(style);
	hPack.WriteCell(track);

	gH_SQL.Query(SQL_GetUserName_Callback, sQuery, hPack, DBPrio_High);

	int cells = CELLS_PER_FRAME;

	if(gA_FrameCache[style][track].iReplayVersion == 0x01)
	{
		cells = 6;
	}

	any[] aReplayData = new any[cells];

	for(int i = 0; i < gA_FrameCache[style][track].iFrameCount; i++)
	{
		if(file.Read(aReplayData, cells, 4) >= 0)
		{
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[0]), 0);
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[1]), 1);
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[2]), 2);
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[3]), 3);
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[4]), 4);
			gA_Frames[style][track].Set(i, view_as<int>(aReplayData[5]), 5);

			if(gA_FrameCache[style][track].iReplayVersion >= 0x02)
			{
				gA_Frames[style][track].Set(i, view_as<int>(aReplayData[6]), 6);
				gA_Frames[style][track].Set(i, view_as<int>(aReplayData[7]), 7);
			}
		}
	}

	gA_FrameCache[style][track].bNewFormat = true; // not wr-based

	delete file;

	return true;
}

bool LoadV2ReplayFormat(File file, int frames, int style, int track)
{
	int iReplaySize = gA_FrameCache[style][track].iFrameCount = frames;
	gA_Frames[style][track].Resize(iReplaySize);

	gA_FrameCache[style][track].fTime = 0.0; // N/A at this version

	any[] aReplayData = new any[6];

	for(int i = 0; i < iReplaySize; i++)
	{
		if(file.Read(aReplayData, 6, 4) >= 0)
		{
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[0]), 0);
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[1]), 1);
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[2]), 2);
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[3]), 3);
			gA_Frames[style][track].Set(i, view_as<float>(aReplayData[4]), 4);
			gA_Frames[style][track].Set(i, view_as<int>(aReplayData[5]), 5);
		}
	}

	gA_FrameCache[style][track].bNewFormat = false;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");

	delete file;

	return true;
}

bool LoadOldReplayFormat(File file, int style, int track)
{
	char sLine[320];
	char sExplodedLine[6][64];

	if(!file.Seek(0, SEEK_SET))
	{
		delete file;

		return false;
	}

	for(int i = 0; !file.EndOfFile(); i++)
	{
		file.ReadLine(sLine, 320);
		int iStrings = ExplodeString(sLine, "|", sExplodedLine, 6, 64);

		gA_Frames[style][track].Resize(i + 1);
		gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[0]), 0);
		gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[1]), 1);
		gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[2]), 2);
		gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[3]), 3);
		gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[4]), 4);
		gA_Frames[style][track].Set(i, (iStrings == 6)? StringToInt(sExplodedLine[5]):0, 5);
	}

	gA_FrameCache[style][track].iFrameCount = gA_Frames[style][track].Length;
	gA_FrameCache[style][track].fTime = 0.0; // N/A at this version
	gA_FrameCache[style][track].bNewFormat = false; // wr-based
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");

	delete file;

	return true;
}

// this is returning false when it should return true?
bool LoadReplay(int style, int track, const char[] path)
{
	// PrintToServer("LoadReplay %d/%d %s", style, track, path);
	if(FileExists(path))
	{
		File fFile = OpenFile(path, "rb");

		char sHeader[64];

		if(!fFile.ReadLine(sHeader, 64))
		{
			delete fFile;

			return false;
		}

		TrimString(sHeader);
		char sExplodedHeader[2][64];
		ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

		if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_FINAL)) // hopefully, the last of them
		{
			return LoadCurrentReplayFormat(fFile, StringToInt(sExplodedHeader[0]), style, track);
		}

		else if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_V2))
		{
			return LoadV2ReplayFormat(fFile, StringToInt(sExplodedHeader[0]), style, track);
		}

		else // old, outdated and slow - only used for ancient replays
		{
			return LoadOldReplayFormat(fFile, style, track);
		}
	}
	else {
		PrintToServer("no replay for %d/%d", style, track);
		return false;
	}
}

bool SaveUserReplay(int style, int track, float time, int steamid, char[] name, int preframes = 0)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/by-steamid/%d/%d_%s%s.replay", gS_ReplayFolder, style, steamid, gS_Map, (track > 0)? sTrack:"");

	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	File fFile = OpenFile(sPath, "wb");
	fFile.WriteLine("%d:" ... REPLAY_FORMAT_FINAL, REPLAY_FORMAT_SUBVERSION);

	fFile.WriteString(gS_Map, true);
	fFile.WriteInt8(style);
	fFile.WriteInt8(track);
	fFile.WriteInt32(preframes);

	int iSize = gA_Frames[style][track].Length;
	fFile.WriteInt32(iSize);
	fFile.WriteInt32(view_as<int>(time));
	fFile.WriteInt32(steamid);

	any aFrameData[CELLS_PER_FRAME];
	any aWriteData[CELLS_PER_FRAME * FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	for(int i = 0; i < iSize; i++)
	{
		gA_Frames[style][track].GetArray(i, aFrameData, CELLS_PER_FRAME);

		for(int j = 0; j < CELLS_PER_FRAME; j++)
		{
			aWriteData[(CELLS_PER_FRAME * iFramesWritten) + j] = aFrameData[j];
		}

		if(++iFramesWritten == FRAMES_PER_WRITE || i == iSize - 1)
		{
			fFile.Write(aWriteData, CELLS_PER_FRAME * iFramesWritten, 4);

			iFramesWritten = 0;
		}
	}

	delete fFile;

	gA_FrameCache[style][track].iFrameCount = iSize;
	gA_FrameCache[style][track].fTime = time;
	gA_FrameCache[style][track].bNewFormat = true;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, name);

	return true;
}

bool SaveReplay(int style, int track, float time, int steamid, char[] name, int preframes = 0)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"");

	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	File fFile = OpenFile(sPath, "wb");
	fFile.WriteLine("%d:" ... REPLAY_FORMAT_FINAL, REPLAY_FORMAT_SUBVERSION);

	fFile.WriteString(gS_Map, true);
	fFile.WriteInt8(style);
	fFile.WriteInt8(track);
	fFile.WriteInt32(preframes);

	int iSize = gA_Frames[style][track].Length;
	fFile.WriteInt32(iSize);
	fFile.WriteInt32(view_as<int>(time));
	fFile.WriteInt32(steamid);

	any aFrameData[CELLS_PER_FRAME];
	any aWriteData[CELLS_PER_FRAME * FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	for(int i = 0; i < iSize; i++)
	{
		gA_Frames[style][track].GetArray(i, aFrameData, CELLS_PER_FRAME);

		for(int j = 0; j < CELLS_PER_FRAME; j++)
		{
			aWriteData[(CELLS_PER_FRAME * iFramesWritten) + j] = aFrameData[j];
		}

		if(++iFramesWritten == FRAMES_PER_WRITE || i == iSize - 1)
		{
			fFile.Write(aWriteData, CELLS_PER_FRAME * iFramesWritten, 4);

			iFramesWritten = 0;
		}
	}

	delete fFile;

	gA_FrameCache[style][track].iFrameCount = iSize;
	gA_FrameCache[style][track].fTime = time;
	gA_FrameCache[style][track].bNewFormat = true;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, name);

	return true;
}

bool DeleteReplay(int style, int track)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"");

	if(!FileExists(sPath) || !DeleteFile(sPath))
	{
		return false;
	}

	UnloadReplay(style, track);

	return true;
}

public void SQL_GetUserName_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int style = data.ReadCell();
	int track = data.ReadCell();
	delete data;

	if(results == null)
	{
		LogError("Timer error! Get user name (replay) failed. Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		results.FetchString(0, gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH);
	}
}

public void OnClientPutInServer(int client)
{
	// PrintToServer("OnClientPutInServer %d", client);
	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		delete gA_PlayerFrames[client];
		gA_PlayerFrames[client] = new ArrayList(CELLS_PER_FRAME);
	}
	else
	{
		for(int i = 0; i < gI_Styles; i++)
		{
			if (ReplayEnabled(i)) {
				if (gI_ReplayBotClient[i][0] == 0) {
					// PrintToServer("%d setting main track for client %d", i, client);
					gI_ReplayBotClient[i][0] = client;
					trackClient[client] = 0;
					UpdateReplayInfo(client, i, -1.0, 0);
					return;
				}
				else if (gI_ReplayBotClient[i][1] == 0 && BonusReplayEnabled(i)) {
					// PrintToServer("%d setting bonus track for client %d", i, client);
					gI_ReplayBotClient[i][1] = client;
					trackClient[client] = 1;
					UpdateReplayInfo(client, i, -1.0, 1);
					return;
				}
				else {
					// PrintToServer("%d both replay bots are defined? %d", i, client);
				}
			}

			// for(int j = 0; j < 2; j++)
			// {
			// 	if(ReplayEnabled(i) && gI_ReplayBotClient[i][j] == 0)
			// 	{
			// 		PrintToServer("adding bot %d %d for client %d", i, j, client);
			// 		gI_ReplayBotClient[i][j] = client;
			// 		// gI_ReplayBotClient[i][1] = client;
			// 		UpdateReplayInfo(client, i, -1.0, j);
			// 		break;
			// 	}
			// }
		}	
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// trigger_once | trigger_multiple.. etc
	// func_door | func_door_rotating
	if(StrContains(classname, "trigger_") != -1 || StrContains(classname, "_door") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, HookTriggers);
		SDKHook(entity, SDKHook_EndTouch, HookTriggers);
		SDKHook(entity, SDKHook_Touch, HookTriggers);
		SDKHook(entity, SDKHook_Use, HookTriggers);
	}
}

public Action HookTriggers(int entity, int other)
{
	if(gCV_Enabled.BoolValue && 1 <= other <= MaxClients && IsFakeClient(other))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void FormatStyle(const char[] source, int style, bool central, float time, int track, char[] dest, int size)
{
	float fWRTime = GetReplayLength(style, track);

	char sTime[16];
	FormatSeconds((time == -1.0)? fWRTime:time, sTime, 16);

	char sName[MAX_NAME_LENGTH];

	GetReplayName(style, track, sName, MAX_NAME_LENGTH);

	// PrintToServer("FormatStyle: %d, %d, %f, %s, %s", style, track, time, size, sName);

	char[] temp = new char[size];
	strcopy(temp, size, source);

	ReplaceString(temp, size, "{map}", gS_Map);

	if(central && gA_CentralCache.iReplayStatus == Replay_Idle)
	{
		ReplaceString(temp, size, "{style}", gS_ReplayStrings.sCentralStyle);
		ReplaceString(temp, size, "{styletag}", gS_ReplayStrings.sCentralStyleTag);
	}

	else
	{
		ReplaceString(temp, size, "{style}", gS_StyleStrings[style].sStyleName);
		ReplaceString(temp, size, "{styletag}", gS_StyleStrings[style].sClanTag);
	}
	
	ReplaceString(temp, size, "{time}", sTime);
	ReplaceString(temp, size, "{player}", sName);

	char sTrack[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);
	ReplaceString(temp, size, "{track}", sTrack);

	strcopy(dest, size, temp);
}

void UpdateReplayInfo(int client, int style, float time, int track)
{
	if(!gCV_Enabled.BoolValue || !IsValidClient(client) || !IsFakeClient(client))
	{
		return;
	}
	// if (style == -1 || track == -1) {
	// 	PrintToServer("invalid style or track for client %d, skipping", client);
	// 	return;
	// }

	SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);

	char sName[MAX_NAME_LENGTH];
	// for some reason track is incrementing to 3?
	// PrintToServer("getting cache size for %d %d %f", track, style, time);
	// PrintToServer("frame cache size: %d", gA_FrameCache[style][track].iFrameCount);
	int iFrameCount = gA_FrameCache[style][track].iFrameCount;
	
	if(iFrameCount > 0)
	{
		FormatStyle(gS_ReplayStrings.sNameStyle, style, false, time, track, sName, MAX_NAME_LENGTH);
	}

	else
	{
		FormatStyle(gS_ReplayStrings.sUnloaded, style, false, time, track, sName, MAX_NAME_LENGTH);
	}

	gB_HideNameChange = true;
	SetClientName(client, sName);

	int iScore = (iFrameCount > 0 || client == gA_CentralCache.iClient)? 2000:-2000;

	if(gEV_Type == Engine_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}

	else if(gEV_Type == Engine_CSS)
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	SetEntProp(client, Prop_Data, "m_iDeaths", 0);

	gB_DontCallTimer = true;

	if(!gCV_CentralBot.BoolValue && iFrameCount == 0)
	{
		if(IsPlayerAlive(client))
		{
			ForcePlayerSuicide(client);
		}
	}

	else
	{
		if(!IsPlayerAlive(client))
		{
			if(gEV_Type == Engine_TF2)
			{
				TF2_RespawnPlayer(client);
			}

			else
			{
				CS_RespawnPlayer(client);
			}
		}

		else
		{
			int iFlags = GetEntityFlags(client);

			if((iFlags & FL_ATCONTROLS) == 0)
			{
				SetEntityFlags(client, (iFlags | FL_ATCONTROLS));
			}
		}

		char sWeapon[32];
		gCV_BotWeapon.GetString(sWeapon, 32);

		if(gEV_Type != Engine_TF2 && strlen(sWeapon) > 0)
		{
			int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

			if(StrEqual(sWeapon, "none"))
			{
				if(iWeapon != -1 && IsValidEntity(iWeapon))
				{
					CS_DropWeapon(client, iWeapon, false);
					AcceptEntityInput(iWeapon, "Kill");
				}
			}

			else
			{
				char sClassname[32];

				if(iWeapon != -1 && IsValidEntity(iWeapon))
				{
					GetEntityClassname(iWeapon, sClassname, 32);

					if(!StrEqual(sWeapon, sClassname))
					{
						CS_DropWeapon(client, iWeapon, false);
						AcceptEntityInput(iWeapon, "Kill");
					}
				}

				else
				{
					GivePlayerItem(client, sWeapon);
				}
			}
		}
	}

	if(GetClientTeam(client) != gCV_DefaultTeam.IntValue)
	{
		if(gEV_Type == Engine_TF2)
		{
			ChangeClientTeam(client, gCV_DefaultTeam.IntValue);
		}

		else
		{
			CS_SwitchTeam(client, gCV_DefaultTeam.IntValue);
		}
	}
}

public void OnClientDisconnect(int client)
{
	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		RequestFrame(DeleteFrames, client);

		return;
	}

	if(gA_CentralCache.iClient == client)
	{
		gA_CentralCache.iClient = -1;

		return;
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < 2; j++)
		{
			if(client == gI_ReplayBotClient[i][j])
			{
				gI_ReplayBotClient[i][j] = 0;

				break;
			}
		}
	}
}

public void DeleteFrames(int client)
{
	delete gA_PlayerFrames[client];
}

public Action Shavit_OnStart(int client)
{
	ClearFrames(client);

	return Plugin_Continue;
}

public void Shavit_OnStop(int client)
{
	ClearFrames(client);
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track)
{
	if(Shavit_IsPracticeMode(client))
	{
		return;
	}

	if(!gCV_Enabled.BoolValue || (gCV_TimeLimit.FloatValue > 0.0 && time > gCV_TimeLimit.FloatValue))
	{
		ClearFrames(client);

		return;
	}

	float pBest = Shavit_GetClientPB(client, style, track);
	if (pBest != 0.0 && time < pBest) {
		Shavit_PrintToChatAll("logging new PB for: %d style: %d new: %f old: %f", client, style, time, pBest);
		int iSteamID = GetSteamAccountID(client);

		char sName[MAX_NAME_LENGTH];
		GetClientName(client, sName, MAX_NAME_LENGTH);
		ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

		SaveUserReplay(style, track, time, iSteamID, sName);
		return;
	}

	float length = GetReplayLength(style, track);

	if(gA_FrameCache[style][track].bNewFormat)
	{
		if(length > 0.0 && time > length)
		{
			return;
		}
	}
	else
	{
		float wrtime = Shavit_GetWorldRecord(style, track);
		if(wrtime != 0.0 && time > wrtime)
		{
			return;
		}
	}

	if(gI_PlayerFrames[client] == 0)
	{
		return;
	}

	delete gA_Frames[style][track];
	gA_Frames[style][track] = gA_PlayerFrames[client].Clone();

	int iSteamID = GetSteamAccountID(client);

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

	SaveReplay(style, track, time, iSteamID, sName);

	if(ReplayEnabled(style))
	{
		if(gCV_CentralBot.BoolValue && gA_CentralCache.iStyle == style && gA_CentralCache.iTrack == track)
		{
			StopCentralReplay(0);
		}

		else if(!gCV_CentralBot.BoolValue && gI_ReplayBotClient[style][track] != 0)
		{
			UpdateReplayInfo(gI_ReplayBotClient[style][track], style, time, track);

			if(gEV_Type == Engine_TF2)
			{
				TF2_RespawnPlayer(gI_ReplayBotClient[style][track]);
			}

			else
			{
				CS_RespawnPlayer(gI_ReplayBotClient[style][track]);
			}

			gRS_ReplayStatus[style][track] = Replay_Running;
			gI_ReplayTick[style][track] = 0;

			float vecPosition[3];
			vecPosition[0] = gA_Frames[style][track].Get(0, 0);
			vecPosition[1] = gA_Frames[style][track].Get(0, 1);
			vecPosition[2] = gA_Frames[style][track].Get(0, 2);

			TeleportEntity(gI_ReplayBotClient[style][track], vecPosition, NULL_VECTOR, NULL_VECTOR);
		}
	}

	ClearFrames(client);
}

void ApplyFlags(int &flags1, int flags2, int flag)
{
	if((flags2 & flag) > 0)
	{
		flags1 |= flag;
	}

	else
	{
		flags2 &= ~flag;
	}
}

// OnPlayerRunCmd instead of Shavit_OnUserCmdPre because bots are also used here.
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	// PrintToServer("OnPlayerRunCmd %d %d %d %f %f", client, buttons, impulse, vecAngles, vecVelocity);

	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(!IsPlayerAlive(client))
	{
		if((buttons & IN_USE) > 0)
		{
			if(!gB_Button[client] && GetSpectatorTarget(client) == gA_CentralCache.iClient)
			{
				OpenReplayMenu(client);
			}

			gB_Button[client] = true;
		}

		else
		{
			gB_Button[client] = false;
		}

		return Plugin_Continue;
	}

	float vecCurrentPosition[3];
	GetClientAbsOrigin(client, vecCurrentPosition);

	int style = GetReplayStyle(client);
	int track = GetReplayTrack(client);

	if(style != -1 && ReplayEnabled(style))
	{
		buttons = 0;

		vel[0] = 0.0;
		vel[1] = 0.0;

		if(gA_Frames[style][track] == null || gA_FrameCache[style][track].iFrameCount <= 0) // if no replay is loaded
		{
			// PrintToServer("no replay available for %d/%d", style, track);
			return Plugin_Changed;
		}

		// replaytick is always -1 if there is no bonus bot?
		// PrintToServer("DEBUG %d (%d) for %d/%d", gI_ReplayTick[style][track], gA_FrameCache[style][track].iFrameCount, style, track);

		if(gI_ReplayTick[style][track] != -1 && gA_FrameCache[style][track].iFrameCount >= 1)
		{
			float vecPosition[3];
			float vecAngles[3];

			if(gRS_ReplayStatus[style][track] != Replay_Running)
			{
				bool bStart = (gRS_ReplayStatus[style][track] == Replay_Start);

				int iFrame = (bStart)? 0:(gA_FrameCache[style][track].iFrameCount - 1);

				vecPosition[0] = gA_Frames[style][track].Get(iFrame, 0);
				vecPosition[1] = gA_Frames[style][track].Get(iFrame, 1);
				vecPosition[2] = gA_Frames[style][track].Get(iFrame, 2);

				vecAngles[0] = gA_Frames[style][track].Get(iFrame, 3);
				vecAngles[1] = gA_Frames[style][track].Get(iFrame, 4);
				
				if(bStart)
				{
					TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));
				}

				else
				{
					float vecVelocity[3];
					MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
					ScaleVector(vecVelocity, gF_Tickrate);
					TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vecVelocity);
				}

				return Plugin_Changed;
			}

			if(++gI_ReplayTick[style][track] >= gA_FrameCache[style][track].iFrameCount - 1)
			{
				gI_ReplayTick[style][track] = 0;
				gRS_ReplayStatus[style][track] = gA_CentralCache.iReplayStatus = Replay_End;

				delete gH_ReplayTimers[style][track];
				DataPack pack = new DataPack();
				gH_ReplayTimers[style][track] = CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_EndReplay, pack, TIMER_FLAG_NO_MAPCHANGE);
				pack.WriteCell(style);
				pack.WriteCell(track);
				gA_CentralCache.iPlaybackSerial = 0;

				return Plugin_Changed;
			}

			if(gI_ReplayTick[style][track] == 1)
			{
				gF_StartTick[style][track] = GetEngineTime();
			}

			vecPosition[0] = gA_Frames[style][track].Get(gI_ReplayTick[style][track], 0);
			vecPosition[1] = gA_Frames[style][track].Get(gI_ReplayTick[style][track], 1);
			vecPosition[2] = gA_Frames[style][track].Get(gI_ReplayTick[style][track], 2);

			vecAngles[0] = gA_Frames[style][track].Get(gI_ReplayTick[style][track], 3);
			vecAngles[1] = gA_Frames[style][track].Get(gI_ReplayTick[style][track], 4);

			buttons = gA_Frames[style][track].Get(gI_ReplayTick[style][track], 5);

			if((gCV_BotShooting.IntValue & iBotShooting_Attack1) == 0)
			{
				buttons &= ~IN_ATTACK;
			}

			if((gCV_BotShooting.IntValue & iBotShooting_Attack2) == 0)
			{
				buttons &= ~IN_ATTACK2;
			}

			if(!gCV_BotPlusUse.BoolValue)
			{
				buttons &= ~IN_USE;
			}

			bool bWalk = false;
			MoveType mt = MOVETYPE_NOCLIP;

			if(gA_FrameCache[style][track].iReplayVersion >= 0x02)
			{
				int iReplayFlags = gA_Frames[style][track].Get(gI_ReplayTick[style][track], 6);
				int iEntityFlags = GetEntityFlags(client);

				ApplyFlags(iEntityFlags, iReplayFlags, FL_ONGROUND);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_PARTIALGROUND);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_INWATER);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_SWIM);

				SetEntityFlags(client, iEntityFlags);
				
				MoveType movetype = gA_Frames[style][track].Get(gI_ReplayTick[style][track], 7);

				if(movetype == MOVETYPE_LADDER)
				{
					mt = movetype;
				}

				else if(movetype == MOVETYPE_WALK && (iReplayFlags & FL_ONGROUND) > 0)
				{
					bWalk = true;
				}
			}

			SetEntityMoveType(client, mt);

			float vecVelocity[3];
			MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
			ScaleVector(vecVelocity, gF_Tickrate);

			if(gI_ReplayTick[style][track] > 1 &&
				// replay is going above 50k speed, just teleport at this point
				(GetVectorLength(vecVelocity) > 50000.0 ||
				// bot is on ground.. if the distance between the previous position is much bigger (1.5x) than the expected according
				// to the bot's velocity, teleport to avoid sync issues
				(bWalk && GetVectorDistance(vecCurrentPosition, vecPosition) > GetVectorLength(vecVelocity) / gF_Tickrate * 1.5)))
			{
				TeleportEntity(client, vecPosition, vecAngles, NULL_VECTOR);

				return Plugin_Changed;
			}

			TeleportEntity(client, NULL_VECTOR, vecAngles, vecVelocity);

			return Plugin_Changed;
		}
	}

	else if(ReplayEnabled(Shavit_GetBhopStyle(client)) && Shavit_GetTimerStatus(client) == Timer_Running)
	{
		if((gI_PlayerFrames[client] / gF_Tickrate) > gCV_TimeLimit.FloatValue)
		{
			// in case of bad timing
			if(gB_HijackFrame[client])
			{
				gB_HijackFrame[client] = false;
			}

			return Plugin_Continue;
		}

		gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + 1);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[0], 0);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[1], 1);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[2], 2);

		if(!gB_HijackFrame[client])
		{
			float vecEyes[3];
			GetClientEyeAngles(client, vecEyes);

			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecEyes[0], 3);
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecEyes[1], 4);
		}

		else
		{
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], gF_HijackedAngles[client][0], 3);
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], gF_HijackedAngles[client][1], 4);

			gB_HijackFrame[client] = false;
		}

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], buttons, 5);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], GetEntityFlags(client), 6);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], GetEntityMoveType(client), 7);

		gI_PlayerFrames[client]++;
	}

	return Plugin_Continue;
}

public Action Timer_EndReplay(Handle Timer, DataPack pack) // what?
{
	pack.Reset();
	int style = pack.ReadCell();
	int track = pack.ReadCell();

	gH_ReplayTimers[style][track] = null;

	int client = GetClientFromSerial(gA_CentralCache.iPlaybackSerial);

	if(client != 0)
	{
		gF_LastInteraction[client] = GetEngineTime();
	}

	gA_CentralCache.iPlaybackSerial = 0;

	if(gCV_CentralBot.BoolValue && gB_ForciblyStopped)
	{
		gB_ForciblyStopped = false;

		return Plugin_Stop;
	}

	gI_ReplayTick[style][track] = 0;

	// TODO
	Call_StartForward(gH_OnReplayEnd);
	Call_PushCell(gI_ReplayBotClient[style][track]);
	Call_Finish();

	if(gI_ReplayBotClient[style][track] != gA_CentralCache.iClient)
	{
		gRS_ReplayStatus[style][track] = Replay_Start;

		delete gH_ReplayTimers[style][track];

		DataPack packn = new DataPack();
		gH_ReplayTimers[style][track] = CreateDataTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, packn, TIMER_FLAG_NO_MAPCHANGE);
		packn.WriteCell(style);
		packn.WriteCell(track);
	}

	else
	{
		gRS_ReplayStatus[style][track] = gA_CentralCache.iReplayStatus = Replay_Idle;
		gI_ReplayBotClient[style][track] = 0;
	}

	return Plugin_Stop;
}

public Action Timer_StartReplay(Handle Timer, DataPack pack)
{
	pack.Reset();
	int style = pack.ReadCell();
	int track = pack.ReadCell();
	// PrintToServer("Timer_StartReplay for %d/%d", style, track);
	gH_ReplayTimers[style][track] = null;

	// TODO
	if(gRS_ReplayStatus[style][track] == Replay_Running || (gCV_CentralBot.BoolValue && gB_ForciblyStopped))
	{
		return Plugin_Stop;
	}

	Call_StartForward(gH_OnReplayStart);
	Call_PushCell(gI_ReplayBotClient[style][track]);
	Call_Finish();

	gRS_ReplayStatus[style][track] = gA_CentralCache.iReplayStatus = Replay_Running;

	return Plugin_Stop;
}

bool ReplayEnabled(any style)
{
	return (!gA_StyleSettings[style].bUnranked && !gA_StyleSettings[style].bNoReplay);
}

bool BonusReplayEnabled(any style)
{
	return (!gA_StyleSettings[style].bUnranked && !gA_StyleSettings[style].bNoBonusReplay);
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client))
	{
		event.BroadcastDisabled = true;

		if(!gB_DontCallTimer)
		{
			CreateTimer(0.10, DelayedUpdate, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}

		gB_DontCallTimer = false;
	}
}

public Action DelayedUpdate(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return Plugin_Stop;
	}

	// PrintToServer("%s: %d (style: %d) (track: %d)", "DelayedUpdate", client, GetReplayStyle(client), GetReplayTrack(client));
	UpdateReplayInfo(client, GetReplayStyle(client), -1.0, GetReplayTrack(client));

	return Plugin_Stop;
}

public Action BotEvents(Event event, const char[] name, bool dontBroadcast)
{
	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(event.GetBool("bot"))
	{
		int client = GetClientOfUserId(event.GetInt("userid"));

		if(1 <= client <= MaxClients && IsClientInGame(client) && IsFakeClient(client) && !IsClientSourceTV(client))
		{
			int iStyle = GetReplayStyle(client);

			if(iStyle != -1)
			{
				UpdateReplayInfo(client, iStyle, -1.0, GetReplayTrack(client));
			}
		}

		event.BroadcastDisabled = true;

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action Hook_SayText2(UserMsg msg_id, any msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!gB_HideNameChange || !gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	// caching usermessage type rather than call it every time
	static UserMessageType um = view_as<UserMessageType>(-1);

	if(um == view_as<UserMessageType>(-1))
	{
		um = GetUserMessageType();
	}

	char sMessage[24];

	if(um == UM_Protobuf)
	{
		Protobuf pbmsg = msg;
		pbmsg.ReadString("msg_name", sMessage, 24);
		delete pbmsg;
	}

	else
	{
		BfRead bfmsg = msg;
		bfmsg.ReadByte();
		bfmsg.ReadByte();
		bfmsg.ReadString(sMessage, 24);
		delete bfmsg;
	}

	if(StrEqual(sMessage, "#Cstrike_Name_Change") || StrEqual(sMessage, "#TF_Name_Change"))
	{
		gB_HideNameChange = false;

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void ClearFrames(int client)
{
	gA_PlayerFrames[client].Clear();
	gI_PlayerFrames[client] = 0;
}

public void Shavit_OnWRDeleted(int style, int id, int track)
{
	float time = Shavit_GetWorldRecord(style, track);

	if(gA_FrameCache[style][track].iFrameCount > 0 && GetReplayLength(style, track) - gF_Tickrate <= time) // -0.1 to fix rounding issues
	{
		DeleteReplay(style, track);
	}
}

public Action Command_DeleteReplay(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(DeleteReplay_Callback);
	menu.SetTitle("%T", "DeleteReplayMenuTitle", client);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(!ReplayEnabled(iStyle))
		{
			continue;
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			if(gA_FrameCache[iStyle][j].iFrameCount == 0)
			{
				continue;
			}

			char sInfo[8];
			FormatEx(sInfo, 8, "%d;%d", iStyle, j);

			float time = GetReplayLength(iStyle, j);

			char sTrack[32];
			GetTrackName(client, j, sTrack, 32);

			char sDisplay[64];

			if(time > 0.0)
			{
				char sTime[32];
				FormatSeconds(time, sTime, 32, false);

				FormatEx(sDisplay, 64, "%s (%s) - %s", gS_StyleStrings[iStyle].sStyleName, sTrack, sTime);
			}

			else
			{
				FormatEx(sDisplay, 64, "%s (%s)", gS_StyleStrings[iStyle].sStyleName, sTrack);
			}

			menu.AddItem(sInfo, sDisplay);
		}
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "ReplaysUnavailable", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int DeleteReplay_Callback(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		char sExploded[2][4];
		ExplodeString(sInfo, ";", sExploded, 2, 4);
		
		int style = StringToInt(sExploded[0]);

		if(style == -1)
		{
			return 0;
		}

		gI_Track[param1] = StringToInt(sExploded[1]);

		Menu submenu = new Menu(DeleteConfirmation_Callback);
		submenu.SetTitle("%T", "ReplayDeletionConfirmation", param1, gS_StyleStrings[style].sStyleName);

		char sMenuItem[64];

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", param1);
			submenu.AddItem("-1", sMenuItem);
		}

		FormatEx(sMenuItem, 64, "%T", "MenuResponseYes", param1);
		submenu.AddItem(sInfo, sMenuItem);

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", param1);
			submenu.AddItem("-1", sMenuItem);
		}

		submenu.ExitButton = true;
		submenu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int DeleteConfirmation_Callback(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[4];
		menu.GetItem(param2, sInfo, 4);
		int style = StringToInt(sInfo);

		if(DeleteReplay(style, gI_Track[param1]))
		{
			char sTrack[32];
			GetTrackName(param1, gI_Track[param1], sTrack, 32);

			LogAction(param1, param1, "Deleted replay for %s on map %s. (Track: %s)", gS_StyleStrings[style].sStyleName, gS_Map, sTrack);

			Shavit_PrintToChat(param1, "%T (%s%s%s)", "ReplayDeleted", param1, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
		}

		else
		{
			Shavit_PrintToChat(param1, "%T", "ReplayDeleteFailure", param1, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Replay(int client, int args)
{
	if(!IsValidClient(client) || !gCV_CentralBot.BoolValue || gA_CentralCache.iClient == -1)
	{
		return Plugin_Handled;
	}

	if(GetClientTeam(client) > 1)
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_ChangeClientTeam(client, TFTeam_Spectator);
		}

		else
		{
			ChangeClientTeam(client, CS_TEAM_SPECTATOR);
		}

		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", gA_CentralCache.iClient);
	}

	else if(GetSpectatorTarget(client) != gA_CentralCache.iClient)
	{
		Shavit_PrintToChat(client, "%T", "CentralReplaySpectator", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(CanStopCentral(client))
	{
		char arg[8];
		GetCmdArg(1, arg, 8);

		if(StrEqual(arg, "stop"))
		{
			StopCentralReplay(client);

			return Plugin_Handled;
		}
	}

	return OpenReplayMenu(client);
}

Action OpenReplayMenu(int client)
{
}

public int MenuHandler_Replay(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		// avoid an exploit
		if(param2 >= 0 && param2 < TRACKS_SIZE)
		{
			OpenReplaySubMenu(param1, param2);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenReplaySubMenu(int client, int track, int item = 0)
{
	gI_Track[client] = track;

	char sTrack[32];
	GetTrackName(client, track, sTrack, 32);

	Menu menu = new Menu(MenuHandler_ReplaySubmenu);
	menu.SetTitle("%T (%s)\n ", "CentralReplayTitle", client, sTrack);

	if(CanStopCentral(client))
	{
		char sDisplay[64];
		FormatEx(sDisplay, 64, "%T", "CentralReplayStop", client);

		menu.AddItem("stop", sDisplay, (gA_CentralCache.iReplayStatus != Replay_Idle)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(!ReplayEnabled(iStyle))
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		float time = GetReplayLength(iStyle, track);

		char sDisplay[64];

		if(time > 0.0)
		{
			char sTime[32];
			FormatSeconds(time, sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - %s", gS_StyleStrings[iStyle].sStyleName, sTime);
		}

		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[iStyle].sStyleName);
		}

		menu.AddItem(sInfo, sDisplay, (gA_FrameCache[iStyle][track].iFrameCount > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "ERROR");
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, 60);
}

public int MenuHandler_ReplaySubmenu(Menu menu, MenuAction action, int param1, int param2)
{
	return 0;
}

bool CanStopCentral(int client)
{
	return (CheckCommandAccess(client, "sm_deletereplay", ADMFLAG_RCON) ||
			(gCV_PlaybackCanStop.BoolValue &&
			GetClientSerial(client) == gA_CentralCache.iPlaybackSerial &&
			GetEngineTime() - gF_LastInteraction[client] > gCV_PlaybackCooldown.FloatValue));
}

void TeleportToStart(int client, int style, int track)
{
	if(gA_FrameCache[style][track].iFrameCount == 0)
	{
		return;
	}

	float vecPosition[3];
	vecPosition[0] = gA_Frames[style][track].Get(0, 0);
	vecPosition[1] = gA_Frames[style][track].Get(0, 1);
	vecPosition[2] = gA_Frames[style][track].Get(0, 2);

	float vecAngles[3];
	vecAngles[0] = gA_Frames[style][track].Get(0, 3);
	vecAngles[1] = gA_Frames[style][track].Get(0, 4);

	TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));
}

void StopCentralReplay(int client)
{
}

int GetReplayStyle(int client)
{
	if(!IsFakeClient(client) || IsClientSourceTV(client))
	{
		return -1;
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < 2; j++)
		{
			// so the problem is that there is no client 4 in the replaybotclient[style][track]
			// PrintToServer("GetReplayStyle: client: %d, value: %d, style: %d, track: %d", client, gI_ReplayBotClient[i][j], i, j);
			// what is the value of this?
			if(gI_ReplayBotClient[i][j] == client)
			{
				return i;
			}
		}
	}

	return -1;
}

// what should this do?
// this should probably have the track for each client set when it initializes
int GetReplayTrack(int client)
{
	if(!IsFakeClient(client) || IsClientSourceTV(client))
	{
		return -1;
	}

	return trackClient[client];

	// for(int i = 0; i < gI_Styles; i++)
	// {
	// 	for(int j = 0; j < 2; j++)
	// 	{
	// 		// PrintToServer("GetReplayTrack: client: %d, value: %d, style: %d, track: %d", client, gI_ReplayBotClient[i][j], i, j);
	// 		// what is the value of this?
	// 		if(gI_ReplayBotClient[i][j] == client)
	// 		{
	// 			return i;
	// 		}
	// 	}
	// }

	// return -1;
}

int GetSpectatorTarget(int client)
{
	int target = -1;

	if(IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(IsValidClient(iTarget, true))
			{
				target = iTarget;
			}
		}
	}

	return target;
}

void GetTrackName(int client, int track, char[] output, int size)
{
	if(track < 0 || track >= TRACKS_SIZE)
	{
		FormatEx(output, size, "%T", "Track_Unknown", client);

		return;
	}

	static char sTrack[16];
	FormatEx(sTrack, 16, "Track_%d", track);
	FormatEx(output, size, "%T", sTrack, client);
}

float GetReplayLength(int style, int track)
{
	// 	"GetReplayLength: %d %f %d %s",
	// 	gA_FrameCache[style][track].iFrameCount,
	// 	gA_FrameCache[style][track].fTime,
	// 	gA_FrameCache[style][track].iReplayVersion,
	// 	gA_FrameCache[style][track].sReplayName
	// );
	// int iFrameCount;
	// float fTime;
	// bool bNewFormat;
	// int iReplayVersion;
	// char sReplayName[MAX_NAME_LENGTH];
	if(gA_FrameCache[style][track].iFrameCount == 0)
	{
		return 0.0;
	}

	if(gA_FrameCache[style][track].bNewFormat)
	{
		return gA_FrameCache[style][track].fTime;
	}

	return Shavit_GetWorldRecord(style, track) * gA_StyleSettings[style].fTimescale;
}

void GetReplayName(int style, int track, char[] buffer, int length)
{
	if(gA_FrameCache[style][track].bNewFormat)
	{
		strcopy(buffer, length, gA_FrameCache[style][track].sReplayName);

		return;
	}

	Shavit_GetWRName(style, buffer, length, track);
}

/*
 * Copies file source to destination
 * Based on code of javalia:
 * http://forums.alliedmods.net/showthread.php?t=159895
 *
 * @param source		Input file
 * @param destination	Output file
 */
bool File_Copy(const char[] source, const char[] destination)
{
	File file_source = OpenFile(source, "rb");

	if(file_source == null)
	{
		return false;
	}

	File file_destination = OpenFile(destination, "wb");

	if(file_destination == null)
	{
		delete file_source;

		return false;
	}

	int buffer[32];
	int cache = 0;

	while(!IsEndOfFile(file_source))
	{
		cache = ReadFile(file_source, buffer, 32, 1);

		file_destination.Write(buffer, cache, 1);
	}

	delete file_source;
	delete file_destination;

	return true;
}
