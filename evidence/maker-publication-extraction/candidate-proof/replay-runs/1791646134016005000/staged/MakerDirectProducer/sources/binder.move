module maker_direct::native_binding;
use soulidity_foundation::economics::{Self,Config,Admin};
use sui::package::{Publisher,UpgradeCap};
use soulidity_maker_admission::maker_issuance::{Self,Binding};
public struct NATIVE_BINDING has drop {}
public struct NativeInstaller1 has drop {}
public struct NativeRevision1 has drop {}
fun init(w:NATIVE_BINDING,ctx:&mut TxContext){sui::package::claim_and_keep(w,ctx)}
public fun register<C>(cfg:&mut Config<C>,a:&mut Admin,expected:u64,commitment:vector<u8>,p:&Publisher,cap:&UpgradeCap){economics::register_role(cfg,a,expected,commitment,0,NativeInstaller1{},NativeRevision1{},p,cap)}
public fun binding<C>(cfg:&Config<C>):Binding{maker_issuance::bind(cfg,NativeInstaller1{},NativeRevision1{},maker_direct::application_operator::operator())}

#[test_only]
public struct Catalog has key,store {id:UID}
#[test_only]
public fun initialize<C>(ctx:&mut TxContext){
    let (mut cfg,mut admin)=economics::new_config_for_testing<C>(1000,250,0,@0xf,ctx);
    economics::bootstrap_application_for_testing(&mut cfg,&mut admin,NativeInstaller1{},NativeRevision1{});
    let catalog=Catalog{id:object::new(ctx)};let h=vector::tabulate!(32,|_|1);
    let permit=economics::authorize_installation(&cfg,&mut admin,0,economics::commitment(&cfg),0,NativeInstaller1{},NativeRevision1{},&catalog,0,h);
    economics::install_native_initial_for_testing(&mut cfg,&mut admin,permit,catalog,h);economics::enable_initial_for_testing(&mut cfg);economics::share_config_for_testing(cfg,admin,ctx);
}
#[test_only]
public fun bad_operator<C>(cfg:&Config<C>):Binding{maker_issuance::bind(cfg,NativeInstaller1{},NativeRevision1{},false)}
