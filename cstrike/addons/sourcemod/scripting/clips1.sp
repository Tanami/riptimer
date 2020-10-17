#include <sourcemod>
#include <clientprefs>
#include <sdktools>

public Plugin:myinfo = 
{
	name = "ShowClipBrushes", 
	author = "backwards", 
	description = "Allows Players To Type !ShowClips To Toggling Viewing The Maps Clip Brushes.", 
	version = SOURCEMOD_VERSION, 
	url = "http://www.steamcommunity.com/id/mypassword"
}

bool ClipBrushestEnabled[MAXPLAYERS] =  { false, ... };
bool ClipStyle[MAXPLAYERS] =  { false, ... };
Handle g_hClipBrushes, g_hClipBrushesStyle;

enum struct LineData
{
	float Start[3];
	float End[3];
	float MidPoint[3];
	int BrushID;
}

enum struct BrushData
{
	int BrushID;
	ArrayList lines;
}

new beam_mdl_occluded, beam_mdl_open;

ArrayList g_pLineData;

new TotalClipsCount[0] = 0;

public OnPluginStart()
{
	SetupDownloads();
	
	g_hClipBrushes = RegClientCookie("ShowClipBrushes", "Players Enabled Clip-Brushes", CookieAccess_Public);
	g_hClipBrushesStyle = RegClientCookie("ShowClipBrushesStyle", "Players Chosen Clip-Brush Style", CookieAccess_Public);
	
	g_pLineData = new ArrayList(sizeof(LineData));
	
	beam_mdl_open = PrecacheModel("materials/backwards/IgnoreZbeam.vmt", true);
	beam_mdl_occluded = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	
	RegConsoleCmd("sm_clips", ToggleShowClipBrushesCMD, "Toggle displaying clip brushes");
	RegConsoleCmd("sm_showclips", ToggleShowClipBrushesCMD, "Toggle displaying clip brushes");
	RegConsoleCmd("sm_showclip", ToggleShowClipBrushesCMD, "Toggle displaying clip brushes");
	RegConsoleCmd("sm_showclipbrushes", ToggleShowClipBrushesCMD, "Toggle displaying clip brushes");
	RegConsoleCmd("sm_drawclips", ToggleShowClipBrushesCMD, "Toggle displaying clip brushes");
	RegConsoleCmd("sm_drawclip", ToggleShowClipBrushesCMD, "Toggle displaying clip brushes");
	RegConsoleCmd("sm_drawclipbrushes", ToggleShowClipBrushesCMD, "Toggle displaying clip brushes");
	
	RegConsoleCmd("sm_clipstats", TellClipsCount_CMD, "Display clip brush statistics");
	
	RegConsoleCmd("sm_clipstyle", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_clipsstyle", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_changeclips", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_changeclip", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_showclipsstyle", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_changeclipstyle", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_changecliptype", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_drawcliptype", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_showcliptype", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_drawclipstyle", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	RegConsoleCmd("sm_drawclipsstyle", ChangeClipStyle_CMD, "Toggles clip brush drawing styles");
	
	for (new i = 1; i <= MaxClients; i++)
	if (IsValidClient(i))
		OnClientPutInServer(i);
	
	CreateTimer(1.5, Delayed_Startup, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.1, DrawBeams, _, TIMER_REPEAT);
}

public OnMapStart()
{
	SetupDownloads();
	
	beam_mdl_open = PrecacheModel("materials/backwards/IgnoreZbeam.vmt", true);
	beam_mdl_occluded = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	
	g_pLineData.Clear();
	CreateTimer(1.5, Delayed_Startup, _, TIMER_FLAG_NO_MAPCHANGE);
}

public SetupDownloads()
{
	AddFileToDownloadsTable("materials/backwards/IgnoreZbeam.vmt");
	AddFileToDownloadsTable("materials/backwards/IgnoreZbeam.vtf");
}


public Action:Delayed_Startup(Handle:timer, any:unused)
{
	LoadClipBrushes();
	
	return Plugin_Stop;
}

// new Float:flRed, Float:flGreen, Float:flBlue;
new Float:flDegrees = 0.0;

/*HSVtoRGB(&Float:h, Float:s, Float:v, &Float:r, &Float:g, &Float:b)
{
	if(h > 360.0) h -= 360.0
	else if(h < 0.0) h += 360.0
	
	if (s == 0)
	{
		r = v;g = v;b = v;
	}
	else
	{
		new Float:fHue, Float:fValue, Float:fSaturation;
		new i;  new Float:f;  new Float:p,Float:q,Float:t;
		if (h == 360.0) h = 0.0;
		fHue = h / 60.0;
		i = RoundToFloor(fHue);
		f = fHue - i;
		fValue = v;
		fSaturation = s;
		p = fValue * (1.0 - fSaturation);
		q = fValue * (1.0 - (fSaturation * f));
		t = fValue * (1.0 - (fSaturation * (1.0 - f)));
		switch (i)
		{
		   case 0: {r = fValue; g = t; b = p;}
		   case 1: {r = q; g = fValue; b = p; }
		   case 2: {r = p; g = fValue; b = t;}
		   case 3: {r = p; g = q; b = fValue;}
		   case 4: {r = t; g = p; b = fValue;}
		   case 5: {r = fValue; g = p; b = q; }
		}
	}
}*/


GetBeamTypeAddress(client)
{
	if (ClipStyle[client])
		return beam_mdl_open;
	
	return beam_mdl_occluded;
}

new LineDataArraySize = 0;
new beam_draw_mod = -1;
int color_rgb[4] =  { 255, 255, 255, 255 };
float time_till_return = 1.0;
int CallsPerCycle = 0;

void DrawBeamsToPlayer(client)
{
	for (int i = 0; i < CallsPerCycle; i++)
	{
		new index = ((beam_draw_mod * CallsPerCycle) + i);
		
		//Not sure why but its not counting the first 10 without -1 so... 
		if (index < 0)
			return;
		
		if (index > LineDataArraySize - 1)
		{
			beam_draw_mod = -1;
			return;
		}
		
		LineData DataBuff;
		g_pLineData.GetArray(index, DataBuff);
		
		float fStartPos[3];
		float fEndPos[3];
		float fMidPos[3];
		
		fStartPos[0] = DataBuff.Start[0];
		fStartPos[1] = DataBuff.Start[1];
		fStartPos[2] = DataBuff.Start[2];
		
		fEndPos[0] = DataBuff.End[0];
		fEndPos[1] = DataBuff.End[1];
		fEndPos[2] = DataBuff.End[2];
		
		fMidPos[0] = DataBuff.MidPoint[0];
		fMidPos[1] = DataBuff.MidPoint[1];
		fMidPos[2] = DataBuff.MidPoint[2];
		
		TE_SetupBeamPoints(fStartPos, fEndPos, GetBeamTypeAddress(client), 0, 0, 0, time_till_return, 0.8, 0.8, 1, 0.0, color_rgb, 1);
		TE_SendToClient(client, 0.0);
	}
}

public Action:DrawBeams(Handle:timer, any:unused)
{
	if (LineDataArraySize == 0)
		return Plugin_Continue;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!ClipBrushestEnabled[i])
			continue;
		
		if (!IsValidClient(i))
			continue;
		
		DrawBeamsToPlayer(i)
	}
	
	flDegrees += 0.1;
	if (flDegrees >= 720.0)
		flDegrees = 0.0;
	
	/*HSVtoRGB( flDegrees, 1.0, 1.0, flRed, flGreen, flBlue );
	flRed *= 255;
	flGreen *= 255;
	flBlue *= 255;
	color_rgb[0] = RoundToNearest(flRed);
	color_rgb[1] = RoundToNearest(flGreen);
	color_rgb[2] = RoundToNearest(flBlue);*/
	color_rgb[0] = 128;
	color_rgb[1] = 0;
	color_rgb[2] = 128;
	color_rgb[3] = 255;
	
	beam_draw_mod++;
	
	return Plugin_Continue;
}


