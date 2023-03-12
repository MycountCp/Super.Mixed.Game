global function TeamShuffle_Init

array<string> disabledGamemodes_Shuffle = ["private_match"]
array<string> disabledGamemodes_Balance = ["private_match"]
array<string> disabledMaps = ["mp_lobby"]

const int BALANCE_ALLOWED_TEAM_DIFFERENCE = 1
bool hasShuffled = false

void function TeamShuffle_Init()
{
	AddCallback_GameStateEnter( eGameState.Prematch, ShuffleTeams )
	AddCallback_OnClientDisconnected( CheckPlayerDisconnect )
	// viper battle compatible
	//if( !(GAMETYPE == "tdm" && GetMapName() == "mp_forwardbase_kodai") )
	//	AddCallback_OnPlayerKilled( CheckTeamBalance )
	AddCallback_OnPlayerKilled( CheckTeamBalance )
	AddClientCommandCallback( "switch", CC_TrySwitchTeam )
}

bool function CC_TrySwitchTeam( entity player, array<string> args )
{
	// Check if the gamemode or map are on the blacklist
	bool gamemodeDisable = disabledGamemodes_Balance.contains(GAMETYPE) || IsFFAGame();
	bool mapDisable = disabledMaps.contains(GetMapName());

	// Blacklist guards
  	if ( gamemodeDisable )
	{
    	Chat_ServerPrivateMessage( player, "当前模式不可切换队伍", false ) // chathook has been fucked up
		return true
	}

  	if ( mapDisable )
    {
    	Chat_ServerPrivateMessage( player, "当前地图", false ) // chathook has been fucked up
		return true
	}
	
	if ( GetPlayerArray().len() == 1 )
	{
    	Chat_ServerPrivateMessage( player, "人数不足，不可切换队伍", false ) // chathook has been fucked up
		return true
	}

	// Check if difference is smaller than 2 ( dont balance when it is 0 or 1 )
	if( abs ( GetPlayerArrayOfTeam( TEAM_IMC ).len() - GetPlayerArrayOfTeam( TEAM_MILITIA ).len() ) <= BALANCE_ALLOWED_TEAM_DIFFERENCE )
	{
    	Chat_ServerPrivateMessage( player, "队伍已平衡，不可切换队伍", false ) // chathook has been fucked up
		return true
	}

	int oldTeam = player.GetTeam()
	SetTeam( player, GetOtherTeam( player.GetTeam() ) )
	Chat_ServerPrivateMessage( player, "已切换队伍", false )
	thread WaitForPlayerRespawnThenNotify( player )
	NotifyClientsOfTeamChange( player, oldTeam, player.GetTeam() )
	if( IsAlive( player ) ) // poor guy
	{
		player.Die( null, null, { damageSourceId = eDamageSourceId.team_switch } ) // better
		if ( player.GetPlayerGameStat( PGS_DEATHS ) >= 1 ) // reduce the death count
			player.AddToPlayerGameStat( PGS_DEATHS, -1 )
	}
	if( !RespawnsEnabled() ) // do need respawn the guy if respawnsdisabled
		RespawnAsPilot( player )

	return true
}

void function CheckPlayerDisconnect( entity player )
{
	// general check
  	if ( !CanChangeTeam() )
		return

	int weakTeam = GetPlayerArrayOfTeam( TEAM_IMC ).len() > GetPlayerArrayOfTeam( TEAM_MILITIA ).len() ? TEAM_MILITIA : TEAM_IMC
	foreach ( entity player in GetPlayerArrayOfTeam( GetOtherTeam( weakTeam ) ) )
		Chat_ServerPrivateMessage( player, "队伍当前不平衡，可通过控制台输入switch切换队伍", false )
}

void function ShuffleTeams()
{
	TeamShuffleThink()
	bool disabledClassicMP = !GetClassicMPMode() && !ClassicMP_ShouldTryIntroAndEpilogueWithoutClassicMP()
	//print( "disabledClassicMP: " + string( disabledClassicMP ) )
	if ( disabledClassicMP )
	{
		WaitFrame() // do need wait before shuffle
		FixShuffle()
	}
	else if( ClassicMP_GetIntroLength() < 1 )
	{
		FixShuffle()
		WaitFrame() // do need wait to make things shuffled
	}
	else if( ClassicMP_GetIntroLength() >= 5 )
		thread FixShuffle( ClassicMP_GetIntroLength() - 0.5 ) // fix shuffle
}

