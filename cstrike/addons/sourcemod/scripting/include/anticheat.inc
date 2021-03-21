/*
**
*/
#if defined _INCLUDE_included
 #endinput
#endif
#define _INCLUDE_included

#define AUTHORS "njd4, blank"
#define VERSION "1.0"
#define URL "https://github.com/njd4/anticheat"

// =====[ NATIVES ]=====

/**
 * Logs to the database.
 *
 * @param client		Client index.
 * @param sql			Whether log to database or nah.
 * @param msg			Message.
 * @param any			Formatting
 *
 */
native void Anticheat_LogDetection(int client, bool sql, char[] msg, any...);

// =====

/**
 * Gets debug caller. (One who opened debug menu, after targetting)
 *
 * @param client		Client index.
 * @return				Caller.  
 *
 */
native int Anticheat_GetDebugCaller(int client);

/**
 * Gets debug target.
 *
 * @param client		Client index.
 * @return				Debug target.  
 *
 */
native int Anticheat_GetDebugTarget(int client); // Maybe doesn't need to be used, just use GetDebugCaller() ?

/**
 * Gets debug state. 
 *
 * @param client		Client index.
 * @return				Debug target state.  
 *
 */
native bool Anticheat_GetDebugState(int client, char[] state);

/**
 * Gets bypass state.
 *
 * @param client		Client index.
 * @return				TrueFalse.  
 *
 */
native bool Anticheat_GetBypassState(int client);

// =====

/**
 * Gets angle differnce of client.
 *
 * @param client		Client index.
 * @return				Angle difference[3].  
 *
 */
native float Anticheat_GetAngleDifference(int client, float result[3]);

// =====[ STOCKS ]=====

/**
 * Prints to admins.
 *
 * @param client		Client index.
 * @param any			Formatting.
 */
stock void PrintToAdmins(char[] message, any...)
{
	char buffer[255];
	VFormat(buffer, sizeof(buffer), message, 2);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (CheckCommandAccess(i, "generic_admin", ADMFLAG_GENERIC))
		{
			PrintToChat(i, buffer);
		}
	}
}

/**
 * Checks for valid client.
 *
 * @param client		Client index.
 * @param nobots	
 * return ture/false 
 */
stock bool IsValidClient(int client, bool nobots = true)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
	{
		return false;
	}
	return IsClientInGame(client);
} 