void MakeBrushesOutOfLineData()
{
	LineDataArraySize = GetArraySize(g_pLineData);
	
	CallsPerCycle = RoundToCeil(float(LineDataArraySize) * 0.1);
	if (CallsPerCycle > 40)
		CallsPerCycle = 40;
	
	time_till_return = (float(LineDataArraySize) / (float(CallsPerCycle))) * 0.1;
	time_till_return += 0.1;
	if (time_till_return < 1.0)
		time_till_return = 1.0;
	
	if (time_till_return > 25.59)
		time_till_return = 25.6;
}

char MapName[512];

public void LoadClipBrushes()
{
	g_pLineData.Clear();
	LineDataArraySize = 0;
	
	GetCurrentMap(MapName, 512);
	
	char FilePath[1024];
	BuildPath(Path_SM, FilePath, PLATFORM_MAX_PATH, "");
	
	Format(FilePath, 1024, "%sdata\\clipbrushes\\%s.ld", FilePath, MapName);
	
	File file = OpenFile(FilePath, "rb");
	
	PrintToServer("looking for file '%s'", FilePath);
	new EmptyLines = 0;
	
	if (!file)
	{
		PrintToServer("No Clip Brush File Found @ '%s'", FilePath);
		return;
	}
	else
	{
		file.Read(TotalClipsCount[0], 1, 4);
	}
	
	while (!file.EndOfFile())
	{
		LineData DataBuff;
		file.Read(view_as<any>(DataBuff), 10, 4);
		
		if (DataBuff.Start[0] == 0.0 && DataBuff.Start[1] == 0.0 && DataBuff.Start[2] == 0.0 && 
			DataBuff.End[0] == 0.0 && DataBuff.End[1] == 0.0 && DataBuff.End[2] == 0.0 && 
			DataBuff.MidPoint[0] == 0.0 && DataBuff.MidPoint[1] == 0.0 && DataBuff.MidPoint[2] == 0.0)
		{
			EmptyLines++;
			continue;
		}
		
		g_pLineData.PushArray(DataBuff);
		
		//PrintToServer("Found Start Line {%f, %f, %f}", DataBuff.Start[0], DataBuff.Start[1], DataBuff.Start[2]);
		//PrintToServer("Found End Line {%f, %f, %f}", DataBuff.End[0], DataBuff.End[1], DataBuff.End[2]);
		//PrintToServer("Found Mid Point of Line {%f, %f, %f}\n", DataBuff.MidPoint[0], DataBuff.MidPoint[1], DataBuff.MidPoint[2]);
	}
	
	CloseHandle(file);
	
	//if(EmptyLines > 0)
	//	PrintToServer("Found %i Empty Line(s) in binary data.. (ignoring)", EmptyLines);
	
	MakeBrushesOutOfLineData();
}

