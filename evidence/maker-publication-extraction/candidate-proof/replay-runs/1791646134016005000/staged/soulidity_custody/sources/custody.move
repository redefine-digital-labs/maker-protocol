/// Certified personal Kiosk. Its native owner cap never leaves this wallet capability.
module soulidity_custody::account;
use sui::kiosk::{Self,Kiosk,KioskOwnerCap};
use sui::coin::Coin;
use sui::sui::SUI;
use soulidity_application::character::{Self as soul};
use soulidity_standard::soul::Soul;
use soulidity_foundation::economics::Config;
use soulidity_application::vault;
const EOwner:u64=1;const EBinding:u64=2;
public struct Account has key {id:UID,kiosk:ID,owner:address,cap:KioskOwnerCap}
/// Return owned values so the first purchase can use its new account in the
/// same PTB. Account has no store/drop and never exposes the native owner cap.
public fun new(ctx:&mut TxContext):(Kiosk,Account) {
    let(k,cap)=kiosk::new(ctx);let id=object::id(&k);
    (k,Account{id:object::new(ctx),kiosk:id,owner:ctx.sender(),cap})
}
/// Persist the exact pair only after its operations succeed. Its owner is
/// fixed by new(); this cannot transfer an account to an arbitrary recipient.
public fun finalize(mut k:Kiosk,mut a:Account,ctx:&TxContext):ID {
    assert_access(&mut k,&mut a,ctx);let id=object::id(&k);
    transfer::public_share_object(k);transfer::transfer(a,ctx.sender());id
}
public fun create(ctx:&mut TxContext):ID {let(k,a)=new(ctx);finalize(k,a,ctx)}
public fun owner(a:&Account):address{a.owner}
public fun kiosk_id(a:&Account):ID{a.kiosk}
public fun assert_access(k:&mut Kiosk,a:&mut Account,ctx:&TxContext) {
    assert_pair(k,a,ctx)
}
fun assert_pair(k:&mut Kiosk,a:&Account,ctx:&TxContext) {
    assert!(a.owner==ctx.sender(),EOwner);assert!(a.kiosk==object::id(k) && kiosk::owner(k)==a.owner && kiosk::has_access(k,&a.cap),EBinding)
}
public(package) fun cap(a:&Account):&KioskOwnerCap{&a.cap}
public fun withdraw_profits(k:&mut Kiosk,a:&mut Account,amount:Option<u64>,ctx:&mut TxContext) {
    assert_access(k,a,ctx);let profits:Coin<SUI> = kiosk::withdraw(k,&a.cap,amount,ctx);transfer::public_transfer(profits,ctx.sender())
}
public fun deposit_soul<C>(k:&mut Kiosk,a:&mut Account,mut s:Soul,cfg:&Config<C>,expected:u64,ctx:&TxContext) {
    assert_access(k,a,ctx);assert!(soul::protocol(&s)==object::id(cfg),EBinding);soul::assert_revision(&s,expected);soul::clear_authorizations(&mut s);vault::prepare_handover(&mut s);kiosk::place(k,&a.cap,s)
}
/// Returning to the actual wallet owner remains available during protocol pause.
public fun withdraw_soul(k:&mut Kiosk,a:&mut Account,id:ID,expected:u64,ctx:&TxContext) {
    assert_access(k,a,ctx);let mut s=kiosk::take<Soul>(k,&a.cap,id);soul::assert_revision(&s,expected);soul::clear_authorizations(&mut s);vault::prepare_handover(&mut s);transfer::public_transfer(s,ctx.sender())
}

