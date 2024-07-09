#define MAX_ROBOT_CLASS_TEMPLATES	40
#define ROBOT_CLASS_COUNT	view_as<int>(TFClass_Engineer)
#define MAXLEN_STRING_TEMPLATE	256
#define STRING_TEMPLATE_VALUE_NOT_FOUND	"KEYVALUE_NO_SEX_FOUND"
#define ROBOT_TEMPLATE_CONFIG_DIRECTORY	"configs/bwr3"
#define ROBOT_NAME_UNDEFINED	"TFBot"

enum eRobotTemplateType
{
	ROBOT_STANDARD,
	ROBOT_GIANT,
	ROBOT_GATEBOT,
	ROBOT_GATEBOT_GIANT,
	ROBOT_SENTRYBUSTER,
	ROBOT_BOSS,
	ROBOT_TEMPLATE_TYPE_COUNT
};

static Handle m_hDetonateTimer[MAXPLAYERS + 1];
static bool m_bHasDetonated[MAXPLAYERS + 1];
static bool m_bWasSuccessful[MAXPLAYERS + 1];
static bool m_bWasKilled[MAXPLAYERS + 1];

methodmap MvMSuicideBomber < MvMRobotPlayer
{
	public MvMSuicideBomber(int index)
	{
		return view_as<MvMSuicideBomber>(index);
	}
	
	public void Initialize(int victim)
	{
		this.SetMissionTarget(victim);
		
		m_bHasDetonated[this.index] = false;
		m_bWasSuccessful[this.index] = false;
		m_bWasKilled[this.index] = false;
	}
	
	public void DestroySuicideBomber()
	{
		this.DetonateTimerInvalidate();
	}
	
	public void DetonateTimerInvalidate()
	{
		if (m_hDetonateTimer[this.index])
		{
			KillTimer(m_hDetonateTimer[this.index]);
			m_hDetonateTimer[this.index] = null;
		}
	}
	
	public bool DetonateTimerHasStarted()
	{
		return m_hDetonateTimer[this.index] != null;
	}
	
	public void DetonateTimerStart(float duration)
	{
		m_hDetonateTimer[this.index] = CreateTimer(duration, Timer_SuicideBomberDetonate, this.index);
	}
	
	public void StartDetonate(bool bWasSuccessful = false, bool bWasKilled = false)
	{
		if (this.DetonateTimerHasStarted())
			return;
		
		OSTFPlayer player = OSTFPlayer(this.index);
		
		/* if (!IsPlayerAlive(this.index) || player.GetHealth() < 1)
		{
			if (TF2_GetClientTeam(this.index) != TFTeam_Spectator)
			{
				player.m_lifeState = LIFE_ALIVE;
				player.SetHealth(1);
			}
		} */
		
		m_bWasSuccessful[this.index] = bWasSuccessful;
		m_bWasKilled[this.index] = bWasKilled;
		
		player.m_takedamage = DAMAGE_NO;
		
		VS_Taunt(this.index, TAUNT_BASE_WEAPON);
		this.DetonateTimerStart(2.0);
		EmitGameSoundToAll("MvM.SentryBusterSpin", this.index);
	}
	
	public void Detonate()
	{
		m_bHasDetonated[this.index] = true;
		
		//Use vscript to emit the particles
		SetVariantString("DispatchParticleEffect(\"explosionTrail_seeds_mvm\", self.GetOrigin(), self.GetAngles()); DispatchParticleEffect(\"fluidSmokeExpl_ring_mvm\", self.GetOrigin(), self.GetAngles());");
		AcceptEntityInput(this.index, "RunScriptCode");
		
		EmitGameSoundToAll("MVM.SentryBusterExplode", this.index);
		
		float origin[3]; GetClientAbsOrigin(this.index, origin);
		UTIL_ScreenShake(origin, 25.0, 5.0, 5.0, 1000.0, SHAKE_START);
		
		if (!m_bWasSuccessful[this.index])
		{
			MultiplayRules_HaveAllPlayersSpeakConceptIfAllowed(MP_CONCEPT_MVM_SENTRY_BUSTER_DOWN, view_as<int>(TFTeam_Red));
			
			//TODO: decide to award achievement here
		}
		
		//The actual game function uses two CUtlVector objects for players
		//but it's not needed here since the second is just a copy of the first
		
		ArrayList adtVictims = new ArrayList();
		CollectPlayers(adtVictims, view_as<int>(TFTeam_Red), true);
		CollectPlayers(adtVictims, view_as<int>(TFTeam_Blue), true, true);
		
		//Add objects as potential victims
		int iEnt = -1;
		while ((iEnt = FindEntityByClassname(iEnt, "obj_*")) != -1)
			if (BaseEntity_GetTeamNumber(iEnt) == view_as<int>(TFTeam_Blue) || BaseEntity_GetTeamNumber(iEnt) == view_as<int>(TFTeam_Red))
				adtVictims.Push(iEnt);
		
		//TODO: non-player nextbots?
		
		if (m_bWasKilled[this.index])
		{
			Event hEvent = CreateEvent("mvm_sentrybuster_killed");
			
			if (hEvent)
			{
				hEvent.SetInt("sentry_buster", this.index);
				hEvent.Fire();
			}
		}
		
		this.SetMission(CTFBot_NO_MISSION);
		OSTFPlayer(this.index).m_takedamage = DAMAGE_YES;
		
		for (int i = 0; i < adtVictims.Length; i++)
		{
			int victim = adtVictims.Get(i);
			
			float toVictim[3]; SubtractVectors(WorldSpaceCenter(victim), WorldSpaceCenter(this.index), toVictim);
			
			if (Vector_IsLengthGreaterThan(toVictim, tf_bot_suicide_bomb_range.FloatValue))
				continue;
			
			if (BaseEntity_IsPlayer(i))
			{
				int colorHIt[4] = {255, 255, 255, 255};
				UTIL_ScreenFade(i, colorHIt, 1.0, 0.1, FFADE_IN);
			}
			
			if (TF2_IsLineOfFireClear4(this.index, victim))
			{
				NormalizeVector(toVictim, toVictim);
				
				int damage = MaxInt(BaseEntity_GetMaxHealth(victim), BaseEntity_GetHealth(victim));
				float finalDamage = SentryBuster_GetDamageForVictim(victim, float(damage));
				
#if defined MOD_EXT_CBASENPC
				CTakeDamageInfo info = GetGlobalDamageInfo();
				info.Init(this.index, this.index, _, _, _, finalDamage, DMG_BLAST, TF_DMG_CUSTOM_NONE);
				
				if (tf_bot_suicide_bomb_friendly_fire.BoolValue)
					info.SetForceFriendlyFire(true);
				
				CalculateMeleeDamageForce(info, toVictim, WorldSpaceCenter(this.index), 1.0);
				CBaseEntity(victim).TakeDamage(info);
#else
				float vecDamageForce[3]; CalculateMeleeDamageForce(finalDamage, toVictim, 1.0, vecDamageForce);
				SDKHooks_TakeDamage(victim, this.index, this.index, finalDamage, DMG_BLAST, _, vecDamageForce, WorldSpaceCenter(this.index));
#endif
			}
		}
		
		delete adtVictims;
		
		//SM NOTE: bForce is always set to true in SM 1.12
		ForcePlayerSuicide(this.index);
		
		// if (IsPlayerAlive(this.index))
			// VS_ForceChangeTeam(this.index, TFTeam_Spectator);
		
		if (m_bWasKilled[this.index])
		{
			//TODO: CWave -> IncrementSentryBustersKilled
		}
	}
}