void function TeamShuffleThink()
{
	if( hasShuffled )
		return
	// Check if the gamemode or map are on the blacklist
	bool gamemodeDisable = disabledGamemodes_Shuffle.contains(GAMETYPE) || IsFFAGame();
	bool mapDisable = disabledMaps.contains(GetMapName());

  	if ( gamemodeDisable )
    	return
  
  	if ( mapDisable )
    	return
    
 	if ( GetPlayerArray().len() == 0 )
    	return
  
  	// Set team to TEAM_UNASSIGNED
  	foreach ( player in GetPlayerArray() )
    	SetTeam ( player, TEAM_UNASSIGNED )
  
  	int maxTeamSize = GetPlayerArray().len() / 2
  
  	// Assign teams
  	foreach ( player in GetPlayerArray() )
  	{
    	if( !IsValid( player ) )
      		continue
    
    	// Get random team
    	int team = RandomIntRange( TEAM_IMC, TEAM_MILITIA + 1 )
    	// Gueard for team size
    	if ( GetPlayerArrayOfTeam( team ).len() >= maxTeamSize )
    	{
      		SetTeam( player, GetOtherTeam( team ) )
      			continue
    	}
    // 
    	SetTeam( player, team )
	}
	hasShuffled = true
}

void function FixShuffle( float delay = 0 )
{
	if( delay > 0 )
		wait delay

	bool gamemodeDisable = disabledGamemodes_Shuffle.contains(GAMETYPE) || IsFFAGame();
	bool mapDisable = disabledMaps.contains(GetMapName());

  	if ( gamemodeDisable )
    	return
  
  	if ( mapDisable )
    	return

	int mltTeamSize = GetPlayerArrayOfTeam( TEAM_MILITIA ).len()
	int imcTeamSize = GetPlayerArrayOfTeam( TEAM_IMC ).len()
	int teamSizeDifference = abs( mltTeamSize - imcTeamSize )
  	if( teamSizeDifference <= BALANCE_ALLOWED_TEAM_DIFFERENCE )
		return
	
	if ( GetPlayerArray().len() == 1 )
		return

	int timeShouldBeDone = teamSizeDifference - BALANCE_ALLOWED_TEAM_DIFFERENCE
	int largerTeam = imcTeamSize > mltTeamSize ? TEAM_IMC : TEAM_MILITIA
	array<entity> largerTeamPlayers = GetPlayerArrayOfTeam( largerTeam )
	
	int largerTeamIndex = 0
	entity poorGuy
	int oldTeam
	for( int i = 0; i < timeShouldBeDone; i ++ )
	{
		poorGuy = largerTeamPlayers[ largerTeamIndex ]
		largerTeamIndex += 1

		if( IsAlive( poorGuy ) ) // poor guy
		{
			poorGuy.Die( null, null, { damageSourceId = eDamageSourceId.team_switch } ) // better
			if ( poorGuy.GetPlayerGameStat( PGS_DEATHS ) >= 1 ) // reduce the death count
				poorGuy.AddToPlayerGameStat( PGS_DEATHS, -1 )
		}
		int oldTeam = poorGuy.GetTeam()
		SetTeam( poorGuy, GetOtherTeam( largerTeam ) )
		if( !RespawnsEnabled() ) // do need respawn the guy if respawnsdisabled
			RespawnAsPilot( poorGuy )
	}
	if( IsValid( poorGuy ) )
	{ // only notice once
		Chat_ServerPrivateMessage( poorGuy, "由于队伍人数不平衡，你已被重新分队", false )
		thread WaitForPlayerRespawnThenNotify( poorGuy )
		NotifyClientsOfTeamChange( poorGuy, oldTeam, poorGuy.GetTeam() ) 
	}
}

void function WaitForPlayerRespawnThenNotify( entity player )
{
	player.EndSignal( "OnDestroy" )

	player.WaitSignal( "OnRespawned" )
	NSSendInfoMessageToPlayer( player, "由於隊伍人數不平衡，你已被重新分隊" )
}

