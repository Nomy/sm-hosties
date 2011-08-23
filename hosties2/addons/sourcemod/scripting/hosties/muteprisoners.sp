/*
 * SourceMod Hosties Project
 * by: databomb & dataviruset
 *
 * This file is part of the SM Hosties project.
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
 */

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <basecomm>
#define REQUIRE_PLUGIN
#include <hosties>

new Handle:gH_Cvar_MuteStatus = INVALID_HANDLE;
new gShadow_MuteStatus;
new Handle:gH_Cvar_MuteLength = INVALID_HANDLE;
new Float:gShadow_MuteLength;
new Handle:gH_Timer_Unmuter = INVALID_HANDLE;
new Handle:gH_Cvar_MuteImmune = INVALID_HANDLE;
new String:gShadow_MuteImmune[37];
new Handle:gH_Cvar_MuteCT = INVALID_HANDLE;
new bool:gShadow_MuteCT = false;
new gAdmFlags_MuteImmunity = 0;
new bool:g_bBaseCommNatives = false;
new bool:g_bMuted[MAXPLAYERS+1];

MutePrisoners_OnPluginStart()
{
	gH_Cvar_MuteStatus = CreateConVar("sm_hosties_mute", "1", "Setting for muting terrorists automatically: 0 - disable, 1 - terrorists are muted the first 30 seconds of a round, 2 - terrorists are muted when they die, 3 - both", FCVAR_PLUGIN, true, 0.0, true, 3.0);
	gShadow_MuteStatus = 0;
	
	gH_Cvar_MuteLength = CreateConVar("sm_hosties_roundstart_mute", "30.0", "The length of time the Terrorist team is muted for after the round begins", FCVAR_PLUGIN, true, 3.0, true, 90.0);
	gShadow_MuteLength = Float:30.0;
	
	gH_Cvar_MuteImmune = CreateConVar("sm_hosties_mute_immune", "z", "Admin flags which are immune from getting muted: 0 - nobody, 1 - all admins, flag values: abcdefghijklmnopqrst");
	Format(gShadow_MuteImmune, sizeof(gShadow_MuteImmune), "z");
	
	gH_Cvar_MuteCT = CreateConVar("sm_hosties_mute_ct", "0", "Setting for muting counter-terrorists automatically when they die (requires sm_hosties_mute 2 or 3): 0 - disable, 1 - enable", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gShadow_MuteCT = false;
	
	HookConVarChange(gH_Cvar_MuteStatus, MutePrisoners_CvarChanged);
	HookConVarChange(gH_Cvar_MuteLength, MutePrisoners_CvarChanged);
	HookConVarChange(gH_Cvar_MuteImmune, MutePrisoners_CvarChanged);
	HookConVarChange(gH_Cvar_MuteCT, MutePrisoners_CvarChanged);
	
	g_Offset_CollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
	if (g_Offset_CollisionGroup == -1)
	{
		SetFailState("Unable to find offset for collision groups.");
	}
	
	HookEvent("round_start", MutePrisoners_RoundStart);
	HookEvent("round_end", MutePrisoners_RoundEnd);
	HookEvent("player_death", MutePrisoners_PlayerDeath);
}

MutePrisoners_OnClientConnected(client)
{
	g_bMuted[client] = false;
}

MutePrisoners_AllPluginsLoaded()
{
	g_bBaseCommNatives = DoesContainBaseCommNatives();
	
	if (!g_bBaseCommNatives)
	{
		AddCommandListener(Listen_AdminMute, "sm_mute");
		AddCommandListener(Listen_AdminMute, "sm_silence");
	}
}

public Action:Listen_AdminMute(client, const String:command[], args)
{
	if (args < 1)
	{
		return Plugin_Continue;
	}
	
	decl String:arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;
	
	target_count = ProcessTargetString(
		arg,
		client, 
		target_list, 
		MAXPLAYERS, 
		0,
		target_name,
		sizeof(target_name),
		tn_is_ml);
	
	for (new i = 0; i < target_count; i++)
	{
		g_bMuted[target_list[i]] = true;
	}
	
	return Plugin_Continue;
}

MutePrisoners_OnConfigsExecuted()
{
	gShadow_MuteStatus = GetConVarBool(gH_Cvar_MuteStatus);
	gShadow_MuteLength = GetConVarFloat(gH_Cvar_MuteLength);
	
	GetConVarString(gH_Cvar_MuteImmune, gShadow_MuteImmune, sizeof(gShadow_MuteImmune));
	MutePrisoners_CalcImmunity();
}

stock MuteTs()
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if ( (IsClientInGame(i)) && (IsPlayerAlive(i)) ) // if player is in game and alive
		{
			// if player is a terrorist
			if (GetClientTeam(i) == CS_TEAM_T)
			{
				MutePlayer(i);
			}
		}
	}
}

