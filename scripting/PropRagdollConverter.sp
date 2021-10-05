#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <zombiereloaded>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

#define COLLISION_GROUP_DEBRIS 1
#define COLLISION_GROUP_INTERACTIVE_DEBRIS 3

public Plugin myinfo = 
{
	name = "prop_ragdoll Converter",
	author = "PerfectLaugh && PŠΣ™ SHUFEN",
	description = "",
	version = "",
	url = "https://possession.jp"
};


DynamicDetour g_hEventKilledDetour;
DynamicDetour g_hCreateRagdollEntityDetour;
Handle g_hRemoveDeferred;
Handle g_hCreateServerRagdoll;

#if defined _zr_included
#define VEFFECTS_RAGDOLL_DISSOLVE_EFFECTLESS    -2
#define VEFFECTS_RAGDOLL_DISSOLVE_RANDOM        -1
#define VEFFECTS_RAGDOLL_DISSOLVE_ENERGY        0
#define VEFFECTS_RAGDOLL_DISSOLVE_ELECTRICALH   1
#define VEFFECTS_RAGDOLL_DISSOLVE_ELECTRICALL   2
#define VEFFECTS_RAGDOLL_DISSOLVE_CORE          3

bool g_bPlugin_zombiereloaded = false;
#endif

public void OnPluginStart()
{
	GameData hGameConf = new GameData("PropRagdollConverter.games");
	if (hGameConf == null) {
		SetFailState("No PropRagdollConverter.games gamedata found");
	}

	g_hEventKilledDetour = DynamicDetour.FromConf(hGameConf, "CCSPlayer::Event_Killed");
	if (g_hEventKilledDetour == null) {
		SetFailState("Failed to setup detour for CCSPlayer::Event_Killed");
	}
	if (!g_hEventKilledDetour.Enable(Hook_Pre, OnPlayerEventKilled)) {
		SetFailState("Failed to enable a pre detour CCSPlayer::Event_Killed");
	}
	if (!g_hEventKilledDetour.Enable(Hook_Post, OnPlayerEventKilledPost)) {
		SetFailState("Failed to enable a post detour CCSPlayer::Event_Killed");
	}

	g_hCreateRagdollEntityDetour = DynamicDetour.FromConf(hGameConf, "CCSPlayer::CreateRagdollEntity");
	if (g_hCreateRagdollEntityDetour == null) {
		SetFailState("Failed to setup detour for CCSPlayer::CreateRagdollEntity");
	}
	if (!g_hCreateRagdollEntityDetour.Enable(Hook_Pre, OnPlayerCreateRagdollEntity)) {
		SetFailState("Failed to enable a pre detour CCSPlayer::CreateRagdollEntity");
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CBaseEntity::RemoveDeferred");
	g_hRemoveDeferred = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CreateServerRagdoll");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	g_hCreateServerRagdoll = EndPrepSDKCall();
}

#if defined _zr_included
public void OnAllPluginsLoaded()
{
	g_bPlugin_zombiereloaded = LibraryExists("zombiereloaded");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "zombiereloaded")) {
		g_bPlugin_zombiereloaded = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "zombiereloaded")) {
		g_bPlugin_zombiereloaded = false;
	}
}
#endif

Address g_iDmgInfo = Address_Null;
public MRESReturn OnPlayerEventKilled(int client, DHookParam hParams)
{
	g_iDmgInfo = hParams.Get(1);
	return MRES_Ignored;
}

public MRESReturn OnPlayerEventKilledPost(int client, DHookParam hParams)
{
	g_iDmgInfo = Address_Null;
	return MRES_Ignored;
}

