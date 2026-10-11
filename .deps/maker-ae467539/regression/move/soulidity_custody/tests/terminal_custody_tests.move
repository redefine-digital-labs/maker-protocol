#[test_only]
module soulidity_custody::terminal_custody_tests;
use sui::test_scenario;
use sui::kiosk::{Self,Kiosk,KioskOwnerCap};
use sui::transfer_policy;
use soulidity_standard::soul::{Self,Soul,Construction};
use soulidity_custody::account::{Self,Account};
use private_source::producer;
fun fresh(p:&producer::Source,ctx:&mut TxContext):Construction{soul::new(producer::request<Soul>(p,0,ctx),ctx)}
#[test]
fun fresh_pair_terminal_birth_preserves_ids_owner_root_and_next_transaction_access(){
    let mut sc=test_scenario::begin(@0xa);soul::init_for_testing(sc.ctx());sc.next_tx(@0xa);
    let publisher:sui::package::Publisher=sc.take_from_sender();let(policy,pc)=transfer_policy::new<Soul>(&publisher,sc.ctx());
    let p=producer::create(sc.ctx());let c=fresh(&p,sc.ctx());let root=soul::construction_id(&c);let origin=soul::origin(soul::construction_ref(&c));
    let(k,a)=account::new(sc.ctx());let kiosk_id=object::id(&k);let account_id=object::id(&a);let cap_id=account::cap_id(&a);
    assert!(std::bcs::to_bytes(&k).length()==77,0);account::assert_legacy_disabled(&k);
    let auth=producer::complete(&p,soul::construction_ref(&c),soul::construction_snapshot(&c),sc.ctx());
    assert!(account::deliver_locked_fresh_account(c,auth,k,a,&policy,sc.ctx())==root,1);
    transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);sc.return_to_sender(publisher);
    sc.next_tx(@0xa);let mut k:Kiosk=sc.take_shared_by_id(kiosk_id);let mut a:Account=sc.take_from_sender_by_id(account_id);
    account::assert_access(&mut k,&mut a,sc.ctx());assert!(account::owner(&a)==@0xa && account::kiosk_id(&a)==kiosk_id && account::cap_id(&a)==cap_id,2);
    assert!(kiosk::is_locked(&k,root) && !kiosk::is_listed(&k,root),3);let s=account::borrow_for_testing<Soul>(&mut k,&a,root,sc.ctx());assert!(soul::origin(s)==origin,4);
    account::withdraw_profits(&mut k,&mut a,option::some(0),sc.ctx());test_scenario::return_shared(k);sc.return_to_sender(a);sc.end();
}

#[test]
fun existing_shared_pair_terminal_birth_preserves_account_and_native_cap(){
    let mut sc=test_scenario::begin(@0xa);let(k,a)=account::new(sc.ctx());let ki=object::id(&k);let ai=object::id(&a);let cap=account::cap_id(&a);account::finalize(k,a,sc.ctx());
    sc.next_tx(@0xa);let mut k:Kiosk=sc.take_shared_by_id(ki);let a:Account=sc.take_from_sender_by_id(ai);let p=producer::create(sc.ctx());let c=fresh(&p,sc.ctx());let root=soul::construction_id(&c);
    let(policy,pc)=transfer_policy::new_for_testing<Soul>(sc.ctx());let auth=producer::complete(&p,soul::construction_ref(&c),soul::construction_snapshot(&c),sc.ctx());
    account::deliver_locked_account(c,auth,&mut k,a,&policy,sc.ctx());assert!(kiosk::is_locked(&k,root),0);test_scenario::return_shared(k);transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);
    sc.next_tx(@0xa);let mut k:Kiosk=sc.take_shared_by_id(ki);let mut a:Account=sc.take_from_sender_by_id(ai);account::assert_access(&mut k,&mut a,sc.ctx());assert!(account::cap_id(&a)==cap,1);test_scenario::return_shared(k);sc.return_to_sender(a);sc.end();
}

#[test]
fun terminal_custody_retains_three_fresh_nested_origins_and_ids(){
    let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let mut outer=fresh(&p,sc.ctx());let mut child=fresh(&p,sc.ctx());let grand=fresh(&p,sc.ctx());
    let oi=soul::construction_id(&outer);let ci=soul::construction_id(&child);let gi=soul::construction_id(&grand);
    let origins=vector[soul::origin(soul::construction_ref(&outer)),soul::origin(soul::construction_ref(&child)),soul::origin(soul::construction_ref(&grand))];
    let auth=producer::complete(&p,soul::construction_ref(&grand),soul::construction_snapshot(&grand),sc.ctx());soul::nest_construction(&mut child,grand,auth,0,sc.ctx());
    let auth=producer::complete(&p,soul::construction_ref(&child),soul::construction_snapshot(&child),sc.ctx());soul::nest_construction(&mut outer,child,auth,0,sc.ctx());
    let(k,a)=account::new(sc.ctx());let ki=object::id(&k);let ai=object::id(&a);let(policy,pc)=transfer_policy::new_for_testing<Soul>(sc.ctx());let auth=producer::complete(&p,soul::construction_ref(&outer),soul::construction_snapshot(&outer),sc.ctx());
    account::deliver_locked_fresh_account(outer,auth,k,a,&policy,sc.ctx());transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);
    sc.next_tx(@0xa);let mut k:Kiosk=sc.take_shared_by_id(ki);let a:Account=sc.take_from_sender_by_id(ai);let root=account::borrow_for_testing<Soul>(&mut k,&a,oi,sc.ctx());
    assert!(soul::origin(root)==origins[0] && soul::origin(soul::nested(root,ci))==origins[1] && soul::origin(soul::nested(soul::nested(root,ci),gi))==origins[2],0);test_scenario::return_shared(k);sc.return_to_sender(a);sc.end();
}

#[test,expected_failure(abort_code=11,location=soulidity_standard::soul)]
fun terminal_custody_requires_all_fresh_descendants_present(){
    let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let mut outer=fresh(&p,sc.ctx());let child=fresh(&p,sc.ctx());let ci=soul::construction_id(&child);
    let auth=producer::complete(&p,soul::construction_ref(&child),soul::construction_snapshot(&child),sc.ctx());soul::nest_construction(&mut outer,child,auth,0,sc.ctx());let child=soul::unnest(soul::construction_mut(&mut outer),ci,1);
    let(k,a)=account::new(sc.ctx());let(policy,pc)=transfer_policy::new_for_testing<Soul>(sc.ctx());let auth=producer::complete(&p,soul::construction_ref(&outer),soul::construction_snapshot(&outer),sc.ctx());account::deliver_locked_fresh_account(outer,auth,k,a,&policy,sc.ctx());
    transfer::public_transfer(child,@0xa);transfer::public_share_object(policy);transfer::public_transfer(pc,@0xa);transfer::public_transfer(p,@0xa);sc.end();
}
