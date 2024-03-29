global function OnWeaponPrimaryAttack_ability_heal
global function OnProjectileCollision_ability_heal

global const STIM_EFFECT_SEVERITY_OCTANE = 0.25
const OCTANE_STIM_DAMAGE = 20

const JUMP_PAD_LIFETIME = 15
const REPAIR_DRONE_LIFETIME = 20

// not letting too much jump pads causes crash
const int MAX_JUMP_PAD_CONT = 64
struct JumpPadStruct
{
	entity tower
	entity projectile
}
array<JumpPadStruct> placedJumpPads
// not letting too much jump pads play sounds

var function OnWeaponPrimaryAttack_ability_heal( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	entity ownerPlayer = weapon.GetWeaponOwner()
	Assert( IsValid( ownerPlayer) && ownerPlayer.IsPlayer() )
	if ( IsValid( ownerPlayer ) && ownerPlayer.IsPlayer() )
	{
		if ( ownerPlayer.GetCinematicEventFlags() & CE_FLAG_CLASSIC_MP_SPAWNING )
			return false

		if ( ownerPlayer.GetCinematicEventFlags() & CE_FLAG_INTRO )
			return false
	}

	if( weapon.HasMod( "wrecking_ball" ) )
	{
		#if SERVER
		SendHudMessage(ownerPlayer, "投出破坏球", -1, -0.35, 255, 255, 100, 255, 0, 3, 0)
		#endif
		return OnWeaponPrimaryAttack_weapon_wrecking_ball( weapon, attackParams )
	}

	bool isDeployableThrow = weapon.HasMod("jump_pad") || weapon.HasMod("repair_drone")

	float duration = weapon.GetWeaponSettingFloat( eWeaponVar.fire_duration )
	if( isDeployableThrow )
	{
		entity deployable
		if( weapon.HasMod( "jump_pad" ) )
		{
			deployable = ThrowDeployable( weapon, attackParams, DEPLOYABLE_THROW_POWER, OnJumpPadPlanted )
			#if SERVER
			thread HolsterWeaponForPilotInstants( weapon )
			SendHudMessage(ownerPlayer, "扔出跳板", -1, -0.35, 255, 255, 100, 255, 0, 3, 0)
			#endif
		}
		else if( weapon.HasMod( "repair_drone" ) )
		{
			deployable = ThrowDeployable( weapon, attackParams, 100, OnRepairDroneReleased )
			#if SERVER
			thread HolsterWeaponForPilotInstants( weapon )
			SendHudMessage(ownerPlayer, "扔出维修无人机", -1, -0.35, 255, 255, 100, 255, 0, 3, 0)
			#endif
		}
		
		if ( deployable )
		{
			entity player = weapon.GetWeaponOwner()

			#if SERVER
			string projectileSound = GetGrenadeProjectileSound( weapon )
			if ( projectileSound != "" )
				EmitSoundOnEntity( deployable, projectileSound )

			weapon.w.lastProjectileFired = deployable
			#endif
		}
	}
	else if( weapon.HasMod("octane_stim") )
	{
		StimPlayer( ownerPlayer, duration, STIM_EFFECT_SEVERITY_OCTANE )
		#if SERVER
		thread OctaneStimThink( ownerPlayer, duration )
		#endif
	}
	else if( weapon.HasMod( "bc_super_stim" ) && weapon.HasMod( "dev_mod_low_recharge" ) )
		StimPlayer( ownerPlayer, duration, 0.15 )
	else
		StimPlayer( ownerPlayer, duration )

	PlayerUsedOffhand( ownerPlayer, weapon )

#if SERVER
#if BATTLECHATTER_ENABLED
	TryPlayWeaponBattleChatterLine( ownerPlayer, weapon )
#endif //
#else //
	Rumble_Play( "rumble_stim_activate", {} )
#endif //

	return weapon.GetWeaponSettingInt( eWeaponVar.ammo_min_to_fire )
}

void function OnProjectileCollision_ability_heal( entity projectile, vector pos, vector normal, entity hitEnt, int hitbox, bool isCritical )
{
	array<string> mods = projectile.ProjectileGetMods()
	if( mods.contains( "wrecking_ball" ) )
		return OnProjectileCollision_weapon_wrecking_ball( projectile, pos, normal, hitEnt, hitbox, isCritical )
	else
		return OnProjectileCollision_weapon_deployable( projectile, pos, normal, hitEnt, hitbox, isCritical )
}

