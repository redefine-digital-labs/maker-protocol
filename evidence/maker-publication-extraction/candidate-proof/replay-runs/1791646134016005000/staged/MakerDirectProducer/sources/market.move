module maker_direct::market;
use sui::coin::Coin;
use sui::package::{Publisher,UpgradeCap};
use soulidity_foundation::economics::{Self,Config,Admin};
use soulidity_maker_terms::maker_resale::{Self,Snapshot,Receipt};
public struct MARKET has drop {}
public struct MarketAuthority1 has drop {}
public struct MarketRevision1 has drop {}
fun init(w:MARKET,ctx:&mut TxContext){sui::package::claim_and_keep(w,ctx)}
public fun register<C>(cfg:&mut Config<C>,a:&mut Admin,expected:u64,commitment:vector<u8>,p:&Publisher,cap:&UpgradeCap){economics::register_role(cfg,a,expected,commitment,3,MarketAuthority1{},MarketRevision1{},p,cap)}
public fun settle<C>(cfg:&mut Config<C>,rights:&Snapshot,receipt:Receipt,payment:Coin<C>,subject:ID,attempt:vector<u8>,ctx:&mut TxContext){maker_resale::settle(MarketAuthority1{},MarketRevision1{},cfg,rights,receipt,payment,subject,attempt,ctx)}