int g_iRefLastTeleporter = INVALID_ENT_REFERENCE;
float g_flLastTeleportTime = -1.0;

static int m_iSpyTeleportAttempt[MAXPLAYERS + 1];

static Action Timer_SuicideBomberDetonate(Handle timer, any data)
{
	if (IsClientInGame(data) && IsPlayingAsRobot(data) && IsPlayerAlive(data) && !ShouldTacticalMonitorSuspendAction())
	{
		MvMSuicideBomber(data).Detonate();
		
		//TODO: victim stuff for detonation event
		if (m_bWasSuccessful[data])
		{
			
		}
	}
	
	m_hDetonateTimer[data] = null;
	
	return Plugin_Stop;
}

static Action Timer_SpyLeaveSpawnRoom(Handle timer, any data)
{
	if (!IsClientInGame(data) || !IsPlayerAlive(data) || !TF2_IsClass(data, TFClass_Spy))
		return Plugin_Stop;
	
	int victim = -1;
	
	ArrayList adtEnemy = new ArrayList();
	CollectPlayers(adtEnemy, view_as<int>(TFTeam_Red), true);
	
	ArrayList adtShuffle = adtEnemy.Clone();
	delete adtEnemy;
	int n = adtShuffle.Length;
	
	while (n > 1)
	{
		int k = GetRandomInt(0, n - 1);
		n--;
		
		int tmp = adtShuffle.Get(n);
		adtShuffle.Set(n, adtShuffle.Get(k));
		adtShuffle.Set(k, tmp);
	}
	
	for (int i = 0; i < adtShuffle.Length; i++)
	{
		if (TeleportNearVictim(data, adtShuffle.Get(i), m_iSpyTeleportAttempt[data]))
		{
			victim = adtShuffle.Get(i);
			break;
		}
	}
	
	delete adtShuffle;
	
	if (victim == -1)
	{
		CreateTimer(1.0, Timer_SpyLeaveSpawnRoom, data, TIMER_FLAG_NO_MAPCHANGE);
		
		m_iSpyTeleportAttempt[data]++;
		
		return Plugin_Stop;
	}
	
	SetPlayerToMove(data, true);
	
	return Plugin_Stop;
}

static Action Timer_MvMEngineerTeleportSpawn(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || !TF2_IsClass(client, TFClass_Engineer))
		return Plugin_Stop;
	
	int hintEntity = pack.ReadCell();
	
	if (!IsValidEntity(hintEntity))
		return Plugin_Stop;
	
	float angles[3]; angles = GetAbsAngles(hintEntity);
	float origin[3]; origin = GetAbsOrigin(hintEntity);
	origin[2] += 10.0;
	
	TeleportEntity(client, origin, angles, NULL_VECTOR);
	
	TE_TFParticleEffectComplex(0.0, "teleported_blue", origin, NULL_VECTOR);
	TE_TFParticleEffectComplex(0.0, "player_sparkles_blue", origin, NULL_VECTOR);
	
	//TODO: what exactly determines m_bFirstTeleportSpawn?
	TE_TFParticleEffectComplex(0.0, "teleported_mvm_bot", origin, NULL_VECTOR);
	EmitGameSoundToAll("Engineer.MVM_BattleCry07", client);
	EmitGameSoundToAll("MVM.Robot_Engineer_Spawn", hintEntity);
	
	if (IsValidEntity(g_iPopulationManager))
	{
		//TODO: CWave engineer stuff
	}
	
	return Plugin_Stop;
}

static float SentryBuster_GetDamageForVictim(int victim, float baseDamage)
{
	//Sentry busters are an exception to the damage override on minibosses rule
	//This is due to an order of precdence in CTFPlayer::OnTakeDamage
	if (IsSentryBusterRobot(victim))
		return baseDamage * 4;
	
	if (TF2_IsMiniBoss(victim))
		return SENTRYBUSTER_DMG_TO_MINIBOSS;
	
	return baseDamage * 4;
}