void function OnJumpPadPlanted( entity projectile )
{
	#if SERVER
	Assert( IsValid( projectile ) )
	vector origin = projectile.GetOrigin()

	vector endOrigin = origin - Vector( 0.0, 0.0, 32.0 )
	vector surfaceAngles = projectile.proj.savedAngles
	vector oldUpDir = AnglesToUp( surfaceAngles )

	TraceResults traceResult = TraceLine( origin, endOrigin, [], TRACE_MASK_SOLID, TRACE_COLLISION_GROUP_NONE )
	if ( traceResult.fraction < 1.0 )
	{
		vector forward = AnglesToForward( projectile.proj.savedAngles )
		surfaceAngles = AnglesOnSurface( traceResult.surfaceNormal, forward )

		vector newUpDir = AnglesToUp( surfaceAngles )
		if ( DotProduct( newUpDir, oldUpDir ) < 0.55 )
			surfaceAngles = projectile.proj.savedAngles
	}

	projectile.SetAngles( surfaceAngles )

	DeployJumpPad( projectile, origin, surfaceAngles )
	#endif
}

void function OnRepairDroneReleased( entity projectile )
{
	#if SERVER
	entity drone = SpawnRepairDrone( projectile.GetTeam(), projectile.GetOrigin(), < 0,0,0 >, projectile.GetOwner() )
	thread AfterTimeDestroyDrone( drone, projectile.GetOwner(), REPAIR_DRONE_LIFETIME )
	projectile.GrenadeExplode( < 0,0,20 > )
	#endif
}

#if SERVER
void function DeployJumpPad( entity projectile, vector origin, vector angles )
{
	#if SERVER
	int team = projectile.GetTeam()
	entity tower = CreateEntity( "prop_dynamic" )
	tower.SetModel( $"models/weapons/sentry_shield/sentry_shield_proj.mdl" )
	tower.SetOrigin( origin )
	tower.SetAngles( angles )
	tower.kv.modelscale = 4

	array<string> mods = projectile.ProjectileGetMods()
	if( mods.contains( "infinite_jump_pad" ) )
	{
		JumpPadStruct placedJumpPad
		placedJumpPad.tower = tower
		placedJumpPad.projectile = projectile
		placedJumpPads.append( placedJumpPad )
		JumpPadLimitThink()
	}

	thread JumpPadThink( projectile, tower )

	// grunt mode specifics!
	if ( mods.contains( "gm_jumper" ) )
		thread DestroyJumpPadOnOwnerDeath( projectile, projectile.GetOwner() )
	if( !mods.contains( "infinite_jump_pad" ) )
		thread CleanupJumpPad( tower, projectile, JUMP_PAD_LIFETIME )
	#endif
}

void function JumpPadThink( entity projectile, entity tower )
{
	projectile.EndSignal( "OnDestroy" )
	tower.EndSignal( "OnDestroy" )
	entity trigger = CreateEntity( "trigger_cylinder" )
	trigger.SetRadius( 64 )
	trigger.SetAboveHeight( 24 )
	trigger.SetBelowHeight( 0 )
	trigger.SetOrigin( tower.GetOrigin() )
	SetTeam( trigger, tower.GetTeam() )
	DispatchSpawn( trigger )

	trigger.EndSignal( "OnDestroy" )

	trigger.SearchForNewTouchingEntity() //JFS: trigger.GetTouchingEntities() will not return entities already in the trigger unless this is called. See bug 202843

	OnThreadEnd(
		function(): ( projectile, tower, trigger )
		{
			if ( IsValid( projectile ) )
				projectile.GrenadeExplode( projectile.GetForwardVector() )
			if( IsValid( tower ) )
				tower.Destroy()
			if( IsValid( trigger ) )
				trigger.Destroy()
		}
	)

	while( true )
	{
		array<entity> touchingEnts = trigger.GetTouchingEntities()

		foreach( entity ent in touchingEnts )
		{
			GiveJumpPadEffect( trigger, ent )
			//ScriptTriggerRemoveEntity( trigger, ent ) // don't remove since we are checking entities touching
		}

		WaitFrame()
	}
}

