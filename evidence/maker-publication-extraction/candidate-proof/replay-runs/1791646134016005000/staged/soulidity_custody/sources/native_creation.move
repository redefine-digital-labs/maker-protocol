/// Thin adapter for the existing sealed Account. Native business logic lives
/// in its independent producer package, not in this custody bridge.
module soulidity_custody::creation;
use sui::kiosk::Kiosk;
use sui::clock::Clock;
use sui::transfer_policy::TransferPolicy;
use std::string::String;
use walrus::system::System;
use soulidity_foundation::economics::Config;
use soulidity_standard::soul::Soul;
use soulidity_native::registry::{Self,Registry,Claim};
use soulidity_native::birth::{Self,Draft};
use soulidity_custody::account::{Self as custody,Account};

public fun register<C>(r:&mut Registry,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,ctx:&TxContext){
    custody::assert_access(k,a,ctx);registry::register_personal_kiosk(r,cfg,k,custody::cap(a),ctx)
}
public fun place_source<C,T:key+store>(r:&Registry,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,source:T,ctx:&TxContext):ID{
    custody::assert_access(k,a,ctx);registry::place_source(r,cfg,k,custody::cap(a),source,ctx)
}
public fun prepare_native<C>(r:&mut Registry,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,nonce:vector<u8>,expected:ID,ctx:&TxContext):Claim{
    custody::assert_access(k,a,ctx);registry::prepare_native(r,cfg,k,custody::cap(a),nonce,expected,ctx)
}
public fun prepare_imported<C>(r:&mut Registry,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,origin:String,nonce:vector<u8>,expected:ID,ctx:&TxContext):Claim{
    custody::assert_access(k,a,ctx);registry::prepare_imported(r,cfg,k,custody::cap(a),origin,nonce,expected,ctx)
}
public fun prepare_joined<C,T:key+store>(r:&mut Registry,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,source:ID,origin:String,nonce:vector<u8>,expected:ID,ctx:&TxContext):Claim{
    custody::assert_access(k,a,ctx);registry::prepare_joined<C,T>(r,cfg,k,custody::cap(a),source,origin,nonce,expected,ctx)
}
public fun begin<C>(claim:Claim,r:&mut Registry,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,
    name:String,description:String,image:String,royalty:u16,keys:vector<String>,values:vector<vector<u8>>,clock:&Clock,ctx:&mut TxContext):Draft{
    custody::assert_access(k,a,ctx);birth::begin(claim,r,cfg,k,custody::cap(a),name,description,image,royalty,keys,values,clock,ctx)
}
public fun finish<C>(d:Draft,r:&Registry,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,p:&TransferPolicy<Soul>,system:&System,ctx:&mut TxContext):ID{
    custody::assert_access(k,a,ctx);birth::finish(d,r,cfg,k,custody::cap(a),p,system,ctx)
}