stock UnmuteAlive()
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i)) // if player is in game and alive
		{
			if (g_bBaseCommNatives)
			{
				if (!BaseComm_IsClientMuted(i))
				{
					UnmutePlayer(i);
				}
			}
			else
			{
				if (!g_bMuted[i])
				{
					UnmutePlayer(i);
				}
			}
		}
	}
}

stock bool:DoesContainBaseCommNatives()
{
	// 1.3.9 will have Native_IsClientMuted in basecomm.inc
	if (GetFeatureStatus(FeatureType_Native, "BaseComm_IsClientMuted") == FeatureStatus_Available)
	{
		return true;
	}
	return false;
}

stock UnmuteAll()
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i)) // if player is in game
		{
			if (g_bBaseCommNatives)
			{
				if (!BaseComm_IsClientMuted(i))
				{
					UnmutePlayer(i);
				}
			}
			else
			{
				if (!g_bMuted[i])
				{
					UnmutePlayer(i);
				}
			}
		}
	}
}

void:MutePrisoners_CalcImmunity()
{
	if (StrEqual(gShadow_MuteImmune, "0"))
	{
		gAdmFlags_MuteImmunity = 0;
	}
	else
	{
		if(StrEqual(gShadow_MuteImmune, "1"))
		{
			// include everything but 'a': reservation slot
			Format(gShadow_MuteImmune, sizeof(gShadow_MuteImmune), "bcdefghijklmnopqrst");	
		}
		
		gAdmFlags_MuteImmunity = ReadFlagString(gShadow_MuteImmune);
	}
}

public MutePrisoners_CvarChanged(Handle:cvar, const String:oldValue[], const String:newValue[])
{
	if (cvar == gH_Cvar_MuteStatus)
	{
		gShadow_MuteStatus = StringToInt(newValue);
	}
	else if (cvar == gH_Cvar_MuteLength)
	{
		gShadow_MuteLength = StringToFloat(newValue);
	}
	else if (cvar == gH_Cvar_MuteImmune)
	{
		Format(gShadow_MuteImmune, sizeof(gShadow_MuteImmune), newValue);
		MutePrisoners_CalcImmunity();
	}
	else if (cvar == gH_Cvar_MuteCT)
	{
		gShadow_MuteCT = bool:StringToInt(newValue);
	}
}

public MutePrisoners_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (gShadow_MuteStatus <= 1)
	{
		return;
	}
	
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new team = GetClientTeam(victim);
	switch (team)
	{
		case CS_TEAM_T:
		{
			if (!(GetUserFlagBits(victim) & gAdmFlags_MuteImmunity))
			{
				MutePlayer(victim);
				PrintToChat(victim, CHAT_BANNER, "Now Muted");
			}
		}
		case CS_TEAM_CT:
		{
			if (gShadow_MuteCT && !(GetUserFlagBits(victim) & gAdmFlags_MuteImmunity))
			{			
				MutePlayer(victim);
				PrintToChat(victim, CHAT_BANNER, "Now Muted");
			}
		}
	}
}

public MutePrisoners_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (gShadow_MuteStatus && (gH_Timer_Unmuter != INVALID_HANDLE))
	{
		UnmuteAll();
	}
	
	if (gH_Timer_Unmuter != INVALID_HANDLE)
	{
		CloseHandle(gH_Timer_Unmuter);
		gH_Timer_Unmuter = INVALID_HANDLE;
	}
}

public MutePrisoners_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (gShadow_MuteStatus == 1 || gShadow_MuteStatus == 3)
	{
		if (gAdmFlags_MuteImmunity == 0)
		{
			// Mute All Ts
			MuteTs();
		}
		else
		{
			// Mute non-flagged Ts
			for (new idx = 1; idx <= MaxClients; idx++)
			{
				if (IsClientInGame(idx) && (GetClientTeam(idx) == CS_TEAM_T) && !(GetUserFlagBits(idx) & gAdmFlags_MuteImmunity))
				{
					MutePlayer(idx);
				}
			}
		}
		
		// Unmute Timer
		gH_Timer_Unmuter = CreateTimer(gShadow_MuteLength, Timer_UnmutePrisoners, _, TIMER_FLAG_NO_MAPCHANGE);
		
		PrintToChatAll(CHAT_BANNER, "Ts Muted", RoundToNearest(gShadow_MuteLength));
	}
}

public Action:Timer_UnmutePrisoners(Handle:timer)
{
	UnmuteAlive();
	PrintToChatAll(CHAT_BANNER, "Ts Can Speak Again");
	gH_Timer_Unmuter = INVALID_HANDLE;
}