void TurnPlayerIntoRandomRobot(int client, eRobotTemplateType type = ROBOT_STANDARD)
{
	char fileName[PLATFORM_MAX_PATH];
	char filePath[PLATFORM_MAX_PATH];
	
	switch (type)
	{
		case ROBOT_STANDARD:
		{
			bwr3_robot_template_file.GetString(fileName, sizeof(fileName));
			BuildPath(Path_SM, filePath, sizeof(filePath), "%s/%s", ROBOT_TEMPLATE_CONFIG_DIRECTORY, fileName);
			
			if (!FileExists(filePath))
				ThrowError("Could not find standard robot config file: %s", filePath);
			
			KeyValues kv = new KeyValues("RobotStandardTemplates");
			kv.ImportFromFile(filePath);
			
			ParseRobotTemplateOntoPlayer(kv, client);
			delete kv;
		}
		case ROBOT_GIANT:
		{
			bwr3_robot_giant_template_file.GetString(fileName, sizeof(fileName));
			BuildPath(Path_SM, filePath, sizeof(filePath), "%s/%s", ROBOT_TEMPLATE_CONFIG_DIRECTORY, fileName);
			
			if (!FileExists(filePath))
				ThrowError("Could not find giant robot config file: %s", filePath);
			
			KeyValues kv = new KeyValues("RobotGiantTemplates");
			kv.ImportFromFile(filePath);
			
			ParseRobotTemplateOntoPlayer(kv, client);
			delete kv;
		}
		case ROBOT_GATEBOT:
		{
			bwr3_robot_gatebot_template_file.GetString(fileName, sizeof(fileName));
			BuildPath(Path_SM, filePath, sizeof(filePath), "%s/%s", ROBOT_TEMPLATE_CONFIG_DIRECTORY, fileName);
			
			if (!FileExists(filePath))
				ThrowError("Could not find gatebot robot config file: %s", filePath);
			
			KeyValues kv = new KeyValues("RobotGatebotTemplates");
			kv.ImportFromFile(filePath);
			
			ParseRobotTemplateOntoPlayer(kv, client);
			delete kv;
		}
		case ROBOT_SENTRYBUSTER:
		{
			bwr3_robot_sentrybuster_template_file.GetString(fileName, sizeof(fileName));
			BuildPath(Path_SM, filePath, sizeof(filePath), "%s/%s", ROBOT_TEMPLATE_CONFIG_DIRECTORY, fileName);
			
			if (!FileExists(filePath))
				ThrowError("Could not find sentry buster robot config file: %s", filePath);
			
			KeyValues kv = new KeyValues("RobotSentryBusterTemplates");
			kv.ImportFromFile(filePath);
			
			ParseRobotTemplateOntoPlayer(kv, client);
			delete kv;
		}
		case ROBOT_BOSS:
		{
			bwr3_robot_boss_template_file.GetString(fileName, sizeof(fileName));
			BuildPath(Path_SM, filePath, sizeof(filePath), "%s/%s", ROBOT_TEMPLATE_CONFIG_DIRECTORY, fileName);
			
			if (!FileExists(filePath))
				ThrowError("Could not find boss robot config file: %s", filePath);
			
			KeyValues kv = new KeyValues("RobotBossTemplates");
			kv.ImportFromFile(filePath);
			
			ParseRobotTemplateOntoPlayer(kv, client);
			delete kv;
		}
		default:	LogError("TurnPlayerIntoRandomRobot: Unknown robot template type %d", type);
	}
}

static void ParseRobotTemplateOntoPlayer(KeyValues kv, int client)
{
	if (kv.JumpToKey("Templates"))
	{
		kv.GotoFirstSubKey(false);
		
		int totalTemplates = 0;
		
		do
		{
			totalTemplates++;
		} while (kv.GotoNextKey(false))
		
		kv.GoBack();
		kv.GotoFirstSubKey(false);
		
		int chosenTemplate = GetRandomInt(1, totalTemplates);
		int count = 0;
		
		//This was already bad was it was, but doing another loop is just ridiculous
		do
		{
			count++;
			
			if (count == chosenTemplate)
			{
				TF2Attrib_RemoveAll(client);
				
				//First we need to join as the class desired by the template
				char className[PLATFORM_MAX_PATH]; kv.GetString("Class", className, sizeof(className));
				TFClassType playerClass = TF2_GetClassIndexFromString(className);
				Player_JoinClass(client, playerClass);
				
				//After joining a class, remove their weapons and cosmetics
				StripWeapons(client, true, TFWeaponSlot_Building);
				RemovePowerupBottle(client);
				RemoveSpellbook(client);
				
				if (bwr3_cosmetic_mode.IntValue == COSMETIC_MODE_NONE)
					RemoveCosmetics(client);
				
				MvMRobotPlayer roboPlayer = MvMRobotPlayer(client);
				
				//Now we set the robot's basic details here
				char kvStringBuffer[16]; kv.GetString("Skill", kvStringBuffer, sizeof(kvStringBuffer));
				roboPlayer.SetDifficulty(GetSkillFromString(kvStringBuffer));
				
				roboPlayer.ClearWeaponRestrictions();
				kv.GetString("WeaponRestrictions", kvStringBuffer, sizeof(kvStringBuffer));
				roboPlayer.SetWeaponRestriction(GetWeaponRestrictionFlagsFromString(kvStringBuffer));
				
				roboPlayer.SetAutoJump(kv.GetFloat("AutoJumpMin"), kv.GetFloat("AutoJumpMax"));
				roboPlayer.SetMaxVisionRange(kv.GetFloat("MaxVisionRange", -1.0));
				roboPlayer.ClearTags();
				
				char botTags[BOT_TAGS_BUFFER_MAX_LENGTH]; kv.GetString("Tags", botTags, sizeof(botTags));
				
				if (strlen(botTags) > 0)
				{
					char splitTags[MAX_BOT_TAG_CHECKS][BOT_TAG_EACH_MAX_LENGTH];
					int splitTagsCount = ExplodeString(botTags, ",", splitTags, sizeof(splitTags), sizeof(splitTags[]));
					
					for (int i = 0; i < splitTagsCount; i++)
						roboPlayer.AddTag(splitTags[i]);
				}
				
				//Not usually part of a robot template, but I don't see any other way to do it here
				kv.GetString("Objective", kvStringBuffer, sizeof(kvStringBuffer));
				roboPlayer.SetMission(GetBotMissionFromString(kvStringBuffer));
				
				//These will be used later
				char name[MAX_NAME_LENGTH]; kv.GetString("Name", name, sizeof(name), ROBOT_NAME_UNDEFINED);
				int health = kv.GetNum("Health");
				float scale = kv.GetFloat("Scale");
				char classIcon[PLATFORM_MAX_PATH]; kv.GetString("ClassIcon", classIcon, sizeof(classIcon));
				int credits = kv.GetNum("TotalCurrency");
				
				roboPlayer.ClearAllAttributes();
				
				if (kv.JumpToKey("BotAttributes"))
				{
					roboPlayer.SetAttribute(GetBotAttributesFromKeyValues(kv));
					kv.GoBack();
				}
				
				if (kv.JumpToKey("CharacterAttributes"))
				{
					if (kv.GotoFirstSubKey(false))
					{
						char attributeName[PLATFORM_MAX_PATH];
						char attributeValue[PLATFORM_MAX_PATH];
						
						do
						{
							kv.GetSectionName(attributeName, sizeof(attributeName));
							kv.GetString(NULL_STRING, attributeValue, sizeof(attributeValue));
							
							TF2Attrib_SetFromStringValue(client, attributeName, attributeValue);
						} while (kv.GotoNextKey(false))
						
						kv.GoBack();
					}
					
					kv.GoBack();
				}
				
				if (kv.JumpToKey("Items"))
				{
					if (kv.GotoFirstSubKey(false))
					{
						char itemName[128];
						int item = -1;
						
						do
						{
							kv.GetSectionName(itemName, sizeof(itemName));
							
							item = AddItemToPlayer(client, itemName);
							
							if (item != -1)
							{
								if (kv.GotoFirstSubKey(false))
								{
									char attributeName[PLATFORM_MAX_PATH];
									char attributeValue[PLATFORM_MAX_PATH];
									
									do
									{
										kv.GetSectionName(attributeName, sizeof(attributeName));
										kv.GetString(NULL_STRING, attributeValue, sizeof(attributeValue));
										
										TF2Attrib_SetFromStringValue(item, attributeName, attributeValue);
									} while (kv.GotoNextKey(false))
									
									kv.GoBack();
								}
							}
						} while (kv.GotoNextKey(false))
						
						kv.GoBack();
					}
					
					kv.GoBack();
				}
				
				//Now we do all the stuff needed for when the bot spawns
				DataPack pack;
				CreateDataTimer(0.1, Timer_FinishRobotPlayer, pack);
				pack.WriteCell(client);
				pack.WriteString(name);
				pack.WriteCell(health);
				pack.WriteFloat(scale);
				pack.WriteCell(playerClass);
				pack.WriteString(classIcon);
				pack.WriteCell(credits);
				
				break;
			}
		} while (kv.GotoNextKey(false))
	}
}