public OnClientCookiesCached(client)
{
	if (IsClientInGame(client) && !IsFakeClient(client))
	{
		char sCookieValue[2];
		GetClientCookie(client, g_hClipBrushes, sCookieValue, sizeof(sCookieValue));
		
		if (StringToInt(sCookieValue) == 0)
			ClipBrushestEnabled[client] = false;
		else
			ClipBrushestEnabled[client] = true;
		
		GetClientCookie(client, g_hClipBrushesStyle, sCookieValue, sizeof(sCookieValue));
		
		if (StringToInt(sCookieValue) == 0)
			ClipStyle[client] = false;
		else
			ClipStyle[client] = true;
	}
}

public OnClientPutInServer(client)
{
	if (!IsFakeClient(client))
	{
		if (AreClientCookiesCached(client))
		{
			char sCookieValue[2];
			GetClientCookie(client, g_hClipBrushes, sCookieValue, sizeof(sCookieValue));
			if (StringToInt(sCookieValue) == 0)
				ClipBrushestEnabled[client] = false;
			else
				ClipBrushestEnabled[client] = true;
			
			GetClientCookie(client, g_hClipBrushesStyle, sCookieValue, sizeof(sCookieValue));
			if (StringToInt(sCookieValue) == 0)
				ClipStyle[client] = false;
			else
				ClipStyle[client] = true;
		}
	}
}

