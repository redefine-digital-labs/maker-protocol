/// Compatibility of source entry names only; the unpublished target uses leaf Account.
module soulidity_v1::custody;
use sui::kiosk::Kiosk;
use soulidity_custody::account::{Self as leaf,Account};
use soulidity_standard::soul::Soul;
use soulidity_foundation::economics::Config;
public fun new(ctx:&mut TxContext):(Kiosk,Account){leaf::new(ctx)}
public fun finalize(k:Kiosk,a:Account,ctx:&TxContext):ID{leaf::finalize(k,a,ctx)}
public fun create(ctx:&mut TxContext):ID{leaf::create(ctx)}
public fun owner(a:&Account):address{leaf::owner(a)}
public fun kiosk_id(a:&Account):ID{leaf::kiosk_id(a)}
public fun assert_access(k:&mut Kiosk,a:&mut Account,ctx:&TxContext){leaf::assert_access(k,a,ctx)}
public fun withdraw_profits(k:&mut Kiosk,a:&mut Account,amount:Option<u64>,ctx:&mut TxContext){leaf::withdraw_profits(k,a,amount,ctx)}
public fun deposit_soul<C>(k:&mut Kiosk,a:&mut Account,s:Soul,cfg:&Config<C>,expected:u64,ctx:&TxContext){leaf::deposit_soul(k,a,s,cfg,expected,ctx)}
public fun withdraw_soul(k:&mut Kiosk,a:&mut Account,id:ID,expected:u64,ctx:&TxContext){leaf::withdraw_soul(k,a,id,expected,ctx)}
