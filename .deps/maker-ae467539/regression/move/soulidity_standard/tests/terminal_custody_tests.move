#[test_only]
module soulidity_standard::terminal_custody_tests;
use sui::test_scenario;
use sui::kiosk::{Self,Kiosk,KioskOwnerCap};
use sui::transfer_policy;
use soulidity_standard::soul::{Self,Soul,Construction};
use private_source::producer;
fun fresh(p:&producer::Source,ctx:&mut TxContext):Construction{soul::new(producer::request<Soul>(p,0,ctx),ctx)}

#[test]
fun raw_cap_terminal_birth_preserves_same_cap_and_next_transaction_listing(){
    let mut sc=test_scenario::begin(@0xa);let(mut k,cap)=kiosk::new(sc.ctx());let ki=object::id(&k);let ci=object::id(&cap);let p=producer::create(sc.ctx());let c=fresh(&p,sc.ctx());let root=soul::construction_id(&c);let(policy,pc)=transfer_policy::new_for_testing<Soul>(sc.ctx());
    let auth=producer::complete(&p,soul::construction_ref(&c),soul::construction_snapshot(&c),sc.ctx());soul::deliver_locked_cap(c,auth,&mut k,cap,&policy,sc.ctx());assert!(kiosk::is_locked(&k,root) && !kiosk::is_listed(&k,root),0);
    transfer::public_share_object(k);transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);
    sc.next_tx(@0xa);let mut k:Kiosk=sc.take_shared_by_id(ki);let cap:KioskOwnerCap=sc.take_from_sender_by_id(ci);kiosk::list<Soul>(&mut k,&cap,root,10);assert!(kiosk::is_listed(&k,root),1);kiosk::delist<Soul>(&mut k,&cap,root);assert!(!kiosk::is_listed(&k,root),2);test_scenario::return_shared(k);sc.return_to_sender(cap);sc.end();
}

#[test,expected_failure(abort_code=13,location=soulidity_standard::soul)]
fun raw_legacy_enabled_rejects_with_typed_precondition(){
    let mut sc=test_scenario::begin(@0xa);let(mut k,cap)=kiosk::new(sc.ctx());kiosk::set_allow_extensions(&mut k,&cap,true);soul::assert_legacy_disabled(&k);transfer::public_share_object(k);transfer::public_transfer(cap,@0xa);sc.end();
}