public OnClientDisconnect(client)
{
	char cValue[2];
	if (ClipBrushestEnabled[client])
		Format(cValue, 2, "%i", 1);
	else
		Format(cValue, 2, "%i", 0);
	
	SetClientCookie(client, g_hClipBrushes, cValue);
	ClipBrushestEnabled[client] = false;
	
	if (ClipStyle[client])
		Format(cValue, 2, "%i", 1);
	else
		Format(cValue, 2, "%i", 0);
	
	SetClientCookie(client, g_hClipBrushesStyle, cValue);
	ClipStyle[client] = false;
}

public Action ChangeClipStyle_CMD(int client, int args)
{
	ClipStyle[client] = !ClipStyle[client];
	
	if (GetEngineVersion() == Engine_CSGO)
	{
		if (ClipStyle[client])
			PrintToChat(client, "\x01\x02 \x02Clip Style Changed To\x04Open\x02.");
		else
			PrintToChat(client, "\x01\x02 \x02Clip Style Changed To\x08Occluded\x02.");
	}
	if (GetEngineVersion() == Engine_CSS)
	{
		if (ClipStyle[client])
			SayText2(client, "\x01\x07ffffff[\x0700bbbbClips\x07ffffff] Clip Style: \x07EA8236Open\x07FFFFFF.");
		else
			SayText2(client, "\x01\x07ffffff[\x0700bbbbClips\x07ffffff] Clip Style: \x07A2EA36Occluded\x07FFFFFF.");
	}
}

public Action TellClipsCount_CMD(int client, int args)
{
	if (GetEngineVersion() == Engine_CSGO)
	{
		PrintToChat(client, "\x01\x02 \x02There's \x04%i\x02 Clip Brushes on Map \x08%s\x02 with \x0B%i \x02Edges and \x0C%i \x02Calls Per Cycle.", TotalClipsCount[0], MapName, LineDataArraySize, CallsPerCycle);
	}
	if (GetEngineVersion() == Engine_CSS)
	{
		SayText2(client, "\x01\x07ffffff---\x0700bbbb[Clip Stats]\x07ffffff---\n\x07ffffffClip Amount: \x0700bbbb%i\n\x07ffffffMap: \x0700bbbb%s\n\x07ffffffEdges: \x0700bbbb%i\n\x07ffffffCalls per Cycle: \x0700bbbb%i\n\x07ffffff---\x0700bbbb[Clip Stats]\x07ffffff---", TotalClipsCount[0], MapName, LineDataArraySize, CallsPerCycle);
	}
}

public Action ToggleShowClipBrushesCMD(int client, int args)
{
	ClipBrushestEnabled[client] = !ClipBrushestEnabled[client];
	
	if (GetEngineVersion() == Engine_CSGO)
	{
		if (ClipBrushestEnabled[client])
		{
			PrintToChat(client, "\x01\x02 \x04Draw Clip Brushes has been Enabled.");
			PrintToChat(client, "\x01\x02 \x04You can change \x05Clip Styles\x04 by typing \x03!ClipStyle\x04.");
		}
		else
			PrintToChat(client, "\x01\x02 \x02Draw Clip Brushes has been Disabled.");
	}
	if (GetEngineVersion() == Engine_CSS)
	{
		if (ClipBrushestEnabled[client])
		{
			SayText2(client, "\x01\x07ffffff[\x0700bbbbClips\x07ffffff] Clips: \x0700BB00Enabled\n\x07ffffff- Use \x0700bbbb!clipstats \x07fffffffor data of playerclips in the map\n\x07ffffff- Use \x0700bbbb!clipstyle \x07fffffffor toggling clip brush drawing styles");
		}
		else
		{
			SayText2(client, "\x01\x07ffffff[\x0700bbbbClips\x07ffffff] Clips: \x07bb0000Disabled");
		}
	}
}
	
bool IsValidClient(int client)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || IsClientSourceTV(client) || IsClientReplay(client) || !IsClientConnected(client))
		return false;
	
	return true;
}
	
stock SayText2(to, const String:message[], any:...)
{
	new Handle:hBf = StartMessageOne("SayText2", to, USERMSG_RELIABLE);
	if (!hBf)return;
	decl String:buffer[1024];
	VFormat(buffer, sizeof(buffer), message, 3);
	BfWriteByte(hBf, to);
	BfWriteByte(hBf, true);
	BfWriteString(hBf, buffer);
	EndMessage();
} 