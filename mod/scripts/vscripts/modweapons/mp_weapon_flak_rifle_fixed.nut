untyped
global function MpWeaponFlakRifle_Init

void function MpWeaponFlakRifle_Init()
{
	#if SERVER
	AddDamageCallbackSourceID( eDamageSourceId.mp_weapon_vinson, OnDamagedTarget_FlakRifle )
	#endif
}

#if SERVER
void function OnDamagedTarget_FlakRifle( entity ent, var damageInfo )
{
	if ( !IsValid( ent ) )
		return

	entity attacker = DamageInfo_GetAttacker( damageInfo )

	if ( !IsValid( attacker ) )
		return

	entity inflictor = DamageInfo_GetInflictor( damageInfo )
	if( !IsValid( inflictor ) )
		return
	if( !inflictor.IsProjectile() )
		return

	if( !inflictor.IsProjectile() )
		return
	
	array<string> mods = inflictor.ProjectileGetMods()

	if( mods.contains( "flakrifle" ) )
	{
		PROTO_Flak_Rifle_DamagedPlayerOrNPC( ent, damageInfo )
	}
}
#endif