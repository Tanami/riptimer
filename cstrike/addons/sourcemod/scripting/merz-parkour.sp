#include <sourcemod>
#include <sdktools>

#include <shavit>

#include <msharedutil/arrayvec>
#include <msharedutil/ents>

#pragma newdecls required
#pragma semicolon 1


#define TRACEDIF 8.0

#define WALLJUMP_BOOST 500.0

#define BOOST 500.0

#define WALLJUMP_COOLDOWN 0.5

#define BOOST_COOLDOWN 3


float g_flNextWallJump[MAXPLAYERS+1];
float g_flNextBoost[MAXPLAYERS+1];

float g_flLastWallJump[MAXPLAYERS+1];
float g_flLastBoost[MAXPLAYERS+1];

public Plugin myinfo =
{
    author = "MERZBAU, WeebM",
    url = "https://github.com/Tanami/merz-parkour/",
    name = "merz-parkour",
    description = "original by KiD Fearless / influx timer",
    version = "1.0",
};


public void OnClientPutInServer( int client )
{
    g_flNextWallJump[client] = GetEngineTime();
    g_flNextBoost[client] = GetEngineTime();
}

public Action Shavit_OnStart(int client, int track)
{
    g_flNextWallJump[client] = GetEngineTime();
    g_flNextBoost[client] = GetEngineTime();
}

public void SetPlayerClassname(int client, int style) {
    char[] sSpecial = new char[32];
    Shavit_GetStyleStrings(style, sSpecialString, sSpecial, 32);
    
    if(IsPlayerAlive(client) && IsValidClient(client)) {
        if(StrContains(sSpecial, "parkour", false) == -1) {
            SetEntPropString(client, Prop_Data, "m_iClassname", "player", 0);
        }
        else {
            SetEntPropString(client, Prop_Data, "m_iClassname", "parkour", 0);
            // ClientCommand(client, "playgamesound ambient/3dmeagle.wav");
        }
    }
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
    SetPlayerClassname(client, newstyle);
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity)
{
    SetPlayerClassname(client, Shavit_GetBhopStyle(client));
}

public Action Shavit_OnSave(int client)
{
    g_flLastBoost[client] = GetEngineTime() - g_flNextBoost[client] + BOOST_COOLDOWN;
    g_flLastWallJump[client] = GetEngineTime() - g_flNextBoost[client] + WALLJUMP_COOLDOWN;
    return Plugin_Continue;
}

public Action Shavit_OnTeleport (int client)
{
    g_flNextBoost[client] = GetEngineTime() + (BOOST_COOLDOWN - g_flLastBoost[client]);
    g_flNextWallJump[client] = GetEngineTime() + (WALLJUMP_COOLDOWN - g_flLastBoost[client]);
    return Plugin_Continue;
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style)
{
    if ( !IsPlayerAlive( client ) )
    {
        return Plugin_Continue;
    }
    
    char[] sSpecial = new char[32];
    Shavit_GetStyleStrings(style, sSpecialString, sSpecial, 32);

    if(StrContains(sSpecial, "parkour", false) == -1)
    {
        return Plugin_Continue;
    }

    if (( buttons & IN_ATTACK2 && (GetEngineTime() > g_flNextWallJump[client])) && status != Timer_Paused)
    {
        float pos[3];
        float normal[3];
        
        GetClientAbsOrigin( client, pos );
        
        if ( FindWall( pos, normal ) )
        {
            float velocity[3];
            GetEntityVelocity( client, velocity );
            
            for ( int i = 0; i < 3; i++ )
            {
                velocity[i] += normal[i] * WALLJUMP_BOOST;
            }
            
            if ( velocity[2] < WALLJUMP_BOOST )
            {
                velocity[2] = WALLJUMP_BOOST;
            }
            
            
            TeleportEntity( client, NULL_VECTOR, NULL_VECTOR, velocity );
            ClientCommand(client, "playgamesound weapons/flashbang/grenade_hit1.wav");
            
            g_flNextWallJump[client] = GetEngineTime() + WALLJUMP_COOLDOWN;
        }
    }
    
    if (( buttons & IN_ATTACK && (GetEngineTime() > g_flNextBoost[client])) && status != Timer_Paused)
    {
        float vec[3];
        GetClientEyeAngles( client, vec );
        
        GetAngleVectors( vec, vec, NULL_VECTOR, NULL_VECTOR );
        
        
        float velocity[3];
        GetEntityVelocity( client, velocity );
        
        for ( int i = 0; i < 3; i++ )
        {
            velocity[i] += vec[i] * BOOST;
        }
        
        TeleportEntity( client, NULL_VECTOR, NULL_VECTOR, velocity );
        ClientCommand(client, "playgamesound weapons/grenade/tick1.wav");
        
        g_flNextBoost[client] = GetEngineTime() + BOOST_COOLDOWN;
    }
    
    return Plugin_Continue;
}

stock bool FindWall(  const float pos[3], float normal[3] )
{
    float end[3];
    
    
    end = pos; end[0] += TRACEDIF;
    if ( GetTraceNormal( pos, end, normal ) ) return true;
    
    end = pos; end[0] -= TRACEDIF;
    if ( GetTraceNormal( pos, end, normal ) ) return true;
    
    end = pos; end[1] += TRACEDIF;
    if ( GetTraceNormal( pos, end, normal ) ) return true;
    
    end = pos; end[1] -= TRACEDIF;
    if ( GetTraceNormal( pos, end, normal ) ) return true;
    
    end = pos; end[2] += TRACEDIF;
    if ( GetTraceNormal( pos, end, normal ) ) return true;
    
    end = pos; end[2] -= TRACEDIF;
    if ( GetTraceNormal( pos, end, normal ) ) return true;
    
    
    return false;
}

stock bool GetTraceNormal( const float pos[3], const float end[3], float normal[3] )
{
    TR_TraceHullFilter( pos, end, PLYHULL_MINS, PLYHULL_MAXS, MASK_PLAYERSOLID, TrcFltr_AnythingButThoseFilthyScrubs );
    
    if ( TR_GetFraction() != 1.0 )
    {
        //Check that the surface isn't a no-walljump surface
        char surface[64];
        TR_GetSurfaceName(null, surface, sizeof(surface));
        
        if(StrContains(surface, "nowalljump", false) > -1)
            return false;
        
        //Success
        TR_GetPlaneNormal( null, normal );
        return true;
    }
    
    return false;
}

public bool TrcFltr_AnythingButThoseFilthyScrubs( int ent, int mask, any data )
{
    return ( ent == 0 || ent > MaxClients );
}