void function CheckTeamBalance( entity victim, entity attacker, var damageInfo )
{  
	// general check
  	if ( !CanChangeTeam() )
		return
	
	// Compare victims teams size
	if ( GetPlayerArrayOfTeam( victim.GetTeam() ).len() < GetPlayerArrayOfTeam( GetOtherTeam( victim.GetTeam() ) ).len() )
		return
	
	// We passed all checks, balance the teams
	int oldTeam = victim.GetTeam()
	SetTeam( victim, GetOtherTeam( victim.GetTeam() ) )
	Chat_ServerPrivateMessage( victim, "由于队伍人数不平衡，你已被重新分队", false )
	thread WaitForPlayerRespawnThenNotify( victim )
	NotifyClientsOfTeamChange( victim, oldTeam, victim.GetTeam() )
}

bool function CanChangeTeam()
{
	// Check if the gamemode or map are on the blacklist
	bool gamemodeDisable = disabledGamemodes_Balance.contains(GAMETYPE) || IsFFAGame();
	bool mapDisable = disabledMaps.contains(GetMapName());

	// Blacklist guards
  	if ( gamemodeDisable )
    	return false
  
  	if ( mapDisable )
    	return false
  
	// Check if difference is smaller than 2 ( dont balance when it is 0 or 1 )
	// May be too aggresive ??
	if( abs ( GetPlayerArrayOfTeam( TEAM_IMC ).len() - GetPlayerArrayOfTeam( TEAM_MILITIA ).len() ) <= BALANCE_ALLOWED_TEAM_DIFFERENCE )
		return false
	
	if ( GetPlayerArray().len() == 1 )
		return false

	return true
}
	

/* // pandora version
bool function ClientCommand_SwitchTeam( entity player, array<string> args )
{
	if( !IsValid( player ) )
		return false

	int PlayerTeam = player.GetTeam()
	int EnemyTeam = GetEnemyTeam( PlayerTeam )
	entity PetTitan = player.GetPetTitan()
	string PlayerFaction = GetFactionChoice( player )
	string EnemyFaction = GetEnemyFaction( player )
	int PlayerTeamCount = GetPlayerArrayOfTeam( PlayerTeam ).len()
    	int EnemyTeamCount = GetPlayerArrayOfTeam( EnemyTeam ).len()
	int MaxPlayers = GetGamemodeVarOrUseValue( GetConVarString( "ns_private_match_last_mode" ), "max_players", "12" ).tointeger()
	
	if( PlayerTeam != TEAM_MILITIA && PlayerTeam != TEAM_IMC )
	{
		SendHudMessage( player, "#PATCH_BLANK", -1, 0.33, 192, 255, 0, 255, 0.0, 3.0, 0.0 )
		return false
	}
	
	if( PlayerTeamCount + EnemyTeamCount >= MaxPlayers )
	{
		SendHudMessage( player, "#PRIVATE_MATCH_NOT_READY_TEAMS", -1, 0.33, 192, 255, 0, 255, 0.0, 3.0, 0.0 )
		return false
	}

	if( EnemyTeamCount - PlayerTeamCount > 1 )
	{
		SendHudMessage( player, "#PRIVATE_MATCH_NOT_READY_TEAMS", -1, 0.33, 192, 255, 0, 255, 0.0, 3.0, 0.0 )
		return false
	}
	
	if( IsAlive( player ) )
	{
		SendHudMessage( player, "#CONVO_S2S_WELLIMNOTDEAD", -1, 0.33, 192, 255, 0, 255, 0.0, 3.0, 0.0 )
		return false
		/ayer.Die( svGlobal.worldspawn, svGlobal.worldspawn, { damageSourceId = eDamageSourceId.team_switch } )
	}

	if( IsValid( PetTitan ) && player.IsTitan() )
	{
		SendHudMessage( player, "#CONVO_S2S_WELLIMNOTDEAD", -1, 0.33, 192, 255, 0, 255, 0.0, 3.0, 0.0 )
		return false
	}
	else if( IsValid( PetTitan ) && !player.IsTitan() )
	{
		//Kill that auto titan
		PetTitan.Die( svGlobal.worldspawn, svGlobal.worldspawn, { damageSourceId = eDamageSourceId.team_switch } )
	}
	
	if( PlayerTeam == TEAM_IMC )
	{
		SetTeam( player, TEAM_MILITIA )
	}
	else if( PlayerTeam == TEAM_MILITIA )
	{
		SetTeam( player, TEAM_IMC )
	}

	player.SetPersistentVar( "factionChoice", EnemyFaction )
	player.SetPersistentVar( "enemyFaction", PlayerFaction )

	SendHudMessage( player, "#SWITCH_TEAMS", -1, 0.33, 192, 255, 0, 255, 0.0, 3.0, 0.0 )
	return true
}
*/