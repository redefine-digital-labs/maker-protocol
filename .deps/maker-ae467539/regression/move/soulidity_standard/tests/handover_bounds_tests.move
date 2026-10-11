#[test_only]
module soulidity_standard::handover_bounds_tests;
use sui::test_scenario;
use soulidity_standard::soul::{Self,Soul};
use private_source::producer::{Self,Source};
use foreign_soul::soul as foreign_soul;
public struct ProtectedWitness has drop {}
public struct Protected has key,store {id:UID,generation:u64}
/// Genuine independent source request with explicitly test-only raw allocation
/// isolates native-tree bounds. Full original App/Vault journeys are separate.
fun raw(p:&Source,ctx:&mut TxContext):Soul {
 soul::raw_from_request_for_testing(producer::request<Soul>(p,0,ctx),ctx)
}
fun chain(p:&Source,depth:u64,ctx:&mut TxContext):Soul {
 let mut child=raw(p,ctx);let mut i=0;
 while(i < depth){let mut parent=raw(p,ctx);soul::nest(&mut parent,child,0);child=parent;i=i+1};child
}
fun fan(p:&Source,count:u64,ctx:&mut TxContext):Soul {
 let mut root=raw(p,ctx);let mut left=count-1;
 while(left>0){let mut middle=raw(p,ctx);left=left-1;let take=left.min(63);let mut i=0;
  while(i < take){let leaf=raw(p,ctx);let r=soul::revision(&middle);soul::nest(&mut middle,leaf,r);i=i+1};left=left-take;
  let r=soul::revision(&root);soul::nest(&mut root,middle,r)
 };root
}
#[test]
fun actual_depth16_native_tree_finishes_under_default_budget(){
 let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let s=chain(&p,16,sc.ctx());let id=object::id(&s);let h=soul::begin_handover(s);soul::finish_handover(h,@0xb);transfer::public_transfer(p,@0xa);
 sc.next_tx(@0xb);let s:Soul=sc.take_from_sender_by_id(id);sc.return_to_sender(s);sc.end();
}
#[test,expected_failure(abort_code=7,location=soulidity_standard::soul)]
fun actual_depth17_native_tree_is_capacity_refused(){let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let s=chain(&p,17,sc.ctx());let h=soul::begin_handover(s);soul::finish_handover(h,@0xb);transfer::public_transfer(p,@0xa);sc.end();}
#[test]
fun actual_node256_native_tree_finishes_under_default_budget(){
 let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let s=fan(&p,256,sc.ctx());let id=object::id(&s);let h=soul::begin_handover(s);soul::finish_handover(h,@0xb);transfer::public_transfer(p,@0xa);
 sc.next_tx(@0xb);let s:Soul=sc.take_from_sender_by_id(id);sc.return_to_sender(s);sc.end();
}
#[test,expected_failure(abort_code=7,location=soulidity_standard::soul)]
fun actual_node257_native_tree_is_capacity_refused(){let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let s=fan(&p,257,sc.ctx());let h=soul::begin_handover(s);soul::finish_handover(h,@0xb);transfer::public_transfer(p,@0xa);sc.end();}

#[test]
fun fresh_protected_genesis_gift_preserves_unrotated_generation(){
 let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let mut c=soul::new(producer::request<Soul>(&p,0,sc.ctx()),sc.ctx());
 let tool=Protected{id:object::new(sc.ctx()),generation:0};soul::install_protected(soul::construction_mut(&mut c),ProtectedWitness{},b"protected",tool,1,false,vector::tabulate!(32,|_|7),0);
 let auth=producer::complete(&p,soul::construction_ref(&c),soul::construction_snapshot(&c),sc.ctx());let id=soul::deliver(c,auth,@0xb,sc.ctx());transfer::public_transfer(p,@0xa);
 sc.next_tx(@0xb);let s:Soul=sc.take_from_sender_by_id(id);assert!(soul::borrow_module<ProtectedWitness,Protected>(&s,b"protected").generation==0 && soul::handover_required(&soul::descriptor<ProtectedWitness>(&s,b"protected").destroy_some()),0);sc.return_to_sender(s);sc.end();
}
#[test,expected_failure(abort_code=3,location=soulidity_standard::soul)]
fun public_manifest_cannot_hide_canonical_soul_in_non_native_namespace(){
 let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let mut root=raw(&p,sc.ctx());let mut child=raw(&p,sc.ctx());
 soul::install_protected(&mut child,ProtectedWitness{},b"protected",Protected{id:object::new(sc.ctx()),generation:55},1,false,vector::tabulate!(32,|_|7),0);
 let metadata=soul::manifest(&root);soul::install(&mut root,metadata,b"hidden",child,1,true,vector::tabulate!(32,|_|7),0);transfer::public_transfer(root,@0xb);transfer::public_transfer(p,@0xa);sc.end();
}
#[test]
fun exact_foreign_soul_type_keeps_generic_non_native_install_domain(){
 let mut sc=test_scenario::begin(@0xa);let p=producer::create(sc.ctx());let mut root=raw(&p,sc.ctx());let(w,foreign)=foreign_soul::new(sc.ctx());let id=object::id(&foreign);let r=soul::revision(&root);soul::install(&mut root,w,b"foreign",foreign,1,true,vector::tabulate!(32,|_|7),r);
 let ty=std::type_name::with_defining_ids<foreign_soul::Soul>();let canonical=std::type_name::with_defining_ids<Soul>();
 assert!(ty.module_string()==canonical.module_string() && ty.datatype_string()==canonical.datatype_string() && ty.address_string()!=canonical.address_string(),2);
 assert!(object::id(soul::borrow_module<foreign_soul::Witness,foreign_soul::Soul>(&root,b"foreign"))==id,0);let rid=object::id(&root);let h=soul::begin_handover(root);soul::finish_handover(h,@0xb);transfer::public_transfer(p,@0xa);
 sc.next_tx(@0xb);let s:Soul=sc.take_from_sender_by_id(rid);let foreign=soul::borrow_module<foreign_soul::Witness,foreign_soul::Soul>(&s,b"foreign");assert!(object::id(foreign)==id && foreign_soul::value(foreign)==71,1);sc.return_to_sender(s);sc.end();
}