void function GiveJumpPadEffect( entity trigger, entity player )
{
	if( !IsValid( player ) )
		return
	if( !player.IsPlayer() )
		return
	if( player.GetParent() != null )
		return
	if( player.IsTitan() )
		return
	if( IsPlayerInJumpPadCooldown( player ) )
		return

	StopSoundOnEntity( player, "Boost_Card_SentryTurret_Deployed_3P" ) // prevent sound stacking
	for( int i = 0; i < 5; i++ )
		EmitSoundOnEntity( player, "Boost_Card_SentryTurret_Deployed_3P" )

	vector targetVelocity
	if( player.IsInputCommandHeld( IN_DUCK ) || player.IsInputCommandHeld( IN_DUCKTOGGLE ) ) // further but lower
		targetVelocity = < player.GetVelocity().x * 1.5, player.GetVelocity().y * 1.5, 550 >
	else // higher
		targetVelocity = < player.GetVelocity().x * 1.3, player.GetVelocity().y * 1.3, 750 >
	thread JumpPadForcedVelocity( player, targetVelocity ) // prevent jump higher through manually jump input

	player.TouchGround() // regen doublejump

	thread JumpPadFlying( player ) // signal sender
	thread JumpPadCooldownThink( player )
	thread JumpPadTrailThink( player )
	thread JumpPadTripleJumpThink( player )
	Remote_CallFunction_Replay( player, "ServerCallback_ScreenShake", 5, 10, 0.5 )
}

void function JumpPadFlying( entity player )
{
	player.EndSignal( "OnDeath" )
	player.EndSignal( "OnDestroy" )
	player.Signal( "JumpPadFlyStart" )
	player.EndSignal( "JumpPadFlyStart" )

	OnThreadEnd(
		function(): ( player )
		{
			if( IsValid( player ) )
				player.Signal( "JumpPadPlayerTouchGround" )
		}
	)

	wait 1 // wait for player leave ground

	while( true )
	{
		if( player.IsOnGround() )
			break

		WaitFrame()
	}
}

void function JumpPadForcedVelocity( entity player, vector targetVelocity )
{
	player.EndSignal( "OnDeath" )
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "JumpPadPlayerTouchGround" )
	player.Signal( "JumpPadForcedVelocityStart" )
	player.EndSignal( "JumpPadForcedVelocityStart" )

	float forcedTime = 0.2
	float startTime = Time()
	while( Time() < startTime + forcedTime )
	{
		player.SetVelocity( targetVelocity )
		WaitFrame()
	}
}

void function JumpPadTripleJumpThink( entity player )
{
	player.EndSignal( "OnDeath" )
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "JumpPadPlayerTouchGround" )
	player.EndSignal( "JumpPadGainTripleJump" )
	player.Signal( "JumpPadTripleJumpThinkStart" )
	player.EndSignal( "JumpPadTripleJumpThinkStart" )

	OnThreadEnd(
		function(): ( player )
		{
			if( IsValid( player ) )
				RemovePlayerMovementEventCallback( player, ePlayerMovementEvents.DOUBLE_JUMP, RegenDoubleJump )
		}
	)

	AddPlayerMovementEventCallback( player, ePlayerMovementEvents.DOUBLE_JUMP, RegenDoubleJump )

	WaitForever()
}

void function RegenDoubleJump( entity player )
{
	player.TouchGround()
	player.Signal( "JumpPadGainTripleJump" )
}

void function JumpPadTrailThink( entity player )
{
	player.EndSignal( "OnDeath" )
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "JumpPadPlayerTouchGround" )
	player.Signal( "JumpPadTrailStart" )
	player.EndSignal( "JumpPadTrailStart" )

	array<entity> jumpJetFX

	OnThreadEnd(
		function(): ( jumpJetFX )
		{
			foreach( entity fx in jumpJetFX )
			{
				if( IsValid( fx ) )
					EffectStop( fx )
			}
		}
	)

	// enemy left vent fx, // "vent_left_out" "vent_right_out" direction is a little bit weird
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_enemy_jump_jet_DBL", "vent_left", false ) )
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_enemy_jump_jet_ON_trails", "vent_left", false ) )
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_enemy_jump_jet_ON", "vent_left", false ) )
	// enemy right vent fx
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_enemy_jump_jet_DBL", "vent_right", false ) )
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_enemy_jump_jet_ON_trails", "vent_right", false ) )
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_enemy_jump_jet_ON", "vent_right", false ) )
	// enemy center vent fx
	// this can be too big!! maybe use it for flame throwers?
	//jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_enemy_jump_jet_center_DBL", "vent_center", false ) )

	// friendly left vent fx, "P_team_jump_jet_WR_trails" is more visible with some transparent flames
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_team_jump_jet_DBL", "vent_left", true ) )
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_team_jump_jet_ON_trails", "vent_left", true ) )
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_team_jump_jet_ON", "vent_left", true ) )
	// friendly right vent fx
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_team_jump_jet_DBL", "vent_right", true ) )
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_team_jump_jet_ON_trails", "vent_right", true ) )
	jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_team_jump_jet_ON", "vent_right", true ) )
	// friendly center vent fx
	// this can be too big!! maybe use it for flame throwers?
	//jumpJetFX.append( CreateJumpPadJetFxForPlayer( player, $"P_team_jump_jet_center_DBL", "vent_center", true ) )

	WaitForever()
	
}

