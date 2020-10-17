#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

ArrayList g_StrafeData;
float g_LastAngles[MAXPLAYERS + 1][3];
float g_LastMoveDir[MAXPLAYERS + 1];
float g_LastSpeed[MAXPLAYERS + 1];
int g_TickCount[MAXPLAYERS + 1];
int g_IdleCounter[MAXPLAYERS + 1];

enum struct StrafeData
{
    int steamid;
    int tick_count;
    int flags;
    int buttons;
    float sidemove;
    float forwardmove;
    float yaw_delta;
    float pitch_delta;
    float move_dir_delta;
    float speed2d;
}

public void OnPluginStart()
{
    g_StrafeData = new ArrayList(sizeof(StrafeData));
}

public void OnClientConnected( int client )
{
    g_TickCount[client] = 0;
    g_IdleCounter[client] = 0;
    g_LastSpeed[client] = 0.0;
    g_LastMoveDir[client] = 0.0;
    g_LastAngles[client][0] = 0.0;
    g_LastAngles[client][1] = 0.0;
    g_LastAngles[client][2] = 0.0;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    float yaw_delta = NormalizeYaw( angles[1] - g_LastAngles[client][1] );
    float pitch_delta = NormalizePitch( angles[0] - g_LastAngles[client][0] );
    float move_dir = GetMoveDir( client );
    float move_dir_delta = NormalizeYaw( move_dir - g_LastMoveDir[client] );

    /* Dont infest data with huge move_dir_deltas, cause a 0 speed start */
    if( CloseEnough( g_LastMoveDir[client], 0.0 ) &&
        CloseEnough( g_LastSpeed[client], 0.0 ) )
    {
        move_dir_delta = 0.0;
    }

    /* Update last values */
    g_LastMoveDir[client] = move_dir;
    g_LastAngles[client] = angles;
    g_LastSpeed[client] = GetSpeed3d( client );

    if( IsFakeClient( client ) ||
        !IsPlayerAlive( client ) ||
        GetEntityMoveType( client ) != MOVETYPE_WALK )
    {
        g_IdleCounter[client] = 0;
        g_TickCount[client] = 0;
        return Plugin_Continue;
    }

    if( CloseEnough( GetSpeed3d( client ), 0.0 ) &&
        CloseEnough( yaw_delta, 0.0 ) &&
        CloseEnough( pitch_delta, 0.0 ) )
    {
        g_IdleCounter[client]++;

        if( g_IdleCounter[client] >= ( 0.1 / GetTickInterval() ) )
        {
            g_TickCount[client] = 0;
            return Plugin_Continue;
        }
    }
    else
    {
        g_IdleCounter[client] = 0;
    }

    g_TickCount[client]++;

    StrafeData data;
    data.steamid = GetSteamAccountID( client );
    data.tick_count = g_TickCount[client];
    data.flags = GetEntityFlags( client );
    data.buttons = buttons;
    data.sidemove = vel[1];
    data.forwardmove = vel[0];
    data.yaw_delta = yaw_delta;
    data.pitch_delta = pitch_delta;
    data.move_dir_delta = move_dir_delta;
    data.speed2d = GetSpeed2d( client );
    PushStrafeData( data );

    return Plugin_Continue;
}

void PushStrafeData( StrafeData data )
{
    g_StrafeData.PushArray( data );

    if( g_StrafeData.Length > 1000 )
    {
        FlushToFile();
    }
}

void FlushToFile()
{
    File file = OpenFile("strafe_data.csv", "a");

    for( int i = 0; i < g_StrafeData.Length; i++ )
    {
        StrafeData data;
        g_StrafeData.GetArray( i, data );

        file.WriteLine( "%i,%i,%i,%i,%f,%f,%f,%f,%f,%f",
                data.steamid,
                data.tick_count,
                data.flags,
                data.buttons,
                data.sidemove,
                data.forwardmove,
                data.yaw_delta,
                data.pitch_delta,
                data.move_dir_delta,
                data.speed2d );
    }

    g_StrafeData.Clear();

    delete file;
}

stock float NormalizeYaw( float angle )
{
    while( angle <= -180.0 ) angle += 360.0;
    while( angle > 180.0 )   angle -= 360.0;
    return angle;
}

stock float NormalizePitch( float angle )
{
    while( angle <= -90.0 ) angle += 180.0;
    while( angle > 90.0 )   angle -= 180.0;
    return angle;
}

stock float GetVelocity( int client, float vel[3] )
{
    GetEntPropVector( client, Prop_Data, "m_vecVelocity", vel );
}

stock float GetMoveDir( int client )
{
    float vel[3];
    float angle[3];
    GetVelocity( client, vel );
    GetVectorAngles(vel, angle);
    return angle[1];
}

stock float GetSpeed2d( int client )
{
    float vel[3];
    GetVelocity( client, vel );
    return SquareRoot( vel[0]*vel[0] + vel[1]*vel[1] );
}

stock float GetSpeed3d( int client )
{
    float vel[3];
    GetVelocity( client, vel );
    return SquareRoot( vel[0]*vel[0] + vel[1]*vel[1] + vel[2]*vel[2] );
}

stock bool CloseEnough( float a, float b, float epsilon = 0.0001 )
{
    if( FloatAbs( a - b ) <= epsilon )
    {
        return true;
    }

    return false;
}