/// A concrete role-authenticated consumer. Witness values cannot be packed by clients.
/// This checks identity only: Collection.create retains its original Primary-live gate.
fun assert_collection<C,W:drop,R:drop,T>(cfg:&Config<C>,_w:W,_r:R) {
    soulidity_foundation::economics::assert_role_types<C,W,R>(cfg,4);
    let actual=std::type_name::with_original_ids<T>();
    let authority=std::type_name::with_original_ids<W>();
    let defining=std::type_name::with_defining_ids<T>();
    let defining_authority=std::type_name::with_defining_ids<W>();
    assert!(!actual.is_primitive() && actual.address_string()==authority.address_string()
        && actual.module_string()==authority.module_string()
        && *actual.datatype_string().as_bytes()==b"Right"
        && defining.address_string()==defining_authority.address_string()
        && defining.module_string()==defining_authority.module_string(),EBinding)
}
public fun lock_right<C,W:drop,R:drop,T:key+store>(cfg:&Config<C>,w:W,r:R,k:&mut Kiosk,a:&Account,p:&sui::transfer_policy::TransferPolicy<T>,value:T,ctx:&TxContext) {
    assert_collection<C,W,R,T>(cfg,w,r);assert_pair(k,a,ctx);kiosk::lock(k,&a.cap,p,value)
}
public fun borrow_right<C,W:drop,R:drop,T:key+store>(cfg:&Config<C>,w:W,r:R,k:&mut Kiosk,a:&Account,id:ID,ctx:&TxContext):&T {
    assert_collection<C,W,R,T>(cfg,w,r);assert_pair(k,a,ctx);kiosk::borrow<T>(k,&a.cap,id)
}
public fun list_right<C,W:drop,R:drop,T:key+store>(cfg:&Config<C>,w:W,r:R,k:&mut Kiosk,a:&Account,id:ID,ctx:&mut TxContext):sui::kiosk::PurchaseCap<T> {
    assert_collection<C,W,R,T>(cfg,w,r);assert_pair(k,a,ctx);kiosk::list_with_purchase_cap<T>(k,&a.cap,id,0,ctx)
}
public fun borrow_soul_for_collection<C,W:drop,R:drop>(cfg:&Config<C>,_w:W,_r:R,k:&mut Kiosk,a:&Account,id:ID,ctx:&TxContext):&mut Soul {
    soulidity_foundation::economics::assert_role_types<C,W,R>(cfg,4);assert_pair(k,a,ctx);kiosk::borrow_mut<Soul>(k,&a.cap,id)
}
/// Real X values scope each operation to X's namespace. All installations request
/// zero permissions; these helpers expose neither Soul storage nor native caps.
public fun add_extension<X:drop>(x:X,k:&mut Kiosk,a:&Account,ctx:&mut TxContext) {
    assert_pair(k,a,ctx);sui::kiosk_extension::add(x,k,&a.cap,0,ctx)
}
public fun disable_extension<X:drop>(_x:X,k:&mut Kiosk,a:&Account,ctx:&TxContext) {
    assert_pair(k,a,ctx);sui::kiosk_extension::disable<X>(k,&a.cap)
}
public fun enable_extension<X:drop>(_x:X,k:&mut Kiosk,a:&Account,ctx:&TxContext) {
    assert_pair(k,a,ctx);sui::kiosk_extension::enable<X>(k,&a.cap)
}
public fun remove_extension<X:drop>(_x:X,k:&mut Kiosk,a:&Account,ctx:&TxContext) {
    assert_pair(k,a,ctx);sui::kiosk_extension::remove<X>(k,&a.cap)
}
#[test_only]
public fun has_access_for_testing(k:&mut Kiosk,a:&Account):bool{kiosk::has_access(k,&a.cap)}
#[test_only]
public fun borrow_soul_for_testing(k:&mut Kiosk,a:&Account,id:ID,ctx:&TxContext):&Soul {
    assert_pair(k,a,ctx);kiosk::borrow<Soul>(k,&a.cap,id)
}
#[test_only]
public fun attempt_take_right_for_testing<T:key+store>(k:&mut Kiosk,a:&Account,id:ID,recipient:address,ctx:&TxContext) {
    let n=std::type_name::with_original_ids<T>();assert!(!n.is_primitive() && *n.module_string().as_bytes()==b"collection" && *n.datatype_string().as_bytes()==b"Right",EBinding);
    assert_pair(k,a,ctx);let right=kiosk::take<T>(k,&a.cap,id);transfer::public_transfer(right,recipient)
}
#[test_only]
public fun list_soul_for_testing(k:&mut Kiosk,a:&Account,id:ID,price:u64,ctx:&TxContext) {
    assert_pair(k,a,ctx);kiosk::list<Soul>(k,&a.cap,id,price)
}
#[test_only]
public fun list_soul_exclusively_for_testing(k:&mut Kiosk,a:&Account,id:ID,ctx:&mut TxContext):sui::kiosk::PurchaseCap<Soul> {
    assert_pair(k,a,ctx);kiosk::list_with_purchase_cap<Soul>(k,&a.cap,id,0,ctx)
}