static Action Timer_FinishRobotPlayer(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();
	
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return Plugin_Stop;
	
	char strName[MAX_NAME_LENGTH]; pack.ReadString(strName, sizeof(strName));
	int iHealth = pack.ReadCell();
	float flScale = pack.ReadFloat();
	TFClassType iClass = pack.ReadCell();
	char strClassIcon[PLATFORM_MAX_PATH]; pack.ReadString(strClassIcon, sizeof(strClassIcon));
	int iCreditAmount = pack.ReadCell();
	
	MvMRobotPlayer roboPlayer = MvMRobotPlayer(client);
	OSTFPlayer player = OSTFPlayer(client);
	
	if (strlen(strClassIcon) > 0)
		player.SetClassIconName(strClassIcon);
	
	roboPlayer.ClearTeleportWhere();
	
	// PrintToChat(client, "%s %t", "Player_Spawn_As_Robot", strName);
	
	//TODO: SetTeleportWhjere
	
	if (roboPlayer.HasAttribute(CTFBot_MINIBOSS))
		player.SetIsMiniBoss(true);
	
	if (roboPlayer.HasAttribute(CTFBot_USE_BOSS_HEALTH_BAR))
		player.SetUseBossHealthBar(true);
	
	//Handled elsewhere
	/* if (roboPlayer.HasAttribute(CTFBot_AUTO_JUMP))
		roboPlayer.SetAutoJump(flAutoJumpMin, flAutoJumpMax); */
	
	if (roboPlayer.HasAttribute(CTFBot_BULLET_IMMUNE))
		player.AddCond(TFCond_BulletImmune);
	
	if (roboPlayer.HasAttribute(CTFBot_BLAST_IMMUNE))
		player.AddCond(TFCond_BlastImmune);
	
	if (roboPlayer.HasAttribute(CTFBot_FIRE_IMMUNE))
		player.AddCond(TFCond_FireImmune);
	
	//Currency is used as an amount to drop
	player.SetCurrency(iCreditAmount);
	
	int nMission = roboPlayer.GetMission();
	int spyCount = 0;
	int nSniperCount = 0;
	
	if (iClass == TFClass_Spy || nMission == CTFBot_MISSION_SNIPER)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && TF2_GetClientTeam(i) == TFTeam_Blue && IsPlayerAlive(i))
			{
				if (TF2_IsClass(i, TFClass_Spy))
					spyCount++;
				
				if (TF2_IsClass(i, TFClass_Sniper))
					nSniperCount++;
			}
		}
	}
	
	//Announce incoming spies
	//This will update the count for every spy on blue that is currently active
	if (iClass == TFClass_Spy)
	{
		Event hEvent = CreateEvent("mvm_mission_update");

		if (hEvent)
		{
			hEvent.SetInt("class", view_as<int>(TFClass_Spy));
			hEvent.SetInt("count", spyCount);
			hEvent.Fire();
		}
	}
	
	if (flScale > 0.0)
		player.SetModelScale(flScale);
	
	int nHealth = iHealth;
	
	if (nHealth <= 0.0)
		nHealth = player.GetMaxHealth();
	
	//TODO: factor in GetHealthMultiplier for endless waves
	
	ModifyMaxHealth(client, nHealth, _, _, flScale);
	
	StartIdleSound(client, iClass);
	
	//NOTE: romevision is added later
	
	//TODO: EventChangeAttributes
	
	if (roboPlayer.HasAttribute(CTFBot_SPAWN_WITH_FULL_CHARGE))
	{
		int medigun = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
		
		if (medigun != -1 && TF2Util_GetWeaponID(medigun) == TF_WEAPON_MEDIGUN)
			SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", 1.0);
		
		SetEntPropFloat(client, Prop_Send, "m_flRageMeter", 100.0);
	}
	
	int nClassIndex = view_as<int>(iClass);
	
	//TODO: this should be using the value of m_nMvMEventPopfileType from CPopulationManager
	if (GetEntProp(g_iObjectiveResource, Prop_Send, "m_nMvMEventPopfileType") == MVM_EVENT_POPFILE_HALLOWEEN)
	{
		//NOTE: this part wouldn't actually change anything visibly due to how the client's game is coded
		player.m_nSkin = 4;
		
		char itemName[64]; Format(itemName, sizeof(itemName), "Zombie %s", g_sClassNamesShort[nClassIndex]);
		
		AddItemToPlayer(client, itemName);
	}
	else
	{
		if (iClass >= TFClass_Scout && iClass <= TFClass_Engineer && nMission != CTFBot_MISSION_DESTROY_SENTRIES)
		{
			if ((flScale >= tf_mvm_miniboss_scale.FloatValue || roboPlayer.HasAttribute(CTFBot_MINIBOSS)) /* && FileExists(g_sBotBossModels[nClassIndex]) */)
			{
				player.SetCustomModel(g_sBotBossModels[nClassIndex], true);
				player.SetBloodColor(DONT_BLEED);
			}
			else //if (FileExists(g_sBotModels[nClassIndex]))
			{
				player.SetCustomModel(g_sBotModels[nClassIndex], true);
				player.SetBloodColor(DONT_BLEED);
			}
		}
	}
	
	if (nMission == CTFBot_MISSION_DESTROY_SENTRIES)
	{
		player.SetCustomModel(g_sBotSentryBusterModel, true);
		player.SetBloodColor(DONT_BLEED);
	}
	
	//Do this after the items, since this one only adds new ones if there are no equip region conflicts
	AddRomevisionCosmetics(client);
	
	//Standard shit i guess
	PostInventoryApplication(client);
	
	if (nMission == CTFBot_MISSION_DESTROY_SENTRIES)
	{
		MvMSuicideBomber(client).Initialize(GetMostThreateningSentry());
		
		if (IsValidEntity(g_iObjectiveResource))
		{
			int iFlags = MVM_CLASS_FLAG_MISSION;
			
			if (roboPlayer.HasAttribute(CTFBot_MINIBOSS))
				iFlags |= MVM_CLASS_FLAG_MINIBOSS;
			
			if (roboPlayer.HasAttribute(CTFBot_ALWAYS_CRIT))
				iFlags |= MVM_CLASS_FLAG_ALWAYSCRIT;
			
			TF2_IncrementMannVsMachineWaveClassCount(g_iObjectiveResource, strClassIcon, iFlags);
		}
		
		MultiplayRules_HaveAllPlayersSpeakConceptIfAllowed(MP_CONCEPT_MVM_SENTRY_BUSTER, view_as<int>(TFTeam_Red));
	}
	else if (nMission == CTFBot_MISSION_SNIPER)
	{
		if (IsValidEntity(g_iObjectiveResource))
		{
			int iFlags = MVM_CLASS_FLAG_MISSION;
			
			if (roboPlayer.HasAttribute(CTFBot_MINIBOSS))
				iFlags |= MVM_CLASS_FLAG_MINIBOSS;
			
			if (roboPlayer.HasAttribute(CTFBot_ALWAYS_CRIT))
				iFlags |= MVM_CLASS_FLAG_ALWAYSCRIT;
			
			TF2_IncrementMannVsMachineWaveClassCount(g_iObjectiveResource, strClassIcon, iFlags);
		}
		
		//Don't update this as the loop done earlier already counts ourselves as we;ve already changed classes by now
		// nSniperCount++;
		
		//Only the first sniper is announced by the defenders
		if (nSniperCount == 1)
			MultiplayRules_HaveAllPlayersSpeakConceptIfAllowed(MP_CONCEPT_MVM_SNIPER_CALLOUT, view_as<int>(TFTeam_Red));
	}
	else if (roboPlayer.HasAttribute(CTFBot_MINIBOSS))
	{
		MultiplayRules_HaveAllPlayersSpeakConceptIfAllowed(MP_CONCEPT_MVM_GIANT_CALLOUT, view_as<int>(TFTeam_Red));
	}
	
	float rawHere[3];
	
	if (GetSpawnLocation(rawHere) == SPAWN_LOCATION_TELEPORTER)
		OnBotTeleported(client);
	
	float here[3]; here = rawHere;
	
	float z;
	
	//Try a few heights to see if we can actually spawn here
	for (z = 0.0; z < TFBOT_STEP_HEIGHT; z += 4.0)
	{
		here[2] = rawHere[2] + TFBOT_STEP_HEIGHT;
		
		if (IsSpaceToSpawnHere(here))
			break;
	}
	
	if (z >= TFBOT_STEP_HEIGHT)
	{
		LogError("Timer_FinishRobotPlayer: %3.2f: *** No space to spawn at (%f, %f, %f)", GetGameTime(), here[0], here[1], here[2]);
		// return Plugin_Stop;
	}
	
	TeleportEntity(client, here);
	
	if (iClass == TFClass_Spy)
	{
		SpyLeaveSpawnRoom_OnStart(client);
	}
	else if (iClass == TFClass_Engineer && roboPlayer.HasAttribute(CTFBot_TELEPORT_TO_HINT))
	{
		MvMEngineerTeleportSpawn(client);
	}
	
	//For TFBots this is actually checked in CTFBot::PhysicsSimulate
	if (roboPlayer.HasAttribute(CTFBot_ALWAYS_CRIT))
		player.AddCond(TFCond_CritCanteen);
	
