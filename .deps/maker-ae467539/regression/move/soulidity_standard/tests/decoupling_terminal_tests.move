#[test_only]
module soulidity_standard::decoupling_terminal_tests;
use sui::test_scenario;
use sui::kiosk::{Self,Kiosk,KioskOwnerCap};
use sui::transfer_policy;
use soulidity_standard::soul::{Self,Soul};
use private_source::producer;
#[test]
fun real_publisher_raw_terminal_preserves_same_cap_next_transaction(){
    let mut sc=test_scenario::begin(@0xa);soul::init_for_testing(sc.ctx());sc.next_tx(@0xa);
    let publisher:sui::package::Publisher=sc.take_from_sender();let(policy,pc)=transfer_policy::new<Soul>(&publisher,sc.ctx());
    let(mut k,cap)=kiosk::new(sc.ctx());let ki=object::id(&k);let ci=object::id(&cap);
    let p=producer::create(sc.ctx());let c=soul::new(producer::request<Soul>(&p,0,sc.ctx()),sc.ctx());let root=soul::construction_id(&c);let origin=soul::origin(soul::construction_ref(&c));
    let auth=producer::complete(&p,soul::construction_ref(&c),soul::construction_snapshot(&c),sc.ctx());
    assert!(soul::deliver_locked_cap(c,auth,&mut k,cap,&policy,sc.ctx())==root,0);
    transfer::public_share_object(k);transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);sc.return_to_sender(publisher);
    sc.next_tx(@0xa);let mut k:Kiosk=sc.take_shared_by_id(ki);let cap:KioskOwnerCap=sc.take_from_sender_by_id(ci);
    assert!(kiosk::is_locked(&k,root) && soul::origin(kiosk::borrow<Soul>(&k,&cap,root))==origin,1);
    kiosk::list<Soul>(&mut k,&cap,root,10);kiosk::delist<Soul>(&mut k,&cap,root);test_scenario::return_shared(k);sc.return_to_sender(cap);sc.end();
}
#[test]
fun real_publisher_borrowed_cap_terminal_returns_only_id_and_keeps_cap(){
    let mut sc=test_scenario::begin(@0xa);soul::init_for_testing(sc.ctx());sc.next_tx(@0xa);
    let publisher:sui::package::Publisher=sc.take_from_sender();let(policy,pc)=transfer_policy::new<Soul>(&publisher,sc.ctx());
    let(mut k,cap)=kiosk::new(sc.ctx());let ki=object::id(&k);let ci=object::id(&cap);let p=producer::create(sc.ctx());
    let c=soul::new(producer::request<Soul>(&p,0,sc.ctx()),sc.ctx());let root=soul::construction_id(&c);
    let auth=producer::complete(&p,soul::construction_ref(&c),soul::construction_snapshot(&c),sc.ctx());
    assert!(soul::deliver_locked_with_cap(c,auth,&mut k,&cap,&policy,sc.ctx())==root && object::id(&cap)==ci,0);
    transfer::public_share_object(k);transfer::public_transfer(cap,@0xa);transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);sc.return_to_sender(publisher);
    sc.next_tx(@0xa);let mut k:Kiosk=sc.take_shared_by_id(ki);let cap:KioskOwnerCap=sc.take_from_sender_by_id(ci);assert!(kiosk::has_access(&mut k,&cap) && kiosk::is_locked(&k,root),1);test_scenario::return_shared(k);sc.return_to_sender(cap);sc.end();
}
#[test,expected_failure(abort_code=13,location=soulidity_standard::soul)]
fun legacy_enabled_actual_terminal_rejected(){
    let mut sc=test_scenario::begin(@0xa);soul::init_for_testing(sc.ctx());sc.next_tx(@0xa);
    let publisher:sui::package::Publisher=sc.take_from_sender();let(policy,pc)=transfer_policy::new<Soul>(&publisher,sc.ctx());
    let(mut k,cap)=kiosk::new(sc.ctx());kiosk::set_allow_extensions(&mut k,&cap,true);let p=producer::create(sc.ctx());let c=soul::new(producer::request<Soul>(&p,0,sc.ctx()),sc.ctx());
    let auth=producer::complete(&p,soul::construction_ref(&c),soul::construction_snapshot(&c),sc.ctx());soul::deliver_locked_cap(c,auth,&mut k,cap,&policy,sc.ctx());
    transfer::public_share_object(k);transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);sc.return_to_sender(publisher);sc.end();
}
#[test,expected_failure(abort_code=3,location=soulidity_standard::soul)]
fun wrong_actual_cap_terminal_rejected(){
    let mut sc=test_scenario::begin(@0xa);let(mut k,cap)=kiosk::new(sc.ctx());let(k2,cap2)=kiosk::new(sc.ctx());let p=producer::create(sc.ctx());
    let c=soul::new(producer::request<Soul>(&p,0,sc.ctx()),sc.ctx());let(policy,pc)=transfer_policy::new_for_testing<Soul>(sc.ctx());let auth=producer::complete(&p,soul::construction_ref(&c),soul::construction_snapshot(&c),sc.ctx());
    soul::deliver_locked_cap(c,auth,&mut k,cap2,&policy,sc.ctx());transfer::public_share_object(k);transfer::public_share_object(k2);transfer::public_transfer(cap,@0xa);transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);sc.end();
}
