[![Build status](https://api.travis-ci.org/shavitush/bhopstats.svg?branch=master)](https://travis-ci.org/shavitush/bhopstats)

# Bunnyhop Statistics
Bunnyhop Statistics is an API made in SourcePawn for developers that provides bhop related statistics.  
Made with hope it will be used for the creation of high quality, open sourced anti-cheats or bhop server utilities for Source Engine games.  
**Note**: Not tested with autobhop plugins *at all*, use at your own risk!

Requirements:
--
* [SourceMod 1.8](https://www.sourcemod.net/downloads.php) or above.

Forwards:
--
```cpp
// Called when the jump key is pressed.
// The variable `onground` will be true if the jump key will do anything for the player when tapped.
forward void Bunnyhop_OnJumpPressed(int client, bool onground);

// Called when the jump key is released.
// The variable `onground` will be true if the jump key will do anything for the player when tapped.
forward void Bunnyhop_OnJumpReleased(int client, bool onground);

// Called when the player touches the ground.
forward void Bunnyhop_OnTouchGround(int client);

// Called when the player leaves the ground, by either jumping or falling from somewhere.
// AKA the HookEventless better version of player_jump.
// The `jumped` variable is true if the ground was left by tapping the jump key, or false if the player fell from somewhere.
// `ladder` is true if the player left the 'ground' from a ladder.
forward void Bunnyhop_OnLeaveGround(int client, bool jumped, bool ladder);
```

Natives: (Methodmap equivalents are also available)
--
```cpp
// Amount of separate +jump inputs since the player left the ground.
// The result will be 0 if the player is on ground.
native int Bunnyhop_GetScrollCount(int client);

// Is the player on ground?
// The result will be true if the player is on a ladder or in water, as jumping will be functional.
native bool Bunnyhop_IsOnGround(int client);

// Is the player holding the jump key?
native bool Bunnyhop_IsHoldingJump(int client);

// Gets a percentage of perfectly timed bunnyhops.
// Resets at player connection or the Bunnyhop_ResetPerfectJumps native for it is called.
// Results are from 0.0 to 100.0.
native float Bunnyhop_GetPerfectJumps(int client);

// Resets the perfect jumps percentage of a player back to 0.0.
native void Bunnyhop_ResetPerfectJumps(int client);
```

Methodmaps usage:
--
```cpp
// Class-like
BunnyhopStats stats = new BunnyhopStats(client);
PrintToServer("Scroll count: %d\nOn ground? %s\nHolding jump key? %s", stats.ScrollCount, (stats.OnGround)? "Yes":"No", (stats.HoldingJump)? "Yes":"No");

// Static
PrintToServer("Scroll count: %d\nOn ground? %s\nHolding jump key? %s", BunnyhopStats.GetScrollCount(client), (BunnyhopStats.IsOnGround(client))? "Yes":"No", (BunnyhopStats.IsHoldingJump(client))? "Yes":"No");
```

Todo:
--
- [ ] Implement average jump key hold time measurement and natives that will save those of the past X jumps into an array.
