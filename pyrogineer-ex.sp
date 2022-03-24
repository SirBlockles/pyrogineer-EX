/*
	Pyrogineer EX
	
	An updated version of this plugin: https://forums.alliedmods.net/showthread.php?p=2708112
	which itself is an updated version of the original: https://forums.alliedmods.net/showthread.php?t=282110
	
	What's New:
	* Order of operations is now 1:1 with the wrench - ONLY when hit with full health will a building upgrade/be stocked with ammo
	* Pyro can construction-boost buildings, plugin now requires DHooks (which is included in base SM as of SM 1.11)
	* Healing formula is now 1:1 with the wrench - it will cost the same amount of metal to heal the same amount of health as the engineer would spend
	* a bunch of cvars to customize how much build speed, health, upgrade progress, and ammo is given per swing
	* Pyro puts doubled upgrade metal into buildings during Setup time and in Mannpower mode (same conditions as Engineer)
	* Default cvar values make homewrecker weaker than wrench for what little game balance i can put into a plugin like this
	* metal capacity cvar has been removed; it required TF2items so at that point people might as well just put that attribute onto the homewrecker itself (it does Just Work, surprisingly)
	* by default, neon annihilator does not get wrench properties, but this can be enabled easily by a cvar
	
	CHANGELOG:
	1.0 - initial release
	
	CREDITS:
	aside from the developers of the original plugins, these sources were also used:
	matching teleporter code adapted from psychonic - https://forums.alliedmods.net/showthread.php?t=245901&page=2
*/

#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

ConVar cvarRepairRate,
	cvarUpgradeRate,
	cvarRestockBullets,
	cvarRestockRockets,
	cvarBuildSpeedMult,
	cvarAllowUpgrade,
	cvarAllowLevelUp,
	cvarAllowRepair,
	cvarAllowRestock,
	cvarAllowBuildSpeed,
	cvarAllowNeon;

int teleMatchOffset;
int plyBoostTarget[MAXPLAYERS+1];
Handle plyBoostTimers[MAXPLAYERS+1];

Handle hBuildRate;

#define PLUGIN_VERSION "1.0-rc1"

public Plugin myinfo = {
   name = "Pyrogineer EX",
   author = "muddy, Seacrh_Inkeeper, & Blinx",
   description = "Allows the Homewrecker to interact with buildings in the same fashion as a Wrench",
   version = PLUGIN_VERSION,
   url = ""
}

