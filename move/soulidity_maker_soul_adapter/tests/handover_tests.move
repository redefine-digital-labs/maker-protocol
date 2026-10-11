#[test_only]
module soulidity_maker_soul_adapter::handover_tests;
use soulidity_custody::lifecycle;
use std::string;
use std::type_name;
use sui::test_scenario::{Self,Scenario};
use sui::clock::{Self,Clock};
use sui::coin;
use soulidity_maker_soul_adapter::maker_soul::{Self as adapter,Build};
use soulidity_maker_soul_adapter::storage_fixture as storage;
use soulidity_v1::native_operator_fixture;
use soulidity_foundation::economics::{Self,Config,Admin};
use soulidity_foundation::package_roles::{Self,RoleCertificate};
use soulidity_foundation::revenue;
use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,Product,Control,CreatorAuthority1,CreatorRevision3};
use soulidity_maker_manufacturing::maker_release::{Self as release,ReleaseInstaller1,ReleaseRevision3};
use soulidity_maker_manufacturing::maker_metadata as metadata;
use soulidity_maker_manufacturing::maker_factory as factory;
use soulidity_maker_manufacturing::maker_player::{Self as player,Player};
use soulidity_maker_terms::maker_resale;
use soulidity_model::policy::{Self,Definition,Layout};
use soulidity_model::assembly;
use soulidity_visual::visual;
use soulidity_application::character;
use soulidity_application::output;
use soulidity_maker_publication::output_data::Intent;
use soulidity_content_kinds::content_kind_registry::{Self as kinds,KindRegistry};
use soulidity_content_kinds::document_policy;
use soulidity_standard::soul::{Self as standard,Soul};
use walrus::system::System;
use walrus::test_node::TestStorageNode;
public struct USD has drop {}
public struct F {sc:Scenario,cfg:Config<USD>,admin:Admin,p:Product<USD>,control:Control,system:System,nodes:vector<TestStorageNode>,clock:Clock,registry:KindRegistry,paid:bool}
fun h(n:u8):vector<u8>{vector::tabulate!(32,|_|n)}
fun layout():Layout{policy::layout(false,0,false,0,1000000,0,vector[])}
fun scene():visual::Scene{visual::scene(1024,1024,visual::signed(false,0),visual::signed(false,0),0,h(14),b"body",b"pose",vector[b"ref",b"bound",b"free"],vector[visual::track(b"main",0,false)],vector[visual::channel(b"skin",b"default",true,vector[visual::swatch(b"default",0xffaa00ff,vector[]),visual::swatch(b"blue",0x0000ffff,vector[])])],vector[visual::anchor(b"root",vector[],visual::signed(false,0),visual::signed(false,0))],vector[])}
fun pack_scene():visual::Scene{visual::scene(1024,1024,visual::signed(false,0),visual::signed(false,0),0,h(14),b"body",b"pose",vector[b"ref",b"bound",b"free",b"cape"],vector[visual::track(b"main",0,false)],vector[visual::channel(b"skin",b"default",true,vector[visual::swatch(b"default",0xffaa00ff,vector[]),visual::swatch(b"blue",0x0000ffff,vector[])])],vector[visual::anchor(b"root",vector[],visual::signed(false,0),visual::signed(false,0))],vector[])}
fun definition(part:vector<u8>,rights:u8):Definition{definition_at(part,b"style",rights)}
fun definition_at(part:vector<u8>,style:vector<u8>,rights:u8):Definition{
 let fragment=visual::fragment(b"image",h(11),b"image/png",1024,1024,1024,0,0,1024,1024,512000,512000,b"main",0,b"root",visual::transform(visual::signed(false,0),visual::signed(false,0),1000000,visual::signed(false,0)),1000000,0,option::none(),option::none(),option::none(),vector[]);
 policy::definition(part,b"item",style,rights,h(11),h(12),visual::representation(&if(part==b"cape")pack_scene() else scene(),1024,1024,vector[fragment],vector[]),10,layout(),policy::bounds(10,10,500000,2000000,90000,vector[vector[255,0,0,255]]),vector[],vector[],true)
}
/// Explicit unpublished 0x0 certificate + Walrus certification VM fixtures.
/// Config creation/activation/Product publication/access/settlement are real production calls.
fun setup(paid:bool):F{setup_route(paid,false)}
fun setup_route(paid:bool,native_build:bool):F{
 let mut sc=test_scenario::begin(@0xf);let(nodes,clock)=storage::bootstrap(&mut sc);kinds::init_for_testing(sc.ctx());
 let release_id=package_roles::certificate_for_testing<ReleaseInstaller1,ReleaseRevision3>(1,1,sc.ctx());let creator_id=package_roles::certificate_for_testing<CreatorAuthority1,CreatorRevision3>(2,1,sc.ctx());
 sc.next_tx(@0xa);let mut system:System=sc.take_shared();let release:RoleCertificate<ReleaseInstaller1,ReleaseRevision3> =sc.take_immutable_by_id(release_id);let creator:RoleCertificate<CreatorAuthority1,CreatorRevision3> =sc.take_immutable_by_id(creator_id);
 let(mut cfg,mut admin)=factory::new_service<USD>(&release,&creator,1000,500,if(paid)7 else 0,@0xf,&system,h(80),h(81),sc.ctx());
 test_scenario::return_immutable(release);test_scenario::return_immutable(creator);let rev=economics::revision(&cfg);let hash=economics::commitment(&cfg);economics::set_primary_enabled(&mut cfg,&mut admin,rev,hash,true);let rev=economics::revision(&cfg);let hash=economics::commitment(&cfg);release::activate(&mut cfg,&mut admin,&system,rev,hash);
 assert!(economics::native_snapshot(&cfg).is_none() && !package_roles::pinned(&economics::role(&cfg,0)),100);
 let product=factory::create_maker(&cfg,0,&system,sc.ctx());let config=economics::finalize_manufacturing_instance(cfg,admin,sc.ctx());test_scenario::return_shared(system);sc.next_tx(@0xa);
 let cfg:Config<USD> =sc.take_shared_by_id(config);let admin:Admin=sc.take_from_sender();let mut p:Product<USD> =sc.take_shared_by_id(product);let mut control:Control=sc.take_from_sender();let mut system:System=sc.take_shared();let registry:KindRegistry=sc.take_shared();
 let out=output::policy(b"default",false,vector[],h(14),true,vector[],vector[output::initial_rule(&registry,0,document_policy::soul_doc_name(),3,0),output::initial_rule(&registry,1,document_policy::memory_name(),3,0),output::initial_rule(&registry,2,string::utf8(b"default"),3,0)]);
 let seed=catalog::version(h(1),h(2),if(paid)1 else 0,if(paid)100 else 0,if(paid)1 else 0,if(paid)1000 else 0,0,0,0,@0xd,maker_resale::rates(0,0),vector[b"ref",b"bound",b"free"],vector[b"free"],vector[],vector[],scene());let seed=catalog::with_outputs(if(native_build)native_operator_fixture::with_execution(seed) else adapter::with_execution(seed),vector[out]);
 let mut m=metadata::start(&p,&mut control,&cfg,0,seed,&system,sc.ctx());metadata::append_definitions(&mut m,&p,&mut control,&cfg,vector[definition(b"ref",0),definition(b"bound",1),definition(b"free",2),definition_at(b"free",b"alternate-style",2)],&system,0,sc.ctx());let hash=metadata::policy_hash(&m);let living=storage::blob(&mut system,100,false,true,sc.ctx());let manifest=storage::blob(&mut system,101,false,true,sc.ctx());let mut draft=metadata::begin_publication(m,&p,&mut control,&cfg,1,hash,release::author(b"Character",vector[],vector[],b"license",h(3)),living,manifest,&system,sc.ctx());let blob=storage::blob(&mut system,102,false,true,sc.ctx());release::append(&mut draft,&p,&mut control,&cfg,h(11),false,h(11),blob,&system,0,sc.ctx());release::finish(draft,&mut p,&mut control,&cfg,&system,1,sc.ctx());
 // Ordinary consumer has no service Admin and does not rebind the author's Product.
 test_scenario::return_shared(cfg);test_scenario::return_to_address(@0xa,admin);test_scenario::return_shared(p);test_scenario::return_to_address(@0xa,control);test_scenario::return_shared(system);test_scenario::return_shared(registry);sc.next_tx(@0xb);
 F{cfg:sc.take_shared_by_id(config),admin:sc.take_from_address(@0xa),p:sc.take_shared_by_id(product),control:sc.take_from_address(@0xa),system:sc.take_shared(),registry:sc.take_shared(),sc,nodes,clock,paid}
}
fun expiry(f:&F):u64{clock::timestamp_ms(&f.clock)+1000}
fun recipe(f:&F):vector<u8>{let parts=vector[b"ref",b"bound",b"free"];let mut slots=vector[];let mut i=0;while(i < 3){slots.push_back(output::slot(parts[i],option::some(output::selection(catalog::preview_source(&f.p,1,policy::definition_hash(&definition(parts[i],i as u8))),layout(),option::none()))));i=i+1};output::recipe_hash(&scene(),&visual::default_colors(&scene()),slots)}
fun intent(f:&F,attempt:u8,recipe:vector<u8>):Intent{let v=catalog::published(&f.p,1);let out=catalog::output_policy(v,b"default");output::intent(object::id(&f.cfg),object::id(&f.p),1,catalog::policy_hash(v),output::policy_hash(&out),f.sc.sender(),h(attempt),string::utf8(b"OC"),recipe,vector::tabulate!(16,|_|attempt))}
fun buy_access(f:&mut F){if(f.paid){let exp=expiry(f);let rev=economics::revision(&f.cfg);let hash=catalog::policy_hash(catalog::published(&f.p,1));let F{sc,cfg,p,system,clock,..}=f;factory::buy_access(p,cfg,1,hash,rev,exp,h(20),coin::mint_for_testing<USD>(100,sc.ctx()),system,clock,sc.ctx())}}
fun begin(f:&mut F,attempt:u8):Build{let i=intent(f,attempt,recipe(f));begin_intent(f,i)}
fun begin_intent(f:&mut F,i:Intent):Build{let exp=expiry(f);let rev=economics::revision(&f.cfg);let amount=catalog::completion_price(&f.p,1,f.sc.sender())+economics::complete_fee(&f.cfg);let F{sc,cfg,p,system,clock,..}=f;adapter::begin(p,cfg,i,b"default",rev,exp,coin::mint_for_testing<USD>(amount,sc.ctx()),clock,system,sc.ctx())}
fun select(f:&mut F,b:&mut Build,drift:bool){let parts=vector[b"ref",b"bound",b"free"];let mut i=0;while(i < 3){let chosen=if(drift && i==2)policy::layout(false,1,false,0,1000000,0,vector[]) else layout();let F{sc,cfg,p,system,..}=f;adapter::select(b,p,policy::definition_hash(&definition(parts[i],i as u8)),parts[i],chosen,cfg,system,sc.ctx());i=i+1}}
fun initial(f:&mut F,b:&mut Build,omit:Option<u32>){output::initials(adapter::output_policy(b)).do_ref!(|r|{let kind=output::rule_kind(r);if(omit!=option::some(kind)){let F{sc,system,registry,clock,..}=f;let blob=storage::blob(system,(200+kind) as u256,false,true,sc.ctx());adapter::append_initial_content(b,registry,kind,output::rule_name(r),blob,system,h((50+kind) as u8),b"initial-envelope",clock,sc.ctx());}})}
fun finish(f:&mut F,b:Build):ID{let F{sc,cfg,system,clock,..}=f;let render=storage::blob(system,300,false,true,sc.ctx());adapter::finish(b,cfg,clock,render,system,h(60),vector[],sc.ctx())}
fun complete(f:&mut F,attempt:u8):ID{let mut b=begin(f,attempt);select(f,&mut b,false);initial(f,&mut b,option::none());finish(f,b)}
fun end(f:F){let F{sc,cfg,admin,p,control,system,nodes,clock,registry,paid:_}=f;test_scenario::return_shared(cfg);test_scenario::return_to_address(@0xa,admin);test_scenario::return_shared(p);test_scenario::return_to_address(@0xa,control);test_scenario::return_shared(system);test_scenario::return_shared(registry);nodes.do!(|n|n.destroy());clock::destroy_for_testing(clock);sc.end();}