#if defined TESTING_ONLY
	LogAction(client, -1, "%3.2f: %L spawned as robot %s", GetGameTime(), client, strName);
#endif
	
	return Plugin_Stop;
}

static DifficultyType GetSkillFromString(const char[] value)
{
	if (strlen(value) > 0)
	{
		if (!strcmp(value, "Easy"))
		{
			return CTFBot_EASY;
		}
		else if (!strcmp(value, "Normal"))
		{
			return CTFBot_NORMAL;
		}
		else if (!strcmp(value, "Hard"))
		{
			return CTFBot_HARD;
		}
		else if (!strcmp(value, "Expert"))
		{
			return CTFBot_EXPERT;
		}
		else
		{
			LogError("ParseDynamioAttributes: Invalid skill '%s'", value);
			return CTFBot_EASY;
		}
	}
	
	return CTFBot_EASY;
}

static WeaponRestrictionType GetWeaponRestrictionFlagsFromString(const char[] value)
{
	if (strlen(value) > 0)
	{
		if (!strcmp(value, "MeleeOnly"))
		{
			return CTFBot_MELEE_ONLY;
		}
		else if (!strcmp(value, "PrimaryOnly"))
		{
			return CTFBot_PRIMARY_ONLY;
		}
		else if (!strcmp(value, "SecondaryOnly"))
		{
			return CTFBot_SECONDARY_ONLY;
		}
		else
		{
			LogError("ParseDynamioAttributes: Invalid weapon restriction '%s'", value);
			return CTFBot_ANY_WEAPON;
		}
	}
	
	return CTFBot_ANY_WEAPON;
}

static int GetBotMissionFromString(const char[] value)
{
	if (strlen(value) > 0)
	{
		if (!strcmp(value, "DestroySentries"))
		{
			return CTFBot_MISSION_DESTROY_SENTRIES;
		}
		else if (!strcmp(value, "Sniper"))
		{
			return CTFBot_MISSION_SNIPER;
		}
		else if (!strcmp(value, "Spy"))
		{
			return CTFBot_MISSION_SPY;
		}
		else if (!strcmp(value, "Engineer"))
		{
			return CTFBot_MISSION_ENGINEER;
		}
		else if (!strcmp(value, "SeekAndDestroy"))
		{
			return CTFBot_MISSION_DESTROY_SENTRIES;
		}
		else
		{
			LogError("GetBotMissionFromString: Invalid mission '%s'", value);
			return CTFBot_NO_MISSION;
		}
	}
	
	return CTFBot_NO_MISSION;
}

