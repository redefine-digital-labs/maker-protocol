module maker_direct::catalog;
use std::string::String;
use sui::coin::{Self,Coin};
use sui::clock::Clock;
use sui::package::{Publisher,UpgradeCap};
use soulidity_foundation::economics::{Self,Config,Admin,PrimaryReceipt};
use soulidity_foundation::revenue::{Self,Ledger};
use soulidity_standard::soul::{Self,Soul};
use soulidity_model::policy;
use soulidity_maker_admission::maker_issuance::{Self,Binding,Genesis,Contribution};
public struct CATALOG has drop {}
public struct CreatorAuthority1 has drop {}
public struct CreatorRevision1 has drop {}
public struct SoulProducer has drop {}
public struct Product<phantom C> has key,store{id:UID,version:u64,policy:vector<u8>,creator:address,income:Ledger<C>}
fun init(w:CATALOG,ctx:&mut TxContext){sui::package::claim_and_keep(w,ctx)}
public fun new<C>(version:u64,policy:vector<u8>,ctx:&mut TxContext):Product<C>{
    assert!(version>0,0);policy::assert_hash(&policy);let id=object::new(ctx);let income=revenue::new<C>(&id,ctx);Product{id,version,policy,creator:ctx.sender(),income}
}
public fun register<C>(cfg:&mut Config<C>,a:&mut Admin,expected:u64,commitment:vector<u8>,p:&Publisher,cap:&UpgradeCap){economics::register_role(cfg,a,expected,commitment,2,CreatorAuthority1{},CreatorRevision1{},p,cap)}
public fun mint<C>(p:&mut Product<C>,cfg:&mut Config<C>,binding:Binding,name:String,metadata:vector<u8>,attempt:vector<u8>,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):(Soul,Genesis,PrimaryReceipt){
    let root=soul::new(SoulProducer{},p,p.version,p.policy,name,ctx);
    let receipt=economics::route_primary(economics::primary_quote(&economics::primary_policy(cfg),cfg,coin::value(&payment),false,p.creator,object::id(&root),metadata,ctx.sender(),attempt,expiry),object::id(p));
    let residual=economics::collect_primary(cfg,CreatorAuthority1{},CreatorRevision1{},receipt,payment,clock,ctx);revenue::deposit(&p.id,&mut p.income,residual);
    let genesis=maker_issuance::authorize_genesis(cfg,CreatorAuthority1{},CreatorRevision1{},p,&root,binding,metadata,ctx);(root,genesis,receipt)
}
public fun contribute<C>(p:&mut Product<C>,cfg:&mut Config<C>,root:&Soul,metadata:vector<u8>,attempt:vector<u8>,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):Contribution{
    let receipt=economics::route_primary(economics::primary_quote(&economics::primary_policy(cfg),cfg,coin::value(&payment),false,p.creator,object::id(root),metadata,ctx.sender(),attempt,expiry),object::id(p));
    let residual=economics::collect_primary(cfg,CreatorAuthority1{},CreatorRevision1{},receipt,payment,clock,ctx);revenue::deposit(&p.id,&mut p.income,residual);
    maker_issuance::authorize_contribution(cfg,CreatorAuthority1{},CreatorRevision1{},p,root,p.version,metadata,receipt,ctx)
}
public fun income<C>(p:&Product<C>):u64{revenue::balance(&p.income)}
