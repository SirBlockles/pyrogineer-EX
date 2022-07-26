/*
	Pyrogineer EX
	
	an updated version of this plugin: https://forums.alliedmods.net/showthread.php?p=2708112
	which itself is an updated version of the original: https://forums.alliedmods.net/showthread.php?t=282110
	
	CHANGELOG:
	1.0 - initial release
	1.1 - teleporters now heal at 1:5 metal to HP to match wrench. fixed sentry restocking bug.
	1.2 - if levelup is disabled, building now upgrades to 200/200 instead of 199/200, which lets engineers with 0 metal still upgrade the building. pyros with 0 metal can now also level up a building if it's at 200/200.
	1.3 - when a building takes its first hit after being restored to full HP, it plays the alert sound out loud that is only audible to pyros with the homewrecker equipped, to alert them like engineer.
	
	TODO EVENTUALLY:
	* make HUD use translation key for "Metal" instead of hardcoded english
	
	CREDITS:
	aside from the original plugins linked above, these sources were also used:
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
	cvarAlertSound;

int teleMatchOffset;
int plyBoostTarget[MAXPLAYERS+1];
Handle plyBoostTimers[MAXPLAYERS+1];

Handle hBuildRate;

#define PLUGIN_VERSION "1.2"

public Plugin myinfo = {
   name = "Pyrogineer EX",
   author = "muddy",
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
	cvarAlertSound = CreateConVar("sm_pyrogineer_alertsound", "1", "If enabled, pyros with the homewrecker will hear the building alert sound when it first takes damage from full health", FCVAR_NONE, true, 0.0, true, 1.0);
	
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
	PrecacheSound("misc/hud_warning.wav");
	
	for(int i = 1; i <= MaxClients; i++) {
		plyBoostTarget[i] = 0;
		if(IsValidHandle(plyBoostTimers[i])) KillTimer(plyBoostTimers[i]);
	}
}

public void OnEntityCreated(int ent, const char[] classname) {
	//originally checked for m_iUpgradeMetal but sappers have that prop too, and we don't want to hook those lol	
	if(HasEntProp(ent, Prop_Send, "m_iAmmoShells") || HasEntProp(ent, Prop_Send, "m_iAmmoMetal") || HasEntProp(ent, Prop_Send, "m_flRechargeTime")) {
		DHookEntity(hBuildRate, true, ent);
		SDKHook(ent, SDKHook_OnTakeDamage, buildingTakeDmg);
	}
}

public Action Hook_EntitySound(int plys[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &ply, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed) {
	if (StrContains(sample, "cbar_hit1", false) != -1 || 
		StrContains(sample, "cbar_hit2", false) != -1 || 
		StrContains(sample, "neon_sign_hit_world_01", false) != -1 || 
		StrContains(sample, "neon_sign_hit_world_02", false) != -1 || 
		StrContains(sample, "neon_sign_hit_world_03", false) != -1 || 
		StrContains(sample, "neon_sign_hit_world_04", false) != -1) { // CLANG!
		
		bool didWork = false;
		
		float angles[3];
		float eyepos[3];
		GetClientEyeAngles(ply, angles);
		GetClientEyePosition(ply, eyepos);

		//traceray out to find a building at the correct range, then attempt a construction hit
		//i wonder if there's a better way to do this that lets us trace a wider area, pyros have to be a lot more precise than engineers to hit buildings...
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
			
			//if our wrecker swing did any form of work on a building, play the normal sound, otherwise play the clink sound that denotes nothing happening to a building.
			if(didWork) { return Plugin_Continue; } else if(IsValidTarget(ply)){
				EmitSoundToAll(")weapons/wrench_hit_build_fail.wav", ply, channel);
				return Plugin_Stop; //the player swinging will still hear the original clang on top of the clink, but putting it on the same channel will make only the clink heard to everyone else.
			}
		}
		
	}
	
	return Plugin_Continue;
}

//im lazy and customstatusHUD was written for the sole purpose of empowering the lazy
public Action OnCustomStatusHUDUpdate(int ply, StringMap entries) {
	if(!IsPlayerAlive(ply) || !IsValidTarget(ply) ) { return Plugin_Continue; }
	int plyMetal = GetEntProp(ply, Prop_Send, "m_iAmmo", _, 3);
	char metalStr[12];
	
	//TODO: stop being lazy and use figure out how to use a valve translation key: TR_Eng_MetalTitle is "Metal"
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
	if (IsValidTarget(ply)) { //check if the player is swinging the right weapon 
		if (FindBuildingOwnerTeam(building) == GetClientTeam(ply)) {
			bool didWork = false;
			
			//keep track of a single building that a player is boosting and mark it as the boost target for the next second.
			//this means pyros can only boost one building at a time but between the swing speed and travel time it rarely overrides the existing one
			if(GetEntPropFloat(building, Prop_Send, "m_flPercentageConstructed") < 1.0 && GetConVarBool(cvarAllowBuildSpeed)) { //building is still constructing
				plyBoostTarget[ply] = building;
				if(IsValidHandle(plyBoostTimers[ply])) { KillTimer(plyBoostTimers[ply]); }
				plyBoostTimers[ply] = CreateTimer(1.0, clearBoostTarget, ply);
				
				return true;
			}
			
			//don't attempt performing heals/upgrades/restocks on buildings that are constructing or sapped (vanilla behavior kicks in on sappers)
			if (GetEntPropFloat(building, Prop_Send, "m_flPercentageConstructed") >= 1.0 && GetEntProp(building, Prop_Send, "m_bHasSapper") == 0) {
			
				//prevent restocking/upgrading a building while its in the middle of a level-up animation
				//each building has a different m_iState value for the upgrade animations - just check those and it's good enough
				//tele = 7, sentry = 3, dispenser = 1
				if(	(HasEntProp(building, Prop_Send, "m_iAmmoShells") && GetEntProp(building, Prop_Send, "m_iState") == 3) ||
					(HasEntProp(building, Prop_Send, "m_iAmmoMetal") && GetEntProp(building, Prop_Send, "m_iState") == 1) ||
					(HasEntProp(building, Prop_Send, "m_flRechargeTime") && GetEntProp(building, Prop_Send, "m_iState") == 7) ) {
					return false;
				}
				
				int plyMetal = GetEntProp(ply, Prop_Send, "m_iAmmo", _, 3);
				
				int buildingHP = GetEntProp(building, Prop_Send, "m_iHealth");
				int buildingHPmax = GetEntProp(building, Prop_Send, "m_iMaxHealth");
				int buildingUpgrade = GetEntProp(building, Prop_Send, "m_iUpgradeMetal");
				int buildingUpgradeMax = GetEntProp(building, Prop_Send, "m_iUpgradeMetalRequired");
				int buildingLevel = GetEntProp(building, Prop_Send, "m_iUpgradeLevel");
				int repairCost = 0;
				
				// -- HEAL BUILDING --
				//wrench cost calculations and order of operations adapted from Valve's wrench and building code.
				//this should ensure healing and upgrade logic and costs are 1:1 equivalent with engineer's wrenches.
				if (buildingHP < buildingHPmax && GetConVarBool(cvarAllowRepair)) {
					//first: calculate the cost
					int repairTotal = GetConVarInt(cvarRepairRate);
					int targetRepair = repairTotal;
					int missingHP = buildingHPmax - buildingHP;
					
					if(missingHP < repairTotal) { repairTotal = missingHP; }
					
					repairCost = RoundToCeil(float(repairTotal) / 3.0); //3:1 metal:HP ratio
					if(HasEntProp(building, Prop_Send, "m_flRechargeTime")) { repairCost = RoundToCeil(repairTotal / 5.0); } //teleporters use a 1:5 ratio instead (this is vanilla behavior)
					
					//reduce max potential incoming healing to wrangled sentries
					if(HasEntProp(building, Prop_Send, "m_nShieldLevel") && GetEntProp(building, Prop_Send, "m_nShieldLevel") != 0) {
						targetRepair = RoundToCeil(float(targetRepair) / 9);
						if(repairCost > targetRepair) { repairCost = targetRepair; }
					}
					
					if(repairCost > plyMetal) { repairCost = plyMetal; } //if it costs more than we can afford, reduce the cost to what we have and only heal that much
					
					plyMetal -=  repairCost; //deduct the metal. this will never be below 0 due to the sync above
					SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
					
					
					//second: repair the building, according to cost
					if(repairCost > 0) { didWork = true; } //building is either full health, or player has no metal
					int buildingHPnew = buildingHP + (repairCost * 3);
					if(HasEntProp(building, Prop_Send, "m_flRechargeTime")) { buildingHPnew = buildingHP + (repairCost * 5); } //teleporters
					if(buildingHPnew > buildingHPmax) { buildingHPnew = buildingHPmax; }
					
					if(didWork) { //only fire event if building was actually healed (if hit with 0 metal)
						SetVariantInt(buildingHPnew);
						AcceptEntityInput(building, "SetHealth");
						SetEntProp(building, Prop_Send, "m_iMaxHealth", buildingHPmax);
						Event healEvent = CreateEvent("building_healed", true);
						
						//fire a game event which should both be picked up by other plugins, and provides healing numbers when repairing buildings.
						SetEventInt(healEvent, "building", building);
						SetEventInt(healEvent, "healer", ply);
						if(HasEntProp(building, Prop_Send, "m_flRechargeTime")) { SetEventInt(healEvent, "amount", repairCost * 5); } else { SetEventInt(healEvent, "amount", repairCost * 3); }
						
						FireEvent(healEvent);
					}
				}
				
				//heal matching teleporter if applicable.
				int buildingMatch = GetMatchingTeleporter(building);
				if(buildingMatch > 0 && GetConVarBool(cvarAllowRepair)) {
					int buildingMatchHP = GetEntProp(buildingMatch, Prop_Send, "m_iHealth");
					int buildingMatchHPmax = GetEntProp(buildingMatch, Prop_Send, "m_iMaxHealth");
					
					//if the first teleporter is full-health, but this one isn't, then we need to calculate the cost again.
					//otherwise, we mirror the same amount healed to the first teleporter, without duducting any more metal.
					if(!didWork && buildingMatchHPmax > buildingMatchHP) {
						int repairTotal = GetConVarInt(cvarRepairRate);
						int missingHP = buildingMatchHPmax - buildingMatchHP;
						
						if(missingHP < repairTotal) { repairTotal = missingHP; }
						repairCost = RoundToCeil(repairTotal / 5.0);
						if(repairCost > plyMetal) { repairCost = plyMetal; }
						
						plyMetal -=  repairCost; //deduct the metal. this will never be below 0 due to the sync above
						SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
					}
					
					if(repairCost > 0) { didWork = true; }
					int buildingMatchHPnew = buildingMatchHP + (repairCost * 5);
					if(buildingMatchHPnew > buildingMatchHPmax) { buildingMatchHPnew = buildingMatchHPmax; }
					
					if(didWork) {
						SetVariantInt(buildingMatchHPnew);
						AcceptEntityInput(buildingMatch, "SetHealth");
						SetEntProp(buildingMatch, Prop_Send, "m_iMaxHealth", buildingMatchHPmax);
					}
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
					
					//wrangled sentries also recieve less ammo
					if(GetEntProp(building, Prop_Send, "m_nShieldLevel") != 0) { bulletsToRestock = bulletsToRestock / 3; rocketsToRestock = rocketsToRestock / 3; }
					
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
					
					if(GetConVarInt(cvarAllowRestock) > 1) {
					//rockets are set to 20 even at lv.1, so they will only be less than 20 after being fired
						int missingRockets = 20 - buildingRockets;
						if(plyMetal <= 1 || missingRockets == 0) { return didWork; }
						
						if(missingRockets > rocketsToRestock) { missingRockets = rocketsToRestock; }
						
						int rocketCost = missingRockets * 2;
						
						if(rocketCost > plyMetal) { rocketCost = plyMetal; }
						
						plyMetal -= rocketCost;
						
						rocketCost = RoundToFloor(float(rocketCost) / 2.0);
						
						SetEntProp(building, Prop_Send, "m_iAmmoRockets", buildingRockets+rocketCost);
						SetEntProp(ply, Prop_Send, "m_iAmmo", plyMetal, _, 3);
						didWork = true;
					}
				}
				
				return didWork;
			}
		}
	}
	return false;
}

//play the building alert sound to pyros with the homewrecker when the building takes its first damage
public Action buildingTakeDmg(int victim, int& attacker, int& inflictor, float& dmg, int& dmgType, int& weapon,  float dmgForce[3], float dmgPos[3]) {
	if(!GetConVarBool(cvarAlertSound)) { return Plugin_Continue; }
	
	if(GetEntProp(victim, Prop_Send, "m_iHealth") == GetEntProp(victim, Prop_Send, "m_iMaxHealth")) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsValidTarget(i) && GetClientTeam(i) == GetEntProp(victim, Prop_Send, "m_iTeamNum")) {
				EmitSoundToClient(i, "misc/hud_warning.wav", victim, _, SNDLEVEL_MINIBIKE);
			}
		}
	}
	return Plugin_Continue;
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