static AttributeType GetBotAttributesFromKeyValues(KeyValues kv)
{
	AttributeType flags = CTFBot_NONE;
	
	if (kv.GetNum("RemoveOnDeath") > 0)
	{
		flags |= CTFBot_REMOVE_ON_DEATH;
	}
	
	if (kv.GetNum("Aggressive") > 0)
	{
		flags |= CTFBot_AGGRESSIVE;
	}
	if (kv.GetNum("SuppressFire") > 0)
	{
		flags |= CTFBot_SUPPRESS_FIRE;
	}
	if (kv.GetNum("DisableDodge") > 0)
	{
		flags |= CTFBot_DISABLE_DODGE;
	}
	if (kv.GetNum("BecomeSpectatorOnDeath") > 0)
	{
		flags |= CTFBot_BECOME_SPECTATOR_ON_DEATH;
	}
	if (kv.GetNum("RetainBuildings") > 0)
	{
		flags |= CTFBot_RETAIN_BUILDINGS;
	}
	if (kv.GetNum("SpawnWithFullCharge") > 0)
	{
		flags |= CTFBot_SPAWN_WITH_FULL_CHARGE;
	}
	if (kv.GetNum("AlwaysCrit") > 0)
	{
		flags |= CTFBot_ALWAYS_CRIT;
	}
	if (kv.GetNum("IgnoreEnemies") > 0)
	{
		flags |= CTFBot_IGNORE_ENEMIES;
	}
	if (kv.GetNum("HoldFireUntilFullReload") > 0)
	{
		flags |= CTFBot_HOLD_FIRE_UNTIL_FULL_RELOAD;
	}
	if (kv.GetNum("AlwaysFireWeapon") > 0)
	{
		flags |= CTFBot_ALWAYS_FIRE_WEAPON;
	}
	if (kv.GetNum("TeleportToHint") > 0)
	{
		flags |= CTFBot_TELEPORT_TO_HINT;
	}
	if (kv.GetNum("MiniBoss") > 0)
	{
		flags |= CTFBot_MINIBOSS;
	}
	if (kv.GetNum("UseBossHealthBar") > 0)
	{
		flags |= CTFBot_USE_BOSS_HEALTH_BAR;
	}
	if (kv.GetNum("IgnoreFlag") > 0)
	{
		flags |= CTFBot_IGNORE_FLAG;
	}
	if (kv.GetNum("AutoJump") > 0)
	{
		flags |= CTFBot_AUTO_JUMP;
	}
	if (kv.GetNum("AirChargeOnly") > 0)
	{
		flags |= CTFBot_AIR_CHARGE_ONLY;
	}
	if (kv.GetNum("VaccinatorBullets") > 0)
	{
		flags |= CTFBot_PREFER_VACCINATOR_BULLETS;
	}
	if (kv.GetNum("VaccinatorBlast") > 0)
	{
		flags |= CTFBot_PREFER_VACCINATOR_BLAST;
	}
	if (kv.GetNum("VaccinatorFire") > 0)
	{
		flags |= CTFBot_PREFER_VACCINATOR_FIRE;
	}
	if (kv.GetNum("BulletImmune") > 0)
	{
		flags |= CTFBot_BULLET_IMMUNE;
	}
	if (kv.GetNum("BlastImmune") > 0)
	{
		flags |= CTFBot_BLAST_IMMUNE;
	}
	if (kv.GetNum("FireImmune") > 0)
	{
		flags |= CTFBot_FIRE_IMMUNE;
	}
	if (kv.GetNum("Parachute") > 0)
	{
		flags |= CTFBot_PARACHUTE;
	}
	if (kv.GetNum("ProjectileShield") > 0)
	{
		flags |= CTFBot_PROJECTILE_SHIELD;
	}
	
	return flags;
}

//Different from CTFBot::ModifyMaxHealth, as I don't feel model scale override necessary as its own variable right now
static void ModifyMaxHealth(int client, int nNewMaxHealth, bool bSetCurrentHealth = true, bAllowModelScaling = true, float flModelScaleOverride = 0.0)
{
	OSTFPlayer player = OSTFPlayer(client);
	
	int maxHealth = player.GetMaxHealth();
	if (maxHealth != nNewMaxHealth)
		TF2Attrib_SetByName(client, "hidden maxhealth non buffed", float(nNewMaxHealth - maxHealth));
	
	if (bSetCurrentHealth)
		player.SetHealth(nNewMaxHealth);
	
	if (bAllowModelScaling && player.IsMiniBoss())
		player.SetModelScale(flModelScaleOverride > 0.0 ? flModelScaleOverride : tf_mvm_miniboss_scale.FloatValue);
}

static void StartIdleSound(int client, TFClassType class)
{
	StopIdleSound(client);
	
	//TODO: we could actually have a variable per player store the sound path they are currently playing
	//Use GetGameSoundParams to fill out info, play the sound given from the returned sample
	//then store that sample on a glboal string array for the player
	
	if (TF2_IsMiniBoss(client))
	{
		switch (class)
		{
			//Use actual sound files with specific modifications since game sounds can have multiple waves
			case TFClass_Heavy:	EmitSoundToAll(SOUND_GIANT_HEAVY_LOOP, client, SNDCHAN_STATIC, 83, _, 0.8);
			case TFClass_Soldier:	EmitSoundToAll(SOUND_GIANT_SOLDIER_LOOP, client, SNDCHAN_STATIC, 82);
			case TFClass_DemoMan:
			{
				EmitSoundToAll(MvMRobotPlayer(client).HasMission(CTFBot_MISSION_DESTROY_SENTRIES) ? SOUND_SENTRYBUSTER_LOOP : SOUND_GIANT_DEMOMAN_LOOP, client, SNDCHAN_STATIC, 82, _, 0.6);
			}
			case TFClass_Scout:	EmitSoundToAll(SOUND_GIANT_SCOUT_LOOP, client, SNDCHAN_STATIC, 85, _, 0.3);
			case TFClass_Pyro:	EmitSoundToAll(SOUND_GIANT_PYRO_LOOP, client, SNDCHAN_STATIC, 83, _, 0.8);
		}
	}
}

