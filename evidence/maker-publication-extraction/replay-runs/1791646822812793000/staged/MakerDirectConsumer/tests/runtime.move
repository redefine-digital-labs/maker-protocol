#[test_only]
module maker_consumer::leaf_runtime;
use std::string;
use sui::test_scenario::{Self,Scenario};
use sui::coin::{Self,Coin};
use sui::clock;
use soulidity_foundation::economics::{Self,Config,Admin};
use soulidity_foundation::revenue;
use soulidity_standard::soul::Soul;
use soulidity_maker_terms::maker_resale::{Self,Snapshot};
use soulidity_maker_terms::maker_physical_metadata as metadata;
use soulidity_maker_admission::maker_issuance;
use maker_direct::catalog::{Self,Product};
use maker_direct::native_binding;
use maker_consumer::admission_consumer as consumer;
public struct USD has drop {}
fun h(n:u8):vector<u8>{vector::tabulate!(32,|_|n)}
fun setup():Scenario{let mut sc=test_scenario::begin(@0xa);native_binding::initialize<USD>(sc.ctx());let p=catalog::new<USD>(1,h(2),sc.ctx());transfer::public_share_object(p);sc.next_tx(@0xb);sc}
fun sum(sc:&Scenario):u64{let ids=sc.ids_for_sender<Coin<USD>>();let mut n=0;ids.do_ref!(|id|{let c:Coin<USD> = sc.take_from_sender_by_id(*id);n=n+coin::value(&c);sc.return_to_sender(c)});n}
fun rights(sc:&mut Scenario,cfg:&Config<USD>):Snapshot{maker_resale::snapshot(object::id(cfg),object::id_from_address(@0x55),1,h(2),@0xa,maker_resale::rates(500,500),sc.ctx())}
#[test]
fun actual_primary_genesis_and_contribution_conserve_coins(){
 let mut sc=setup();let mut cfg:Config<USD> = sc.take_shared();let mut p:Product<USD> = sc.take_shared();let clock=clock::create_for_testing(sc.ctx());let pay=coin::mint_for_testing<USD>(101,sc.ctx());
 let (root,operator,receipt)=consumer::create(&mut p,&mut cfg,string::utf8(b"direct"),h(3),h(4),1000,pay,&clock,sc.ctx());
 assert!(*operator.module_string().as_bytes()==b"application_operator",0);assert!(catalog::income(&p)==91 && revenue::balance(economics::income(&cfg))==10 && economics::primary_receipt_actor(&receipt)==@0xb,1);
 let pay=coin::mint_for_testing<USD>(37,sc.ctx());let (product,version,commitment,paid)=consumer::complete(&mut p,&mut cfg,&root,h(5),h(6),1000,pay,&clock,sc.ctx());
 assert!(product==object::id(&p) && version==1 && commitment==h(5) && economics::primary_receipt_subject(&paid)==object::id(&root),2);assert!(catalog::income(&p)==125 && revenue::balance(economics::income(&cfg))==13,3);
 clock::destroy_for_testing(clock);transfer::public_transfer(root,sc.sender());test_scenario::return_shared(p);test_scenario::return_shared(cfg);sc.end();
}
#[test]
fun actual_secondary_gross_floor_pays_distinct_recipients_and_config_income(){
 let mut sc=setup();let mut cfg:Config<USD> = sc.take_shared();let r=rights(&mut sc,&cfg);let q=consumer::quote(&r,&cfg,101,@0xc);assert!(maker_resale::total(&q)==101 && maker_resale::platform_amount(&q)==2 && maker_resale::oc_amount(&q)==5 && maker_resale::maker_amount(&q)==5,0);
 let pay=coin::mint_for_testing<USD>(101,sc.ctx());consumer::settle(&r,&mut cfg,q,pay,object::id_from_address(@0x56),h(8),sc.ctx());assert!(revenue::balance(economics::income(&cfg))==2,1);test_scenario::return_shared(cfg);
 sc.next_tx(@0xa);assert!(sum(&sc)==5,2);sc.next_tx(@0xb);assert!(sum(&sc)==5,3);sc.next_tx(@0xc);assert!(sum(&sc)==89,4);sc.next_tx(@0xf);assert!(sum(&sc)==0,5);sc.end();
}
#[test]
fun actual_collection_ceil_is_per_component(){let mut sc=setup();let mut cfg:Config<USD> = sc.take_shared();let r=rights(&mut sc,&cfg);let q=maker_resale::quote_collection(&r,&cfg,1,@0xc,object::id_from_address(@0x57),@0xe,1);assert!(maker_resale::total(&q)==5 && maker_resale::seller_amount(&q)==1 && maker_resale::platform_amount(&q)==1 && maker_resale::oc_amount(&q)==1 && maker_resale::maker_amount(&q)==1 && maker_resale::collection_amount(&q)==1,0);let pay=coin::mint_for_testing<USD>(5,sc.ctx());consumer::settle(&r,&mut cfg,q,pay,object::id_from_address(@0x56),h(8),sc.ctx());test_scenario::return_shared(cfg);sc.next_tx(@0xe);assert!(sum(&sc)==1,1);sc.end();}
#[test,expected_failure(abort_code=3,location=soulidity_maker_terms::maker_resale)]
fun wrong_exact_coin_rejected(){let mut sc=setup();let mut cfg:Config<USD> = sc.take_shared();let r=rights(&mut sc,&cfg);let q=consumer::quote(&r,&cfg,101,@0xc);let pay=coin::mint_for_testing<USD>(102,sc.ctx());consumer::settle(&r,&mut cfg,q,pay,object::id_from_address(@0x56),h(8),sc.ctx());test_scenario::return_shared(cfg);sc.end();}
#[test,expected_failure(abort_code=1,location=soulidity_maker_terms::maker_resale)]
fun copyable_receipt_for_different_rights_rejected(){let mut sc=setup();let mut cfg:Config<USD> = sc.take_shared();let r=rights(&mut sc,&cfg);let forged=maker_resale::snapshot(object::id(&cfg),object::id_from_address(@0x55),1,h(2),@0xa,maker_resale::rates(0,0),sc.ctx());let q=consumer::quote(&forged,&cfg,101,@0xc);let pay=coin::mint_for_testing<USD>(101,sc.ctx());consumer::settle(&r,&mut cfg,q,pay,object::id_from_address(@0x56),h(8),sc.ctx());test_scenario::return_shared(cfg);sc.end();}
#[test,expected_failure(abort_code=1,location=soulidity_maker_terms::maker_resale)]
fun additive_u64_overflow_rejected(){let mut sc=setup();let cfg:Config<USD> = sc.take_shared();let r=rights(&mut sc,&cfg);maker_resale::quote_collection(&r,&cfg,18446744073709551615,@0xc,object::id_from_address(@0x57),@0xe,1);test_scenario::return_shared(cfg);sc.end();}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::package_roles)]
fun copyable_quote_and_primitive_witness_do_not_authorize_funds(){let mut sc=setup();let mut cfg:Config<USD> = sc.take_shared();let r=rights(&mut sc,&cfg);let q=consumer::quote(&r,&cfg,101,@0xc);let pay=coin::mint_for_testing<USD>(101,sc.ctx());maker_resale::settle(false,false,&mut cfg,&r,q,pay,object::id_from_address(@0x56),h(8),sc.ctx());test_scenario::return_shared(cfg);sc.end();}
#[test,expected_failure(abort_code=1,location=soulidity_maker_admission::maker_issuance)]
fun binding_rejects_wrong_operator_type(){let mut sc=setup();let cfg:Config<USD> = sc.take_shared();let bad=native_binding::bad_operator(&cfg);let mut p:Product<USD> = sc.take_shared();let clock=clock::create_for_testing(sc.ctx());let pay=coin::mint_for_testing<USD>(0,sc.ctx());let mut cfg=cfg;let (root,g,_)=catalog::mint(&mut p,&mut cfg,bad,string::utf8(b"wrong"),h(3),h(4),1000,pay,&clock,sc.ctx());maker_issuance::consume_genesis(g,&root,h(3),sc.ctx());clock::destroy_for_testing(clock);transfer::public_transfer(root,sc.sender());test_scenario::return_shared(p);test_scenario::return_shared(cfg);sc.end();}
#[test,expected_failure(abort_code=2,location=soulidity_maker_admission::maker_issuance)]
fun genesis_rejects_copyable_metadata_mismatch(){let mut sc=setup();let mut cfg:Config<USD> = sc.take_shared();let mut p:Product<USD> = sc.take_shared();let clock=clock::create_for_testing(sc.ctx());let binding=native_binding::binding(&cfg);let pay=coin::mint_for_testing<USD>(0,sc.ctx());let (root,g,_)=catalog::mint(&mut p,&mut cfg,binding,string::utf8(b"wrong"),h(3),h(4),1000,pay,&clock,sc.ctx());maker_issuance::consume_genesis(g,&root,h(9),sc.ctx());clock::destroy_for_testing(clock);transfer::public_transfer(root,sc.sender());test_scenario::return_shared(p);test_scenario::return_shared(cfg);sc.end();}
#[test]
fun physical_proof_is_copyable_untrusted_facts(){let a=object::id_from_address(@0x55);let p=metadata::proof(a,3,4,a,h(1),h(2),h(3),h(4),h(5),h(6),h(7),h(8),h(9));let copied=p;assert!(metadata::proof_hash(&copied)==metadata::proof_hash(&p) && metadata::proof_soul(&p)==a && metadata::proof_revision(&p)==4,0);}