public void OnPluginStart() {
	CreateConVar("sm_pyrogineer_ex_version", PLUGIN_VERSION, "plugin version. don't touch.", FCVAR_SPONLY | FCVAR_DONTRECORD);
	
	AddNormalSoundHook(view_as<NormalSHook>(Hook_EntitySound));

	cvarRepairRate = CreateConVar("sm_pyrogineer_repair_rate", "45", "Target HP when repairing a building in one swing. Engineer's is 100, but it always ends in a multiple of 3.", FCVAR_NONE, true, 0.0, false);
	cvarUpgradeRate = CreateConVar("sm_pyrogineer_upgrade_rate", "20", "How much upgrade progress a building can recieve in a single hit", FCVAR_NONE, true, 0.0, true, 199.0);
	cvarRestockBullets = CreateConVar("sm_pyrogineer_restock_bullets", "30", "How much bullet ammo is restocked on hit. Engineer's value is 40.", FCVAR_NONE, true, 0.0, true, 200.0);
	cvarRestockRockets = CreateConVar("sm_pyrogineer_restock_rockets", "4", "How many rockets are restocked on hit. Engineer's value is 8.", FCVAR_NONE, true, 0.0, true, 20.0);
	cvarBuildSpeedMult = CreateConVar("sm_pyrogineer_build_speed_mult", "1.0", "Construction rate multiplier - ADDED, not MULTIPLIED, to a building - so 1.0 is 2/3 the rate of Engineer's 1.5 (ie -33% boost compared to wrench)", FCVAR_NONE, true, 0.0);
	cvarAllowUpgrade = CreateConVar("sm_pyrogineer_allow_upgrade", "1", "If disabled, pyros won't be allowed to contribute upgrade progress to a building.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarAllowLevelUp = CreateConVar("sm_pyrogineer_allow_levelup", "1", "If disabled, pyros won't be able to finish leveling up a building - upgrade will cap out at 199/200.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarAllowRepair = CreateConVar("sm_pyrogineer_allow_repair", "1", "If disabled, pyros won't be able to restore HP to buildings. Note: leveling a building will still fully heal it!", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarAllowRestock = CreateConVar("sm_pyrogineer_allow_restock", "2", "2: pyros can restock bullets and rockets, 1: pyros can only restock bullets (no rockets), 0: pyro can't restock any ammo to sentries", FCVAR_NONE, true, 0.0, true, 2.0);
	cvarAllowBuildSpeed = CreateConVar("sm_pyrogineer_allow_buildspeed", "1", "If disabled, pyros won't be allowed to construct buildings faster", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarAllowNeon = CreateConVar("sm_pyrogineer_neon_annihilator", "0", "If enabled, the Neon Annihilator gains these abilties too. Otherwise, just Homewrecker/Maul", FCVAR_NONE, true, 0.0, true, 1.0);
	
	build speed mult
	allow buildspeed
	allow neon
	
	
	// -- BEGIN GAMEDATA OFFSET SHIT --
	
	Handle hConf = LoadGameConfigFile("tf2.pyrogineer-ex");
	if (!hConf) { SetFailState("Failed to load tf2.pyrogineer-ex.txt. is it in your gamedata folder?"); }
	
	char szStartProp[64];
	if (!GameConfGetKeyValue(hConf, "StartProp", szStartProp, sizeof(szStartProp))) { SetFailState("Failed to find StartProp in tf2.pyrogineer-ex.txt. is your gamedata up to date?"); }
	
	int teleOffset = GameConfGetOffset(hConf, "MatchingTeleporterOffset");
	if (teleOffset == -1) { SetFailState("Failed to find MatchingTeleporterOffset in tf2.pyrogineer-ex.txt. is your gamedata up to date?"); }
	
	teleMatchOffset = FindSendPropInfo("CObjectTeleporter", szStartProp);
	if (teleMatchOffset <= 0) { SetFailState("Failed to find teleporter offset in tf2.pyrogineer-ex.txt. is your gamedata up to date?", szStartProp); }
	
	int buildRateOffset = GameConfGetOffset(hConf, "CBaseObject::GetConstructionMultiplier");
	if (buildRateOffset == -1) { SetFailState("Failed to find GetConstructionMultiplier offset in tf2.pyrogineer-ex.txt. is your gamedata up to date?"); }
	
	hBuildRate = DHookCreate(buildRateOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, getBuildRate);
	DHookAddParam(hBuildRate, HookParamType_CBaseEntity, _, DHookPass_ByRef);
	
	teleMatchOffset += teleOffset;
	
	CloseHandle(hConf);
}

public void OnMapStart() {
	PrecacheSound(")weapons/wrench_hit_build_fail.wav");
	
	for(int i = 1; i <= MaxClients; i++) {
		plyBoostTarget[i] = 0;
		if(IsValidHandle(plyBoostTimers[i])) KillTimer(plyBoostTimers[i]);
	}
}

public void OnEntityCreated(int ent, const char[] classname) {
	if(HasEntProp(ent, Prop_Send, "m_iUpgradeMetal")) { DHookEntity(hBuildRate, true, ent); }
}

public Action Hook_EntitySound(int plys[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &ply, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed) {
	if (StrContains(sample, "cbar_hit1", false) != -1 || 
		StrContains(sample, "cbar_hit2", false) != -1 || 
		StrContains(sample, "neon_sign_hit_world_01", false) != -1 || 
		StrContains(sample, "neon_sign_hit_world_02", false) != -1 || 
		StrContains(sample, "neon_sign_hit_world_03", false) != -1 || 
		StrContains(sample, "neon_sign_hit_world_04", false) != -1) { // When a Homewrecker or Neon sign sound goes off
		
		bool didWork = false;
		
		float angles[3];
		float eyepos[3];
		GetClientEyeAngles(ply, angles);
		GetClientEyePosition(ply, eyepos);

		TR_TraceRayFilter(eyepos, angles, MASK_SOLID_BRUSHONLY, RayType_Infinite, TraceRayDontHitSelf, ply);
		int ent = TR_GetEntityIndex();

		if (IsValidEntity(ent) && HasEntProp(ent, Prop_Send, "m_iUpgradeMetal"))
		{
			float EntPos[3];
			float ClientPos[3];
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", EntPos);
			GetEntPropVector(ply, Prop_Send, "m_vecOrigin", ClientPos);

			float Distance = GetVectorDistance(EntPos, ClientPos, false);
			if (Distance < 100.0)
			{
				if (!IsValidEntity(ent)) return Plugin_Continue;
				else
				{
					didWork = BuildingHit(ent, ply);
				}
			}
			
			if(didWork) { return Plugin_Continue; } else if(IsValidTarget(ply)){
				EmitSoundToAll(")weapons/wrench_hit_build_fail.wav", ply, channel);
				return Plugin_Stop;
			}
		}
		
	}
	
	return Plugin_Continue;
}

//use CustomStatusHUD for our metal HUD instead of manual timer shit
public Action OnCustomStatusHUDUpdate(int ply, StringMap entries) {
	if(!IsPlayerAlive(ply) || !IsValidTarget(ply) ) { return Plugin_Continue; }
	int plyMetal = GetEntProp(ply, Prop_Send, "m_iAmmo", _, 3);
	char metalStr[12];
	
	//TODO: stop being lazy and use figure out how to use a valve translation key: TR_Eng_MetalTitle is "Metal", and TF_Metal is "METAL". probably want to use the first one.
	Format(metalStr, sizeof(metalStr), "Metal: %i", plyMetal);
	
	entries.SetString("pyrogineer_metal", metalStr);
	
	return Plugin_Changed;
}

public MRESReturn getBuildRate(int building, Handle hReturn, Handle hParams) {
	if(hReturn != INVALID_HANDLE) {
		float buildRate = DHookGetReturn(hReturn);
		
		for(int i = 1; i <= MaxClients; i++) {
			if(!IsClientConnected(i)) { continue; }
			if(plyBoostTarget[i] == building) { buildRate += GetConVarFloat(cvarBuildSpeedMult); }
		}
		
		DHookSetReturn(hReturn, buildRate);
		
		return MRES_Override;
	}
	return MRES_Override;
}

bool BuildingHit(int building, int ply) {
	if (IsValidTarget(ply)) { //If using Homewrecker, Maul, or Neon Annihilator

		if (FindBuildingOwnerTeam(building) == GetClientTeam(ply)) {
			bool didWork = false;
			
			if(GetEntPropFloat(building, Prop_Send, "m_flPercentageConstructed") < 1.0 && GetConVarBool(cvarAllowBuildSpeed)) { //building is still constructing
				plyBoostTarget[ply] = building;
				if(IsValidHandle(plyBoostTimers[ply])) { KillTimer(plyBoostTimers[ply]); }
				plyBoostTimers[ply] = CreateTimer(1.0, clearBoostTarget, ply);
				
				return true;
			}
			
			//don't attempt performing heals/upgrades/restocks on buildings that are constructing or sapped
			if (GetEntPropFloat(building, Prop_Send, "m_flPercentageConstructed") >= 1.0 && GetEntProp(building, Prop_Send, "m_bHasSapper") == 0) {
				//prevent restocking/upgrading a building while its in the middle of a level-up animation
				//each building has a different m_iState value for when it's going through an upgrade animation - just check those and it's good enough
				//tele = 7, sentry = 3, dispenser = 1
				if(	(HasEntProp(building, Prop_Send, "m_iAmmoShells") && GetEntProp(building, Prop_Send, "m_iState") == 3) ||
					(HasEntProp(building, Prop_Send, "m_iAmmoMetal") && GetEntProp(building, Prop_Send, "m_iState") == 1) ||
					(HasEntProp(building, Prop_Send, "m_flRechargeTime") && GetEntProp(building, Prop_Send, "m_iState") == 7) ) {
					return false;
				}
				
				int plyMetal = GetEntProp(ply, Prop_Send, "m_iAmmo", _, 3);
				if(plyMetal == 0) { return false; }
				
				int buildingHP = GetEntProp(building, Prop_Send, "m_iHealth");
				int buildingHPmax = GetEntProp(building, Prop_Send, "m_iMaxHealth");
				int buildingUpgrade = GetEntProp(building, Prop_Send, "m_iUpgradeMetal");
				int buildingUpgradeMax = GetEntProp(building, Prop_Send, "m_iUpgradeMetalRequired");
				int buildingLevel = GetEntProp(building, Prop_Send, "m_iUpgradeLevel");
				
				// -- HEAL BUILDING --
				//wrench cost calculations and order of operations adapted from Valve's wrench and building code.
				//this should ensure healing and upgrade logic and costs are 1:1 equivalent with engineer's wrenches.
				if (buildingHP < buildingHPmax && GetConVarBool(cvarAllowRepair)) {
					//first: calculate the cost
					int repairTotal = GetConVarInt(cvarRepairRate); //70 by default. 100 is wrench's value. always ends in a multiple of 3 - which is why it caps out at 102 when the target HP is 100.
					int missingHP = buildingHPmax - buildingHP;
					
					if(missingHP < repairTotal) { repairTotal = missingHP; }
					
					int repairCost = RoundToCeil(repairTotal / 3.0); //3:1 metal:HP ratio
					
					//reduce incoming healing to wrangled sentries
					if(HasEntProp(building, Prop_Send, "m_nShieldLevel") && GetEntProp(building, Prop_Send, "m_nShieldLevel") != 0) { repairCost = repairCost / 3; }
					
					if(repairCost > plyMetal) { repairCost = plyMetal; } //if it costs more than we can afford, reduce the cost to what we have and only heal that much
					
					plyMetal -=  repairCost; //deduct the metal. this will never be below 0 due to the sync above
					SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
					
					
					//second: repair the building
					int buildingHPnew = buildingHP + (repairCost * 3);
					if(buildingHPnew > buildingHPmax) { buildingHPnew = buildingHPmax; }
					
					SetVariantInt(buildingHPnew);
					AcceptEntityInput(building, "SetHealth");
					SetEntProp(building, Prop_Send, "m_iMaxHealth", buildingHPmax);
					
					Event healEvent = CreateEvent("building_healed", true);
					
					SetEventInt(healEvent, "building", building);
					SetEventInt(healEvent, "healer", ply);
					SetEventInt(healEvent, "amount", repairCost * 3);
					
					FireEvent(healEvent);
					
					didWork = true;
				}
				
				//heal matching teleporter if applicable.
				//technically in the TF2 code, it uses a different repair cost algorhithm for teleporters and only teleporters, but i'm going to just standardize it by copy-pasting the code above lol
				int buildingMatch = GetMatchingTeleporter(building);
				if(buildingMatch > 0 && GetConVarBool(cvarAllowRepair)) {
					int buildingMatchHP = GetEntProp(buildingMatch, Prop_Send, "m_iHealth");
					int buildingMatchHPMax = GetEntProp(buildingMatch, Prop_Send, "m_iMaxHealth");
					
					int repairTotal = GetConVarInt(cvarRepairRate);
					int missingHP = buildingMatchHPMax - buildingMatchHP;
					
					if(missingHP < repairTotal) { repairTotal = missingHP; }
					
					int repairCost = RoundToCeil(repairTotal / 3.0);
					
					if(repairCost > plyMetal) { repairCost = plyMetal; }
					
					if(!didWork) { plyMetal -= repairCost; } //only deduct metal if we're repairing a teleporter from a full-health other end, for stock wrench parity
					SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
					
					//second: repair the building
					int buildingHPMatchNew = buildingMatchHP + (repairCost * 3);
					if(buildingHPMatchNew > buildingMatchHPMax) { buildingHPMatchNew = buildingMatchHPMax; }
					
					SetVariantInt(buildingHPMatchNew);
					AcceptEntityInput(buildingMatch, "SetHealth");
					SetEntProp(buildingMatch, Prop_Send, "m_iMaxHealth", buildingMatchHPMax);
					
					//only set didWork to true if there was actually health to restore to the other teleporter
					if(missingHP > 0) { didWork = true; }
				}
				
				//in TF2 no other actions are taken if a healing swing was performed.
				//if we've healed something, we're done until the next swing.
				if(didWork) { return didWork; }
				
				// -- UPGRADE BUILDING --
				if(buildingLevel < 3 && GetConVarBool(cvarAllowUpgrade)) {
					int upgradeRate = GetConVarInt(cvarUpgradeRate);
					//double upgrade rate in setup time, and in powerup (mannpower) mode, same as engineer
					if(GameRules_GetProp("m_bPowerupMode") || GameRules_GetProp("m_bInSetup")) { upgradeRate *= 2; }
					
					int buildingUpgradeRemaining = buildingUpgradeMax - buildingUpgrade;
					
					if(upgradeRate > buildingUpgradeRemaining) { upgradeRate = buildingUpgradeRemaining; }
					
					if(upgradeRate > plyMetal) { upgradeRate = plyMetal; }
					
					if(upgradeRate + buildingUpgrade == buildingUpgradeMax) {
						if(GetConVarBool(cvarAllowLevelUp)) { //level up the building
							SetEntProp(building, Prop_Send, "m_iHighestUpgradeLevel", buildingLevel + 1);
							SetEntProp(building, Prop_Send, "m_iUpgradeMetal", 0);
							
							if(buildingMatch > 0) {
								SetEntProp(buildingMatch, Prop_Send, "m_iHighestUpgradeLevel", buildingLevel + 1);
								SetEntProp(buildingMatch, Prop_Send, "m_iUpgradeMetal", 0);
							}
							
							plyMetal = plyMetal - upgradeRate;
							SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
							
							//fire the game event for other plugins and achievements to (hopefully) handle
							Event upgradeEvent = CreateEvent("player_upgradedobject", true);
							
							SetEventInt(upgradeEvent, "userid", GetClientUserId(ply));
							SetEventInt(upgradeEvent, "object", GetEntProp(building, Prop_Send, "m_iObjectType"));
							SetEventInt(upgradeEvent, "index", building);
							SetEventBool(upgradeEvent, "isbuilder", false);
							
							FireEvent(upgradeEvent);
							
							didWork = true;
						} else { //cap upgrade out at 199
							upgradeRate -= 1;
						}
					}
					
					//if we didn't level, just add some upgrade metal
					if(!didWork) {
						SetEntProp(building, Prop_Send, "m_iUpgradeMetal", buildingUpgrade + upgradeRate);
						
						if(buildingMatch > 0) {
							SetEntProp(buildingMatch, Prop_Send, "m_iUpgradeMetal", buildingUpgrade + upgradeRate);
						}
						
						plyMetal = plyMetal - upgradeRate;
						SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
						
						//if we hit a 199 building without allowing levelup then upgraderate will be 0 here
						if(upgradeRate > 0) { didWork = true; }
					}
				}
				
				if(plyMetal == 0) { return didWork; } //no metal left to restock ammo with, so don't even bother checking
				
				// -- RESTOCK SENTRYGUN --
				//engineer restocks 40 bullets at 1 metal each, and 8 rockets at 2 metal each.
				if(HasEntProp(building, Prop_Send, "m_iAmmoShells") && GetConVarInt(cvarAllowRestock) > 0) {
					int buildingAmmo = GetEntProp(building, Prop_Send, "m_iAmmoShells");
					int buildingRockets = GetEntProp(building, Prop_Send, "m_iAmmoRockets");
					
					int bulletsToRestock = GetConVarInt(cvarRestockBullets);
					int rocketsToRestock = GetConVarInt(cvarRestockRockets);
					
					if(bulletsToRestock > plyMetal) { bulletsToRestock = plyMetal; }
					
					int missingAmmo; //lv.1 sentry has 150 ammo, lv.2 has 200. mini is same as lv.1
					if(buildingLevel == 1) { missingAmmo = 150 - buildingAmmo; }
					else { missingAmmo = 200 - buildingAmmo; }

					if(bulletsToRestock > missingAmmo) { bulletsToRestock = missingAmmo; }
					
					if(bulletsToRestock > 0) {
						SetEntProp(building, Prop_Send, "m_iAmmoShells", buildingAmmo+bulletsToRestock);
						plyMetal = plyMetal - bulletsToRestock;
						SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
						didWork = true;
					}
					
					//rockets are set to 20 even at lv.1, so they will only be less than 20 after being fired
					int missingRockets = 20 - buildingRockets;
					if(plyMetal <= 1 || missingRockets == 0) { return didWork; }
					
					if(missingRockets > rocketsToRestock) { missingRockets = rocketsToRestock; }
					
					int rocketCost = missingRockets * 2;
					
					if(rocketCost > plyMetal) { rocketCost = plyMetal; }
					
					rocketCost = RoundToFloor(view_as<float>(rocketCost) / 2.0);
					
					SetEntProp(building, Prop_Send, "m_iAmmoRockets", rocketCost/2);
					plyMetal = plyMetal - rocketCost;
					SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
				}
				
				return didWork;
			}
		}
	}
	return false;
}

public Action clearBoostTarget(Handle timer, int ply) {
	plyBoostTarget[ply] = 0;
	return Plugin_Stop;
}

bool IsValidTarget(int ply) {
	int PlayerMelee = GetPlayerWeaponSlot(ply, TFWeaponSlot_Melee);
	int index = GetEntProp(PlayerMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	if(GetConVarBool(cvarAllowNeon)) { return index == 153 || index == 466 || index == 813 || index == 834; }
	else { return index == 153 || index == 466; }
}

public bool TraceRayDontHitSelf(int entity, int mask, any data) {
	return entity == data ? false : true;
}

int FindBuildingOwnerTeam(int ent) {
	return GetClientTeam(GetEntPropEnt(ent, Prop_Send, "m_hBuilder"));
}

int GetMatchingTeleporter(int teleporter) {
	return GetEntDataEnt2(teleporter, teleMatchOffset);
}