//NEW METHOD: heavily based on a function from [TF2] Chaos Mod
static int AddItemToPlayer(int client, const char[] szItemName)
{
	int iItemDefIndex = GetItemDefinitionIndexByName(szItemName);
	
	if (iItemDefIndex != TF_ITEMDEF_DEFAULT)
	{
		// If we already have an item in that slot, remove it
		TFClassType nClass = TF2_GetPlayerClass(client);
		int iSlot = TF2Econ_GetItemLoadoutSlot(iItemDefIndex, nClass);
		int nNewItemRegionMask = TF2Econ_GetItemEquipRegionMask(iItemDefIndex);
		
		if (IsWearableSlot(iSlot))
		{
			// Remove any wearable that has a conflicting equip_region
			for (int wbl = 0; wbl < TF2Util_GetPlayerWearableCount(client); wbl++)
			{
				int wearable = TF2Util_GetPlayerWearable(client, wbl);
				if (wearable == -1)
					continue;
				
				int iWearableDefIndex = GetEntProp(wearable, Prop_Send, "m_iItemDefinitionIndex");
				if (iWearableDefIndex == 0xFFFF)
					continue;
				
				int nWearableRegionMask = TF2Econ_GetItemEquipRegionMask(iWearableDefIndex);
				if (nWearableRegionMask & nNewItemRegionMask)
				{
					TF2_RemoveWearable(client, wearable);
				}
			}
		}
		else
		{
			int entity = TF2Util_GetPlayerLoadoutEntity(client, iSlot);
			if (entity != -1)
			{
				RemovePlayerItem(client, entity);
				RemoveEntity(entity);
			}
		}
		
		char szClassname[64];
		TF2Econ_GetItemClassName(iItemDefIndex, szClassname, sizeof(szClassname));
		TF2Econ_TranslateWeaponEntForClass(szClassname, sizeof(szClassname), nClass);
		
		int newItem = EconItemCreateNoSpawn(szClassname, iItemDefIndex, 1, AE_UNIQUE);
		
		if (newItem != -1)
		{
			EconItemView_SetItemID(newItem, 1);
			EconItemSpawnGiveTo(newItem, client);
		}
		
		// PostInventoryApplication(client);
		
		return newItem;
	}
	else
	{
		if (szItemName[0])
		{
			LogError("GiveItem: Invalid item %s.", szItemName);
		}
	}
	
	return -1;
}

static void AddRomevisionCosmetics(int client)
{
	//We're not gonna nitpicks about adding then removing items, as it's counter-intuitive
	//Instead, we will only add the items if they have no conflict with what we're currently wearing
	if (MvMRobotPlayer(client).HasMission(CTFBot_MISSION_DESTROY_SENTRIES))
	{
		const int sentrybusterRomeDefIndex = 30161; //tw_sentrybuster
		
		if (!DoPlayerWearablesConflictWith(client, sentrybusterRomeDefIndex))
		{
			int item = EconItemCreateNoSpawn("tf_wearable", sentrybusterRomeDefIndex, 1, AE_UNIQUE);
			
			if (item != -1)
			{
				EconItemView_SetItemID(item, 1);
				EconItemSpawnGiveTo(item, client);
			}
		}
	}
	else
	{
		int classIndex = view_as<int>(TF2_GetPlayerClass(client));
		int hatIndex = g_iRomePromoItems_Hat[classIndex];
		int miscIndex = g_iRomePromoItems_Misc[classIndex];
		
		if (!DoPlayerWearablesConflictWith(client, hatIndex))
		{
			int item = EconItemCreateNoSpawn("tf_wearable", hatIndex, 1, AE_UNIQUE);
			
			if (item != -1)
			{
				EconItemView_SetItemID(item, 1);
				EconItemSpawnGiveTo(item, client);
			}
		}
		
		if (!DoPlayerWearablesConflictWith(client, miscIndex))
		{
			int item = EconItemCreateNoSpawn("tf_wearable", miscIndex, 1, AE_UNIQUE);
			
			if (item != -1)
			{
				EconItemView_SetItemID(item, 1);
				EconItemSpawnGiveTo(item, client);
			}
		}
	}
	
	// PostInventoryApplication(client);
}

//TODO: fix me
static int GetMostThreateningSentry()
{
	int nDmgLimit = 0;
	int nKillLimit = 0;
	GetSentryBusterDamageAndKillThreshold(g_iPopulationManager, nDmgLimit, nKillLimit);
	
	int iEnt = -1;
	
	while ((iEnt = FindEntityByClassname(iEnt, "obj_sentrygun")) != -1)
	{
		OSBaseObject cboSentry = OSBaseObject(iEnt);
		
		if (cboSentry.IsDisposableBuilding())
			continue;
		
		if (cboSentry.GetTeamNumber() == view_as<int>(TFTeam_Red))
		{
			int sentryOwner = cboSentry.GetOwner();
			
			if (sentryOwner != -1)
			{
				int nDmgDone = GetAccumulatedSentryGunDamageDealt(sentryOwner);
				int nKillsMade = GetAccumulatedSentryGunKillCount(sentryOwner);
				
				if (nDmgDone >= nDmgLimit || nKillsMade >= nKillLimit)
					return iEnt;
			}
		}
	}
	
	return -1;
}

static SpawnLocationResult GetSpawnLocation(float vSpawnPosition[3])
{
	int activeTeleporter = EntRefToEntIndex(g_iRefLastTeleporter);
	
	if (activeTeleporter != INVALID_ENT_REFERENCE && IsTeleporterUsableByRobots(activeTeleporter))
	{
		//Just use the teleporter we're already aware of
		vSpawnPosition = WorldSpaceCenter(activeTeleporter);
		return SPAWN_LOCATION_TELEPORTER;
	}
	
	ArrayList adtTeleporter = new ArrayList();
	int ent = -1;
	
	while ((ent = FindEntityByClassname(ent, "obj_teleporter")) != -1)
	{
		if (!IsTeleporterUsableByRobots(ent))
			continue;
		
		adtTeleporter.Push(ent);
	}
	
	if (adtTeleporter.Length > 0)
	{
		int which = GetRandomInt(0, adtTeleporter.Length - 1);
		int chosenTeleporter = adtTeleporter.Get(which);
		delete adtTeleporter;
		
		vSpawnPosition = WorldSpaceCenter(chosenTeleporter);
		g_iRefLastTeleporter = EntIndexToEntRef(chosenTeleporter);
		
		return SPAWN_LOCATION_TELEPORTER;
	}
	
	delete adtTeleporter;
	
	ent = -1;
	ArrayList adtSpawnPoints = new ArrayList();
	
	while ((ent = FindEntityByClassname(ent, "info_player_teamspawn")) != -1)
	{
		if (GetEntProp(ent, Prop_Data, "m_bDisabled") == 1)
			continue;
		
		if (BaseEntity_GetTeamNumber(ent) == view_as<int>(TFTeam_Red))
			continue;
		
		adtSpawnPoints.Push(ent);
	}
	
	if (adtSpawnPoints.Length == 0)
	{
		//Could not find any spawn points to begin with
		delete adtSpawnPoints;
		return SPAWN_LOCATION_NOT_FOUND;
	}
	
	float origin[3];
	int maxTries = adtSpawnPoints.Length;
	
	for (int i = 0; i < maxTries; i++)
	{
		int index = GetRandomInt(0, adtSpawnPoints.Length - 1);
		int spawn = adtSpawnPoints.Get(index);
		adtSpawnPoints.Erase(index);
		origin = WorldSpaceCenter(spawn);
		
		//TODO: this should factor in the scale of the robot
		if (IsSpaceToSpawnHere(origin))
		{
			vSpawnPosition = origin;
			break;
		}
	}
	
	delete adtSpawnPoints;
	
	if (IsZeroVector(vSpawnPosition))
		return SPAWN_LOCATION_NOT_FOUND;
	
	return SPAWN_LOCATION_NAV;
}