use std::bcs;
use soulidity_application::{vault,custody_handover};
use soulidity_content::{authorization,paid_access};
use private_source::producer;
public struct SoulProducer has drop {}
public struct RawSource has key,store {id:UID}
public struct Token has key,store {id:UID,value:u64}
public struct FutureWitness has drop {}
public struct WrongWitness has drop {}
public struct FutureTool has key,store {id:UID,epoch:u64}
public struct PassiveWitness has drop {}
public struct PassiveTool has key,store {id:UID,value:u64}
/// Explicit VM-only raw root used only for absent-App native intermediates and
/// capacity/source-control fixtures. Real handover positives use full Maker creation above.
fun raw(ctx:&mut TxContext):Soul {
 let source=RawSource{id:object::new(ctx)};
 let s=standard::creation_raw_for_testing(standard::new(SoulProducer{},&source,1,h(9),string::utf8(b"intermediate"),ctx));
 transfer::public_transfer(source,ctx.sender());s
}
fun created(f:&mut F,attempt:u8):Soul {let id=complete(f,attempt);f.sc.next_tx(@0xb);f.sc.take_from_sender_by_id(id)}
fun funded(f:&mut F,s:&mut Soul,request:u8):ID {
 let r=standard::revision(s);vault::install(s,r,f.sc.ctx());
 let r=standard::revision(s);let t=vault::revision(vault::tool(s));let coin=coin::mint_for_testing<USD>(123,f.sc.ctx());vault::deposit_coin(s,coin,h(request),t,r,f.sc.ctx());
 let token=Token{id:object::new(f.sc.ctx()),value:7};let id=object::id(&token);let r=standard::revision(s);let t=vault::revision(vault::tool(s));vault::deposit_asset(s,token,h(request+1),t,r,f.sc.ctx());
 let blob=storage::blob(&mut f.system,(600+(request as u256)),false,true,f.sc.ctx());let r=standard::revision(s);let t=vault::revision(vault::tool(s));vault::save_private(s,blob,&f.system,h(request+2),h(request+3),0,t,r,f.sc.ctx());id
}
fun grant(f:&mut F,s:&mut Soul){let r=character::revision(s);character::grant(s,@0xd,character::scope_memory(),option::none(),r,option::none(),&f.clock,f.sc.ctx());}
fun future(s:&mut Soul,schema:u16,ctx:&mut TxContext):ID {
 let v=FutureTool{id:object::new(ctx),epoch:0};let id=object::id(&v);let r=standard::revision(s);
 lifecycle::install_protected(s,FutureWitness{},b"future",v,schema,true,h(10),r);id
}
fun update_future(s:&mut Soul,epoch:u64,schema:u16) {
 let r=standard::revision(s);let(mut v,ticket)=standard::begin_update<FutureWitness,FutureTool>(s,FutureWitness{},b"future",r);v.epoch=epoch;
 standard::commit_update(s,ticket,FutureWitness{},v,schema,h(10))
}
fun acknowledge_future(h:&mut lifecycle::Handover) {
 // Genuine source-private mutation precedes private W issuance; no receipt or
 // bare authority constructor is exposed, even in this explicit local fixture.
 let s=lifecycle::handover_raw_mut_for_testing(h);let epoch=standard::borrow_module<FutureWitness,FutureTool>(s,b"future").epoch;
 update_future(s,epoch+1,1);lifecycle::acknowledge_handover<FutureWitness,FutureTool>(h,FutureWitness{},b"future",1)
}
fun acknowledge_known(h:&mut lifecycle::Handover){character::acknowledge_handover(h);vault::acknowledge_handover(h)}
fun passive(s:&mut Soul,ctx:&mut TxContext){let r=standard::revision(s);standard::install(s,PassiveWitness{},b"passive",PassiveTool{id:object::new(ctx),value:0},1,true,h(10),r)}
fun mutate_passive(s:&mut Soul){let r=standard::revision(s);let(mut v,t)=standard::begin_update<PassiveWitness,PassiveTool>(s,PassiveWitness{},b"passive",r);v.value=1;standard::commit_update(s,t,PassiveWitness{},v,1,h(10))}
fun assert_inventory(s:&Soul,asset:ID,request:u8,gen:u64,receipt:Option<soulidity_content::loadout::Receipt>){
 assert!(vault::coin_balance<USD>(s)==123 && vault::has_asset<Token>(s,asset) && vault::asset<Token>(s,asset).value==7,201);
 assert!(vault::privacy_generation(vault::tool(s))==gen && vault::action(s,h(request)).is_some() && vault::action(s,h(request+1)).is_some() && vault::private_receipt(s,@0xb,0,h(request+3))==receipt && vault::private_head(s,@0xb).is_none(),202)
}
#[test]
fun full_paid_maker_nested_absent_app_a_b_a_clears_rotates_preserves_ids_funds_receipts_rights(){
 let mut f=setup(true);buy_access(&mut f);let mut root=created(&mut f,30);let mut grand=created(&mut f,31);let mut middle=raw(f.sc.ctx());
 let rid=object::id(&root);let mid=object::id(&middle);let gid=object::id(&grand);let ro=standard::origin(&root);let go=standard::origin(&grand);
 let asset0=funded(&mut f,&mut root,70);let asset1=funded(&mut f,&mut middle,80);let asset2=funded(&mut f,&mut grand,90);grant(&mut f,&mut root);grant(&mut f,&mut grand);
 let receipt0=vault::private_receipt(&root,@0xb,0,h(73));let receipt1=vault::private_receipt(&middle,@0xb,0,h(83));let receipt2=vault::private_receipt(&grand,@0xb,0,h(93));assert!(receipt0.is_some() && receipt1.is_some() && receipt2.is_some(),203);
 let ar=character::application_module_id(&root);let ag=character::application_module_id(&grand);let bound=character::bound_count(&root);let item=character::free_id(&character::binding(&root,b"free").destroy_some());let art=bcs::to_bytes(character::original_output(&root));
 let r=character::revision(&root);character::add_paid_access(&mut root,&f.registry,kinds::kind_sprite(),@0xd,character::scope_assets(),option::none(),0,option::none(),r,&f.clock,f.sc.ctx());let paid=bcs::to_bytes(character::paid_access(&root));let entry=paid_access::entry_hash(character::paid_access(&root),kinds::kind_sprite(),@0xd);
 let r=standard::revision(&middle);standard::nest(&mut middle,grand,r);let r=standard::revision(&root);standard::nest(&mut root,middle,r);
 // Original owner handover is a safe exit even when service is paused/off.
 let rev=economics::revision(&f.cfg);economics::configure(&mut f.cfg,&mut f.admin,rev,1000,500,7,@0xf,true);let rev=economics::revision(&f.cfg);let hash=economics::commitment(&f.cfg);economics::set_primary_enabled(&mut f.cfg,&mut f.admin,rev,hash,false);let rev=economics::revision(&f.cfg);let hash=economics::commitment(&f.cfg);economics::set_enabled(&mut f.cfg,&mut f.admin,rev,hash,false);
 let expected=character::revision(&root);character::handover(root,@0xc,expected);f.sc.next_tx(@0xc);let root:Soul=f.sc.take_from_sender_by_id(rid);
 let middle=standard::nested(&root,mid);let grand=standard::nested(middle,gid);assert!(standard::origin(&root)==ro && standard::origin(grand)==go && character::application_module_id(&root)==ar && character::application_module_id(grand)==ag,204);
 assert!(character::generation(&root)==1 && character::generation(grand)==1 && character::grant_count(&root)==0 && character::grant_count(grand)==0,205);
 assert_inventory(&root,asset0,70,1,receipt0);assert_inventory(middle,asset1,80,1,receipt1);assert_inventory(grand,asset2,90,1,receipt2);
 assert!(character::bound_count(&root)==bound && character::free_id(&character::binding(&root,b"free").destroy_some())==item && bcs::to_bytes(character::original_output(&root))==art && bcs::to_bytes(character::paid_access(&root))==paid && paid_access::entry_hash(character::paid_access(&root),kinds::kind_sprite(),@0xd)==entry,206);
 custody_handover::handover(root,@0xb);f.sc.next_tx(@0xb);let mut root:Soul=f.sc.take_from_sender_by_id(rid);let middle=standard::nested(&root,mid);let grand=standard::nested(middle,gid);
 assert!(character::generation(&root)==2 && character::generation(grand)==2 && !character::grant_live(&mut root,@0xd,&f.clock,f.sc.ctx()),207);
 assert_inventory(&root,asset0,70,2,receipt0);assert_inventory(standard::nested(&root,mid),asset1,80,2,receipt1);assert_inventory(standard::nested(standard::nested(&root,mid),gid),asset2,90,2,receipt2);
 f.sc.return_to_sender(root);end(f)
}
#[test]
fun genuine_future_private_clear_ack_and_unprotected_post_ack_mutation_succeed(){
 let mut f=setup(false);let mut s=created(&mut f,30);future(&mut s,1,f.sc.ctx());passive(&mut s,f.sc.ctx());let id=object::id(&s);let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);acknowledge_future(&mut h);mutate_passive(lifecycle::handover_raw_mut_for_testing(&mut h));lifecycle::finish_handover(h,@0xc);
 f.sc.next_tx(@0xc);let s:Soul=f.sc.take_from_sender_by_id(id);assert!(character::generation(&s)==1 && standard::borrow_module<FutureWitness,FutureTool>(&s,b"future").epoch==1 && standard::borrow_module<PassiveWitness,PassiveTool>(&s,b"passive").value==1,208);f.sc.return_to_sender(s);end(f)
}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun unknown_future_protected_namespace_blocks_original_character_handover(){let mut f=setup(false);let mut s=created(&mut f,30);future(&mut s,1,f.sc.ctx());let r=character::revision(&s);character::handover(s,@0xc,r);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun app_ack_without_actual_vault_rotation_cannot_finish(){let mut f=setup(false);let mut s=created(&mut f,30);funded(&mut f,&mut s,70);let mut h=lifecycle::begin_handover(s);character::acknowledge_handover(&mut h);lifecycle::finish_handover(h,@0xc);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun post_ack_actual_application_grant_blocks_finish(){let mut f=setup(false);let s=created(&mut f,30);let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);grant(&mut f,lifecycle::handover_raw_mut_for_testing(&mut h));lifecycle::finish_handover(h,@0xc);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun protected_mutate_then_revert_blocks_descriptor_revision(){let mut f=setup(false);let mut s=created(&mut f,30);future(&mut s,1,f.sc.ctx());let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);acknowledge_future(&mut h);update_future(lifecycle::handover_raw_mut_for_testing(&mut h),9,1);update_future(lifecycle::handover_raw_mut_for_testing(&mut h),1,1);lifecycle::finish_handover(h,@0xc);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun wrong_supported_schema_cannot_acknowledge_actual_tool(){let mut f=setup(false);let mut s=created(&mut f,30);future(&mut s,2,f.sc.ctx());let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);lifecycle::acknowledge_handover<FutureWitness,FutureTool>(&mut h,FutureWitness{},b"future",1);lifecycle::finish_handover(h,@0xc);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun schema_drift_after_ack_blocks_finish(){let mut f=setup(false);let mut s=created(&mut f,30);future(&mut s,1,f.sc.ctx());let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);acknowledge_future(&mut h);update_future(lifecycle::handover_raw_mut_for_testing(&mut h),1,2);lifecycle::finish_handover(h,@0xc);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun new_protected_tool_after_snapshot_blocks_finish(){let mut f=setup(false);let s=created(&mut f,30);let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);future(lifecycle::handover_raw_mut_for_testing(&mut h),1,f.sc.ctx());lifecycle::finish_handover(h,@0xc);end(f)}
#[test,expected_failure(abort_code=8,location=soulidity_standard::soul)]
fun flagged_removable_declaration_cannot_uninstall(){let mut f=setup(false);let mut s=created(&mut f,30);future(&mut s,1,f.sc.ctx());let r=standard::revision(&s);let v=standard::uninstall<FutureWitness,FutureTool>(&mut s,b"future",r);transfer::public_transfer(v,@0xb);f.sc.return_to_sender(s);end(f)}
#[test,expected_failure(abort_code=6,location=soulidity_standard::soul)]
fun generic_install_cannot_downgrade_existing_required_tool(){let mut f=setup(false);let mut s=created(&mut f,30);future(&mut s,1,f.sc.ctx());let r=standard::revision(&s);standard::install(&mut s,FutureWitness{},b"future",FutureTool{id:object::new(f.sc.ctx()),epoch:0},1,true,h(10),r);f.sc.return_to_sender(s);end(f)}
#[test,expected_failure(abort_code=9,location=soulidity_standard::soul)]
fun protected_value_replacement_is_rejected(){let mut f=setup(false);let mut s=created(&mut f,30);future(&mut s,1,f.sc.ctx());let r=standard::revision(&s);let(v,t)=standard::begin_update<FutureWitness,FutureTool>(&mut s,FutureWitness{},b"future",r);transfer::public_transfer(v,@0xb);let replacement=FutureTool{id:object::new(f.sc.ctx()),epoch:0};standard::commit_update(&mut s,t,FutureWitness{},replacement,1,h(10));f.sc.return_to_sender(s);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun absent_app_descendant_unnest_cannot_escape_session(){let mut f=setup(false);let mut s=created(&mut f,30);let child=raw(f.sc.ctx());let id=object::id(&child);let r=standard::revision(&s);standard::nest(&mut s,child,r);let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);let root=lifecycle::handover_raw_mut_for_testing(&mut h);let r=standard::revision(root);let child=standard::unnest(root,id,r);transfer::public_transfer(child,@0xd);lifecycle::finish_handover(h,@0xc);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun same_id_unnest_reinsert_history_cannot_hide(){let mut f=setup(false);let mut s=created(&mut f,30);let child=raw(f.sc.ctx());let id=object::id(&child);let r=standard::revision(&s);standard::nest(&mut s,child,r);let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);let root=lifecycle::handover_raw_mut_for_testing(&mut h);let r=standard::revision(root);let child=standard::unnest(root,id,r);let r=standard::revision(root);standard::nest(root,child,r);lifecycle::finish_handover(h,@0xc);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun descendant_replacement_blocks_native_topology(){let mut f=setup(false);let mut s=created(&mut f,30);let child=raw(f.sc.ctx());let id=object::id(&child);let r=standard::revision(&s);standard::nest(&mut s,child,r);let mut h=lifecycle::begin_handover(s);acknowledge_known(&mut h);let root=lifecycle::handover_raw_mut_for_testing(&mut h);let r=standard::revision(root);let child=standard::unnest(root,id,r);transfer::public_transfer(child,@0xb);let r=standard::revision(root);standard::nest(root,raw(f.sc.ctx()),r);lifecycle::finish_handover(h,@0xc);end(f)}
fun composition(f:&mut F):lifecycle::ParentDelivery {
 let s=created(f,30);let source=producer::create(f.sc.ctx());let c=lifecycle::new(producer::witness_for_testing(),&source,producer::request<Soul>(&source,0,f.sc.ctx()),f.sc.ctx());let auth=producer::complete(&source,lifecycle::construction_ref(&c),lifecycle::construction_snapshot(&c),f.sc.ctx());let r=standard::revision(&s);let p=lifecycle::nest_into_parent(s,c,auth,r,f.sc.ctx());transfer::public_transfer(source,@0xb);p
}
#[test]
fun existing_protected_parent_same_actor_return_preserves_generation(){let mut f=setup(false);let p=composition(&mut f);let id=lifecycle::parent_id(&p);lifecycle::deliver_parent(p,@0xb,f.sc.ctx());f.sc.next_tx(@0xb);let s:Soul=f.sc.take_from_sender_by_id(id);assert!(character::generation(&s)==0,209);f.sc.return_to_sender(s);end(f)}
#[test]
fun existing_protected_parent_gift_via_full_handover_wrapper(){let mut f=setup(false);let p=composition(&mut f);let id=lifecycle::parent_id(&p);lifecycle::deliver_parent(p,@0xb,f.sc.ctx());f.sc.next_tx(@0xb);let s:Soul=f.sc.take_from_sender_by_id(id);custody_handover::handover(s,@0xc);f.sc.next_tx(@0xc);let s:Soul=f.sc.take_from_sender_by_id(id);assert!(character::generation(&s)==1,210);f.sc.return_to_sender(s);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun direct_existing_protected_parent_gift_is_refused(){let mut f=setup(false);let p=composition(&mut f);lifecycle::deliver_parent(p,@0xc,f.sc.ctx());end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun raw_existing_protected_child_under_fresh_construction_is_refused(){let mut f=setup(false);let s=created(&mut f,30);let source=producer::create(f.sc.ctx());let mut c=lifecycle::new(producer::witness_for_testing(),&source,producer::request<Soul>(&source,0,f.sc.ctx()),f.sc.ctx());standard::nest(lifecycle::construction_raw_mut_for_testing(&mut c),s,0);let auth=producer::complete(&source,lifecycle::construction_ref(&c),lifecycle::construction_snapshot(&c),f.sc.ctx());lifecycle::deliver(c,auth,@0xc,f.sc.ctx());transfer::public_transfer(source,@0xb);end(f)}
#[test,expected_failure(abort_code=12,location=soulidity_custody::lifecycle)]
fun nested_parent_delivery_false_freshness_cannot_be_laundered(){let mut f=setup(false);let p=composition(&mut f);let source=producer::create(f.sc.ctx());let mut c=lifecycle::new(producer::witness_for_testing(),&source,producer::request<Soul>(&source,0,f.sc.ctx()),f.sc.ctx());lifecycle::nest_parent_delivery(&mut c,p,0,f.sc.ctx());let auth=producer::complete(&source,lifecycle::construction_ref(&c),lifecycle::construction_snapshot(&c),f.sc.ctx());lifecycle::deliver(c,auth,@0xc,f.sc.ctx());transfer::public_transfer(source,@0xb);end(f)}
#[test]
fun construction_conversion_gifts_existing_protected_nested_child(){let mut f=setup(false);let s=created(&mut f,30);let sid=object::id(&s);let source=producer::create(f.sc.ctx());let mut c=lifecycle::new(producer::witness_for_testing(),&source,producer::request<Soul>(&source,0,f.sc.ctx()),f.sc.ctx());standard::creation_nest_owned(lifecycle::construction_mut(&mut c),s,0);let auth=producer::complete(&source,lifecycle::construction_ref(&c),lifecycle::construction_snapshot(&c),f.sc.ctx());let id=lifecycle::deliver(c,auth,@0xb,f.sc.ctx());transfer::public_transfer(source,@0xb);f.sc.next_tx(@0xb);let owned:Soul=f.sc.take_from_sender_by_id(id);custody_handover::handover(owned,@0xc);f.sc.next_tx(@0xc);let s:Soul=f.sc.take_from_sender_by_id(id);assert!(character::generation(standard::nested(&s,sid))==1,211);f.sc.return_to_sender(s);end(f)}

#[test]
fun full_maker_root_two_vault_siblings_both_rotate_with_funds_preserved(){
 let mut f=setup(false);let mut root=created(&mut f,30);grant(&mut f,&mut root);let mut a=raw(f.sc.ctx());let mut b=raw(f.sc.ctx());let aid=object::id(&a);let bid=object::id(&b);let rid=object::id(&root);let av=funded(&mut f,&mut a,70);let bv=funded(&mut f,&mut b,80);let ar=vault::private_receipt(&a,@0xb,0,h(73));let br=vault::private_receipt(&b,@0xb,0,h(83));let r=standard::revision(&root);standard::nest(&mut root,a,r);let r=standard::revision(&root);standard::nest(&mut root,b,r);
 custody_handover::handover(root,@0xc);f.sc.next_tx(@0xc);let root:Soul=f.sc.take_from_sender_by_id(rid);assert!(character::generation(&root)==1 && character::grant_count(&root)==0,212);assert_inventory(standard::nested(&root,aid),av,70,1,ar);assert_inventory(standard::nested(&root,bid),bv,80,1,br);f.sc.return_to_sender(root);end(f)
}