entity function CreateJumpPadJetFxForPlayer( entity player, asset particle, string attachment, bool isFriendly )
{
	int particleID = GetParticleSystemIndex( particle )
	int attachID = player.LookupAttachment( attachment )
	if( attachID <= 0 ) // no attachment valid, don't play fx on this model
		return null
	entity fx = StartParticleEffectOnEntity_ReturnEntity( player, particleID, FX_PATTACH_POINT_FOLLOW, attachID )
	fx.SetOwner( player )
	SetTeam( fx, player.GetTeam() )
	if( isFriendly ) // removed: player can see friendly fx( blue flames and trails )
		fx.kv.VisibilityFlags = ENTITY_VISIBLE_TO_FRIENDLY // | ENTITY_VISIBLE_TO_OWNER // this might get annoying!
	else
		fx.kv.VisibilityFlags = ENTITY_VISIBLE_TO_ENEMY

	return fx
}

void function JumpPadCooldownThink( entity player )
{
	SetPlayerInJumpPadCooldown( player, 1.0 ) // hardcoded now
}

void function DestroyJumpPadOnOwnerDeath( entity projectile, entity owner )
{
	projectile.EndSignal( "OnDestroy" )
	owner.EndSignal( "OnDestroy" )
	owner.EndSignal( "OnDeath" )

	OnThreadEnd(
		function(): ( projectile )
		{
			if ( IsValid( projectile ) )
				projectile.GrenadeExplode( projectile.GetForwardVector() )
		}
	)

	WaitForever()
}

void function CleanupJumpPad( entity tower, entity projectile, float delay )
{
	wait delay
	if( IsValid(tower) )
		tower.Destroy()
	if( IsValid(projectile) )
		projectile.GrenadeExplode(< 0,0,10 >)
}

void function AfterTimeDestroyDrone( entity drone, entity owner, float delay )
{
	owner.EndSignal( "OnDeath" )
	owner.EndSignal( "OnDestroy" )

	OnThreadEnd(
		function() : ( drone )
		{
			if( IsValid( drone ) )
				drone.SetHealth( 0 )
		}
	)
	
	wait delay
}

void function JumpPadLimitThink()
{
	if( placedJumpPads.len() >= MAX_JUMP_PAD_CONT )
	{
		JumpPadStruct curJumpPad = placedJumpPads[0]
		if( IsValid( curJumpPad.tower ) )
			curJumpPad.tower.Destroy()
		if( IsValid( curJumpPad.projectile ) )
			curJumpPad.projectile.GrenadeExplode(< 0,0,10 >)
		placedJumpPads.remove(0)
	}
}

// low recharge stim, disables health regen while activating, less speed boost, with long duration almost no cooldown
void function OctaneStimThink( entity player, float duration )
{
	player.EndSignal( "OnDeath" )
	player.EndSignal( "OnDestroy" )
	player.Signal( "OctaneStimStart" )
	player.EndSignal( "OctaneStimStart" )
	OnThreadEnd(
		function(): ( player )
		{
			if( IsValid( player ) )
			{
				player.SetOneHandedWeaponUsageOff()
			}
		}
	)
	float startTime = Time()
	player.TakeDamage( player.GetHealth() - OCTANE_STIM_DAMAGE < 1 ? 1 : OCTANE_STIM_DAMAGE, player, player, { damageSourceId = eDamageSourceId.bleedout } )
	while( true )
	{
		wait 0.1
		if( IsValid( player ) )
		{
			player.p.lastDamageTime = Time()
			player.SetOneHandedWeaponUsageOn()
		}
		if( Time() >= startTime + duration )
		{
			if( IsValid( player ) )
				player.p.lastDamageTime = Time() - 5
			return
		}
	}
}
#endif
