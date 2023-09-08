untyped
global function GamemodePs_Init
//global function RateSpawnpoints_SpawnZones

struct {
	array<entity> spawnzones
	
	entity militiaActiveSpawnZone
	entity imcActiveSpawnZone
	
	array<entity> militiaPreviousSpawnZones
	array<entity> imcPreviousSpawnZones
} file

void function GamemodePs_Init()
{
	Riff_ForceTitanAvailability( eTitanAvailability.Never )

	AddCallback_OnPlayerKilled( GiveScoreForPlayerKill )
	ScoreEvent_SetupEarnMeterValuesForMixedModes()
	AddCallback_GameStateEnter( eGameState.Prematch, SetUpPilotSkirmishScoreEvent ) // northstar missing
	SetTimeoutWinnerDecisionFunc( CheckScoreForDraw )

	// spawnzone stuff
	SetShouldCreateMinimapSpawnZones( true )
	
	//AddCallback_OnPlayerKilled( CheckSpawnzoneSuspiciousDeaths )
	//AddSpawnCallbackEditorClass( "trigger_multiple", "trigger_mp_spawn_zone", SpawnzoneTriggerInit )
	
	file.militiaPreviousSpawnZones = [ null, null, null ]
	file.imcPreviousSpawnZones = [ null, null, null ]

	// nscn specifics
	SetShouldPlayDefaultMusic( true )
}

// northstar missing
void function SetUpPilotSkirmishScoreEvent()
{
	// pilot kill
	ScoreEvent_SetEarnMeterValues( "KillPilot", 0.1, 0.1, 0.5 )
	// special method of killing
	ScoreEvent_SetEarnMeterValues( "Headshot", 0.0, 0.02, 0.0 )
}

void function GiveScoreForPlayerKill( entity victim, entity attacker, var damageInfo )
{
	if ( victim != attacker && victim.IsPlayer() && attacker.IsPlayer() || GetGameState() != eGameState.Playing )
		AddTeamScore( attacker.GetTeam(), 1 )
}

int function CheckScoreForDraw()
{
	if ( GameRules_GetTeamScore( TEAM_IMC ) > GameRules_GetTeamScore( TEAM_MILITIA ) )
		return TEAM_IMC
	else if ( GameRules_GetTeamScore( TEAM_MILITIA ) > GameRules_GetTeamScore( TEAM_IMC ) )
		return TEAM_MILITIA

	return TEAM_UNASSIGNED
}