static void OnBotTeleported(int client)
{
	int teleporter = EntRefToEntIndex(g_iRefLastTeleporter);
	
	// float origin[3]; origin = GetAbsOrigin(teleporter);
	
	if (GetGameTime() - g_flLastTeleportTime > 0.1)
	{
		EmitGameSoundToAll("MVM.Robot_Teleporter_Deliver", teleporter);
		g_flLastTeleportTime = GetGameTime();
	}
	
	//Have us face the direction specified by the teleporter
	float vForward[3];
	float teleporterAngles[3]; teleporterAngles = GetAbsAngles(teleporter);
	GetAngleVectors(teleporterAngles, vForward, NULL_VECTOR, NULL_VECTOR);
	
	float vecFaceTowards[3]; GetClientAbsOrigin(client, vecFaceTowards);
	vecFaceTowards[0] = vecFaceTowards[0] + 50 * vForward[0];
	vecFaceTowards[1] = vecFaceTowards[1] + 50 * vForward[1];
	vecFaceTowards[2] = vecFaceTowards[2] + 50 * vForward[2];
	
	SnapViewToPosition(client, vecFaceTowards);
	
	if (!TF2_IsClass(client, TFClass_Spy))
	{
		TeleportEffect(client);
		
		float flUberTime = tf_mvm_engineer_teleporter_uber_duration.FloatValue;
		TF2_AddCondition(client, TFCond_Ubercharged, flUberTime);
		TF2_AddCondition(client, TFCond_UberchargeFading, flUberTime);
	}
}

static int GetEngineerHint()
{
	float bestDistance = 999999.0;
	int bestEnt = -1;
	int ent = -1;
	int flag = FindBombNearestToHatch();
	
	if (flag != -1)
	{
		float origin[3]; origin = WorldSpaceCenter(flag);
		
		while ((ent = FindEntityByClassname(ent, "bot_hint_engineer_nest")) != -1)
		{
			if (GetEntProp(ent, Prop_Data, "m_isDisabled") == 1)
				continue;
			
			float distance = GetVectorDistance(origin, GetAbsOrigin(ent));
			
			if (distance <= bestDistance)
			{
				bestDistance = distance;
				bestEnt = ent;
			}
		}
	}
	else
	{
		//TODO: find the engineer hint closest to the robot spawn then
	}
	
	return bestEnt;
}

static int GetActiveSentryBusterCount()
{
	int count = 0;
	
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && TF2_GetClientTeam(i) == TFTeam_Blue && IsPlayerAlive(i) && IsSentryBusterRobot(i))
			count++;
	
	return count;
}

//See if another player is already after this sentry
static bool IsSentryAlreadyTargeted(int sentry)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayingAsRobot(i) && MvMSuicideBomber(i).GetMissionTarget() == sentry)
			return true;
	
	return false;
}

void SelectSpawnRobotTypeForPlayer(int client)
{
	/* int sentry = GetMostThreateningSentry();
	
	if (sentry != -1 && !IsSentryAlreadyTargeted(sentry))
	{
		TurnPlayerIntoRandomRobot(client, ROBOT_SENTRYBUSTER);
		return;
	} */
	
	// bool bShouldBeGatebot = RollRandomChanceFloat(50.0);
	
	if (GetTeamClientCount(TFTeam_Red) >= bwr3_minmimum_players_for_giants.IntValue)
	{
		//TOOD: factor giant gatebots
		
		if (RollRandomChanceFloat(50.0))
		{
			TurnPlayerIntoRandomRobot(client, ROBOT_GIANT);
			return;
		}
	}
	
	/* if (bShouldBeGatebot)
	{
		TurnPlayerIntoRandomRobot(client, ROBOT_GATEBOT);
		return;
	} */
	
	TurnPlayerIntoRandomRobot(client, ROBOT_STANDARD);
}

void StopIdleSound(int client)
{
	//This is kinda dumb...
	StopSound(client, SNDCHAN_STATIC, SOUND_GIANT_HEAVY_LOOP);
	StopSound(client, SNDCHAN_STATIC, SOUND_GIANT_SOLDIER_LOOP);
	StopSound(client, SNDCHAN_STATIC, SOUND_GIANT_DEMOMAN_LOOP);
	StopSound(client, SNDCHAN_STATIC, SOUND_GIANT_SCOUT_LOOP);
	StopSound(client, SNDCHAN_STATIC, SOUND_GIANT_PYRO_LOOP);
	StopSound(client, SNDCHAN_STATIC, SOUND_SENTRYBUSTER_LOOP);
}

bool IsSentryBusterRobot(int client)
{
	if (IsPlayingAsRobot(client) && MvMRobotPlayer(client).HasMission(CTFBot_MISSION_DESTROY_SENTRIES))
		return true;
	
	//TODO: find a better way to determine if a tfbot is a sentry buster
	
	char modelName[PLATFORM_MAX_PATH]; GetClientModel(client, modelName, sizeof(modelName));
	
	return StrEqual(modelName, "models/bots/demo/bot_sentry_buster.mdl");
}

void SpyLeaveSpawnRoom_OnStart(int client)
{
	TF2_DisguiseAsMemberOfEnemyTeam(client);
	
	PressAltFireButton(client);
	
	CreateTimer(2.0 + GetRandomFloat(0.0, 1.0), Timer_SpyLeaveSpawnRoom, client, TIMER_FLAG_NO_MAPCHANGE);
	
	m_iSpyTeleportAttempt[client] = 0;
	
	SetPlayerToMove(client, false);
	
	// PrintToChat(client, "%s %t", PLUGIN_PREFIX, "Player_Spy_Teleporting");
}

void MvMEngineerTeleportSpawn(int client)
{
	int hintEntity = GetEngineerHint();
	
	if (hintEntity == -1)
	{
		LogError("MvMEngineerTeleportSpawn: No hint entities found within the map!");
		return;
	}
	
	DataPack pack;
	CreateDataTimer(0.1, Timer_MvMEngineerTeleportSpawn, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(client);
	pack.WriteCell(hintEntity);
	
	TF2_PushAllPlayersAway(GetAbsOrigin(hintEntity), 400.0, 500.0, TFTeam_Red);
}