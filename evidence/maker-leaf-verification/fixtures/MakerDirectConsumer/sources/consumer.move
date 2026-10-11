module maker_consumer::admission_consumer;
use std::string::String;
use std::type_name::TypeName;
use sui::coin::Coin;
use sui::clock::Clock;
use soulidity_standard::soul::Soul;
use soulidity_foundation::economics::{Self,Config,PrimaryReceipt};
use maker_direct::catalog::{Self,Product};
use maker_direct::native_binding;
use soulidity_maker_admission::maker_issuance;
use soulidity_maker_terms::maker_resale::{Self,Snapshot,Receipt};
public fun create<C>(p:&mut Product<C>,cfg:&mut Config<C>,name:String,metadata:vector<u8>,attempt:vector<u8>,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):(Soul,TypeName,PrimaryReceipt){
    let binding=native_binding::binding(cfg);let (root,g,receipt)=catalog::mint(p,cfg,binding,name,metadata,attempt,expiry,payment,clock,ctx);
    let (config,operator)=maker_issuance::consume_genesis(g,&root,metadata,ctx);assert!(config==object::id(cfg),0);(root,operator,receipt)
}
public fun complete<C>(p:&mut Product<C>,cfg:&mut Config<C>,root:&Soul,metadata:vector<u8>,attempt:vector<u8>,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):(ID,u64,vector<u8>,PrimaryReceipt){
    let contribution=catalog::contribute(p,cfg,root,metadata,attempt,expiry,payment,clock,ctx);maker_issuance::consume_contribution(contribution,root,ctx)
}
public fun quote<C>(rights:&Snapshot,cfg:&Config<C>,gross:u64,seller:address):Receipt{maker_resale::quote_gross(rights,cfg,gross,seller)}
public fun settle<C>(rights:&Snapshot,cfg:&mut Config<C>,receipt:Receipt,payment:Coin<C>,subject:ID,attempt:vector<u8>,ctx:&mut TxContext){maker_direct::market::settle(cfg,rights,receipt,payment,subject,attempt,ctx)}