public MRESReturn OnPlayerCreateRagdollEntity(int client)
{
	if (g_iDmgInfo == Address_Null)
		return MRES_Ignored;

	Address centity = GetEntityAddress(client);
	int nForceBone = GetEntProp(client, Prop_Send, "m_nForceBone");
	
	// HACK: Do not let CSGO use LRURetirement which does crash in server.dll (Win32 does not have bUseLRURetirement check)
	int clFlags = GetEntityFlags(client);
	if (clFlags & FL_DISSOLVING == 0) {
		SetEntityFlags(client, clFlags | FL_DISSOLVING);
	}

	float m_vecDamageForce[3];
	m_vecDamageForce[0] = view_as<float>(LoadFromAddress(g_iDmgInfo, NumberType_Int32));
	m_vecDamageForce[1] = view_as<float>(LoadFromAddress(g_iDmgInfo + view_as<Address>(4), NumberType_Int32));
	m_vecDamageForce[2] = view_as<float>(LoadFromAddress(g_iDmgInfo + view_as<Address>(8), NumberType_Int32));

	StoreToAddress(g_iDmgInfo, view_as<int>(0.0), NumberType_Int32);
	StoreToAddress(g_iDmgInfo + view_as<Address>(4), view_as<int>(0.0), NumberType_Int32);
	StoreToAddress(g_iDmgInfo + view_as<Address>(8), view_as<int>(0.0), NumberType_Int32);

	int ragdoll = SDKCall(g_hCreateServerRagdoll, centity, nForceBone, g_iDmgInfo, COLLISION_GROUP_INTERACTIVE_DEBRIS, false);
	SetEntityFlags(client, clFlags);

	StoreToAddress(g_iDmgInfo, view_as<int>(m_vecDamageForce[0]), NumberType_Int32);
	StoreToAddress(g_iDmgInfo + view_as<Address>(4), view_as<int>(m_vecDamageForce[1]), NumberType_Int32);
	StoreToAddress(g_iDmgInfo + view_as<Address>(8), view_as<int>(m_vecDamageForce[2]), NumberType_Int32);

	if (ragdoll > MaxClients && IsValidEntity(ragdoll)) {
		SetEntPropEnt(client, Prop_Send, "m_hRagdoll", ragdoll);
		SDKCall(g_hRemoveDeferred, client);

#if defined _zr_included
		if (g_bPlugin_zombiereloaded) {
			RagdollOnSpawn(ragdoll);
		}
#endif
	}
	return MRES_Supercede;
}

#if defined _zr_included
void RagdollOnSpawn(int ragdoll)
{
	static ConVar zr_veffects_ragdoll_remove, zr_veffects_ragdoll_delay;
	if (zr_veffects_ragdoll_remove == null) {
		zr_veffects_ragdoll_remove = FindConVar("zr_veffects_ragdoll_remove");
	}
	if (zr_veffects_ragdoll_delay == null) {
		zr_veffects_ragdoll_delay = FindConVar("zr_veffects_ragdoll_delay");
	}

	if (!zr_veffects_ragdoll_remove.BoolValue) {
		return;
	}

	float dissolvedelay = zr_veffects_ragdoll_delay.FloatValue;

	// If the delay is 0 or less, then remove right now.
	if (dissolvedelay <= 0.0) {
		RagdollTimer(INVALID_HANDLE, EntIndexToEntRef(ragdoll));
		return;
	}

	// Create a timer to remove/dissolve ragdoll.
	CreateTimer(dissolvedelay, RagdollTimer, EntIndexToEntRef(ragdoll), TIMER_FLAG_NO_MAPCHANGE);
}

public Action RagdollTimer(Handle timer, any ref)
{
	int ragdoll = EntRefToEntIndex(ref);

	// If the ragdoll is already gone, then stop.
	if (!ragdoll || !IsValidEdict(ragdoll)) {
		return;
	}

	// Remove the ragdoll.
	RagdollRemove(ragdoll);
}

void RagdollRemove(int ragdoll)
{
	// Get the dissolve type.
	static ConVar zr_veffects_ragdoll_dissolve;
	if (zr_veffects_ragdoll_dissolve == null) {
		zr_veffects_ragdoll_dissolve = FindConVar("zr_veffects_ragdoll_dissolve");
	}

	int dissolve = zr_veffects_ragdoll_dissolve.IntValue;

	if (dissolve == VEFFECTS_RAGDOLL_DISSOLVE_EFFECTLESS) {
		// Remove entity from world.
		RemoveEntity(ragdoll);
		return;
	}

	// If random, set value to any between "energy" effect and "core" effect.
	if (dissolve == VEFFECTS_RAGDOLL_DISSOLVE_RANDOM) {
		dissolve = GetRandomInt(VEFFECTS_RAGDOLL_DISSOLVE_ENERGY, VEFFECTS_RAGDOLL_DISSOLVE_CORE);
	}

	// Prep the ragdoll for dissolving.
	char targetname[64];
	FormatEx(targetname, sizeof(targetname), "zr_dissolve_%d", ragdoll);
	DispatchKeyValue(ragdoll, "targetname", targetname);

	// Prep the dissolve entity.
	int dissolver = CreateEntityByName("env_entity_dissolver");

	// Set the target to the ragdoll.
	DispatchKeyValue(dissolver, "target", targetname);

	// Set the dissolve type.
	char dissolvetype[16];
	FormatEx(dissolvetype, sizeof(dissolvetype), "%d", dissolve);
	DispatchKeyValue(dissolver, "dissolvetype", dissolvetype);

	// Tell the entity to dissolve the ragdoll.
	AcceptEntityInput(dissolver, "Dissolve");

	// Remove the dissolver.
	RemoveEntity(dissolver);
}
#endif
