#[test_only]
module soulidity_maker_soul_adapter::maker_soul_tests;
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
#[test]
fun fresh_factory_paid_character_ref_bound_free_docs_output_and_owned_delivery(){
 let mut f=setup(true);buy_access(&mut f);let cfg=object::id(&f.cfg);let maker=object::id(&f.p);let i=intent(&f,30,recipe(&f));let mut b=begin_intent(&mut f,i);adapter::set_initial_state_config(&mut b,string::utf8(b"updater"),b"creator-value",&f.system,f.sc.ctx());select(&mut f,&mut b,false);initial(&mut f,&mut b,option::none());let id=finish(&mut f,b);
 assert!(catalog::protocol(&f.p)==cfg && revenue::root(catalog::income(&f.p))==maker && catalog::wallet_completes(&f.p,1,@0xb)==1 && revenue::balance(catalog::income(&f.p))==990 && revenue::balance(economics::income(&f.cfg))==117,101);
 f.sc.next_tx(@0xb);let mut soul:Soul=f.sc.take_from_sender_by_id(id);assert!(character::protocol(&soul)==cfg && character::maker(&soul)==maker && character::maker_version(&soul)==1 && standard::source_type(&standard::origin(&soul))==type_name::with_defining_ids<Product<USD>>() && standard::module_count(&soul)==1,102);
 assert!(character::reference_count(&soul)==1 && character::bound_count(&soul)==1 && character::free_id(&character::binding(&soul,b"free").destroy_some()).is_some() && character::free_id(&character::binding(&soul,b"ref").destroy_some()).is_none() && character::free_id(&character::binding(&soul,b"bound").destroy_some()).is_none(),103);
 let artifact=character::original_output(&soul);assert!(output::intent_hash(output::artifact_intent(artifact))==output::intent_hash(&i) && output::total_paid(output::artifact_receipt(artifact))==1007 && output::original_slot_count(artifact)==3 && character::content_count(&soul)==3,104);
 assert!(*character::state_config(&soul,string::utf8(b"updater"))==b"creator-value",105);let expected=character::revision(&soul);adapter::set_state_config(&mut soul,&f.cfg,string::utf8(b"updater"),b"owner-value",expected,f.sc.ctx());let expected=character::revision(&soul);adapter::delete_state_config(&mut soul,&f.cfg,string::utf8(b"updater"),expected,f.sc.ctx());assert!(!character::has_state_config(&soul,string::utf8(b"updater")),106);
 let mut n=0;while(n < 3){assert!(catalog::issued_count(&f.p,1,policy::definition_hash(&definition(vector[b"ref",b"bound",b"free"][n],n as u8)))==1,107);n=n+1};f.sc.return_to_sender(soul);end(f)
}
#[test]
fun free_complete_records_real_entitlement_and_real_character(){let mut f=setup(false);assert!(!catalog::access_held(&f.p,1,@0xb),108);let id=complete(&mut f,30);assert!(catalog::access_held(&f.p,1,@0xb) && revenue::balance(catalog::income(&f.p))==0 && revenue::balance(economics::income(&f.cfg))==0,109);f.sc.next_tx(@0xb);let s:Soul=f.sc.take_from_sender_by_id(id);assert!(character::content_count(&s)==3 && character::semantic_recipe_hash(&s)==recipe(&f),110);f.sc.return_to_sender(s);end(f)}
#[test,expected_failure(abort_code=4,location=soulidity_maker_manufacturing::maker_catalog)]
fun paid_access_cannot_auto_claim(){let mut f=setup(true);complete(&mut f,30);end(f)}
#[test,expected_failure(abort_code=7,location=soulidity_maker_manufacturing::maker_catalog)]
fun completed_attempt_cannot_replay(){let mut f=setup(false);complete(&mut f,30);complete(&mut f,30);end(f)}
#[test,expected_failure(abort_code=5,location=soulidity_maker_soul_adapter::maker_soul)]
fun missing_founding_document_aborts(){let mut f=setup(false);let mut b=begin(&mut f,30);select(&mut f,&mut b,false);initial(&mut f,&mut b,option::some(0));finish(&mut f,b);end(f)}
#[test,expected_failure(abort_code=5,location=soulidity_maker_soul_adapter::maker_soul)]
fun missing_memory_aborts(){let mut f=setup(false);let mut b=begin(&mut f,30);select(&mut f,&mut b,false);initial(&mut f,&mut b,option::some(1));finish(&mut f,b);end(f)}
#[test,expected_failure(abort_code=6,location=soulidity_maker_soul_adapter::maker_soul)]
fun changed_recipe_cannot_use_original_intent(){let mut f=setup(false);let mut b=begin(&mut f,30);select(&mut f,&mut b,true);initial(&mut f,&mut b,option::none());finish(&mut f,b);end(f)}
#[test,expected_failure(abort_code=3,location=soulidity_foundation::economics)]
fun clock_expiry_after_funding_aborts_finish(){let mut f=setup(false);let mut b=begin(&mut f,30);select(&mut f,&mut b,false);initial(&mut f,&mut b,option::none());clock::increment_for_testing(&mut f.clock,1001);finish(&mut f,b);end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun original_config_mutation_after_funding_aborts(){let mut f=setup(false);let mut b=begin(&mut f,30);select(&mut f,&mut b,false);initial(&mut f,&mut b,option::none());let rev=economics::revision(&f.cfg);let hash=economics::commitment(&f.cfg);economics::set_primary_enabled(&mut f.cfg,&mut f.admin,rev,hash,false);finish(&mut f,b);end(f)}
#[test,expected_failure(abort_code=13,location=soulidity_application::character)]
fun native_operator_character_cannot_use_manufacturing_owner_config(){
 let mut f=setup_route(false,true);let rev=economics::revision(&f.cfg);let exp=expiry(&f);let hash=catalog::policy_hash(catalog::published(&f.p,1));{let F{sc,p,cfg,system,clock,..}=&mut f;factory::claim_access(p,cfg,1,hash,rev,exp,h(20),system,clock,sc.ctx())};
 let mut native_build={let F{sc,cfg,p,system,clock,..}=&mut f;native_operator_fixture::begin(p,cfg,h(30),exp,coin::zero<USD>(sc.ctx()),clock,system,sc.ctx())};adapter::set_state_config_creation(native_operator_fixture::root_mut(&mut native_build),&f.cfg,string::utf8(b"updater"),b"foreign",0,f.sc.ctx());native_operator_fixture::finish(native_build,&f.cfg,&f.clock,&f.system,f.sc.ctx());end(f)
}
#[test,expected_failure(abort_code=13,location=soulidity_application::character)]
fun native_operator_character_cannot_use_manufacturing_owner_config_delete(){
 let mut f=setup_route(false,true);let rev=economics::revision(&f.cfg);let exp=expiry(&f);let hash=catalog::policy_hash(catalog::published(&f.p,1));{let F{sc,p,cfg,system,clock,..}=&mut f;factory::claim_access(p,cfg,1,hash,rev,exp,h(20),system,clock,sc.ctx())};
 let mut native_build={let F{sc,cfg,p,system,clock,..}=&mut f;native_operator_fixture::begin(p,cfg,h(30),exp,coin::zero<USD>(sc.ctx()),clock,system,sc.ctx())};adapter::delete_state_config_creation(native_operator_fixture::root_mut(&mut native_build),&f.cfg,string::utf8(b"updater"),0,f.sc.ctx());native_operator_fixture::finish(native_build,&f.cfg,&f.clock,&f.system,f.sc.ctx());end(f)
}
fun setup_pack(f:&mut F,price:u64):(Product<USD>,Control){
 f.sc.next_tx(@0xa);let id=factory::create_pack(&f.p,1,&mut f.control,&f.cfg,0,&f.system,f.sc.ctx());f.sc.next_tx(@0xa);let mut pack:Product<USD> =f.sc.take_shared_by_id(id);let mut control:Control=f.sc.take_from_sender();
 let seed=catalog::with_pack_key(adapter::with_execution(catalog::version(h(4),h(5),2,0,if(price==0)0 else 1,price,0,0,0,@0xd,maker_resale::rates(0,0),vector[b"cape"],vector[],vector[],vector[],pack_scene())),b"pack");
 let mut m=metadata::start(&pack,&mut control,&f.cfg,0,seed,&f.system,f.sc.ctx());metadata::append_definitions(&mut m,&pack,&mut control,&f.cfg,vector[definition_at(b"cape",b"pack-style",2),definition_at(b"cape",b"pack-alternate",2)],&f.system,0,f.sc.ctx());let hash=metadata::policy_hash(&m);let living=storage::blob(&mut f.system,110,false,true,f.sc.ctx());let manifest=storage::blob(&mut f.system,111,false,true,f.sc.ctx());let mut draft=metadata::begin_publication(m,&pack,&mut control,&f.cfg,1,hash,release::author(b"Pack",vector[],vector[],b"license",h(3)),living,manifest,&f.system,f.sc.ctx());let blob=storage::blob(&mut f.system,112,false,true,f.sc.ctx());release::append(&mut draft,&pack,&mut control,&f.cfg,h(11),false,h(11),blob,&f.system,0,f.sc.ctx());release::finish(draft,&mut pack,&mut control,&f.cfg,&f.system,1,f.sc.ctx());test_scenario::return_shared(pack);test_scenario::return_to_address(@0xa,control);f.sc.next_tx(@0xb);(f.sc.take_shared_by_id(id),f.sc.take_from_address(@0xa))
}
fun create_player(f:&mut F):Player{
 let rev=economics::revision(&f.cfg);let exp=expiry(f);let id={let F{sc,p,cfg,system,clock,..}=f;factory::create_player(p,cfg,1,rev,exp,h(21),system,clock,sc.ctx())};f.sc.next_tx(@0xb);let mut p:Player=f.sc.take_from_sender_by_id(id);let parts=vector[b"ref",b"bound",b"free"];let mut n=0;while(n < 3){let definition=policy::definition_hash(&definition(parts[n],n as u8));let F{sc,p:maker,cfg,system,clock,..}=f;factory::set_player_base(&mut p,maker,cfg,definition,layout(),n,rev,exp,system,clock,sc.ctx());n=n+1};p
}
fun include_pack(f:&mut F,b:&mut Build,pack:&mut Product<USD>,price:u64){let exp=expiry(f);let rev=economics::revision(&f.cfg);let hash=catalog::policy_hash(catalog::published(pack,1));let F{sc,p:maker,cfg,system,clock,..}=f;adapter::include_pack(b,pack,maker,cfg,1,hash,rev,exp,coin::mint_for_testing<USD>(price,sc.ctx()),clock,system,sc.ctx())}
#[test]
fun genuine_paid_pack_player_colors_complete_then_pack_enhancement(){
 let mut f=setup(true);buy_access(&mut f);let(mut pack,control)=setup_pack(&mut f,333);let mut p=create_player(&mut f);let exp=expiry(&f);let rev=economics::revision(&f.cfg);factory::set_player_pack(&mut p,&f.p,&pack,&f.cfg,1,policy::definition_hash(&definition_at(b"cape",b"pack-style",2)),layout(),3,rev,exp,&f.system,&f.clock,f.sc.ctx());player::set_colors(&mut p,vector[visual::color_choice(b"skin",b"blue")],4,f.sc.ctx());
 let i=intent(&f,30,player::semantic_recipe_hash(&p));let mut b=begin_intent(&mut f,i);include_pack(&mut f,&mut b,&mut pack,333);player::parts(&p).do!(|part|{let selected=player::scoped_selection(&p,part);if(selected.is_some()){let source=player::source(selected.borrow());if(policy::source_product(source)==object::id(&f.p)){let F{sc,p:maker,cfg,system,..}=&mut f;adapter::select_player_scoped(&mut b,maker,&p,part,5,cfg,system,sc.ctx())}else{let F{sc,cfg,system,..}=&mut f;adapter::select_player_scoped(&mut b,&mut pack,&p,part,5,cfg,system,sc.ctx())}}});initial(&mut f,&mut b,option::none());let id=finish(&mut f,b);let scope=assembly::profile_scope(&catalog::assembly_profile(&pack,1));let part=assembly::scoped_part(scope,b"cape");player::close(p,5,f.sc.ctx());
 assert!(catalog::wallet_completes(&pack,1,@0xb)==1 && revenue::balance(catalog::income(&pack))==300 && revenue::balance(economics::income(&f.cfg))==150,111);f.sc.next_tx(@0xb);let mut s:Soul=f.sc.take_from_sender_by_id(id);assert!(character::colors(&s)==vector[visual::color_choice(b"skin",b"blue")] && output::pay_lines(output::artifact_receipt(character::original_output(&s))).length()==2 && output::total_paid(output::artifact_receipt(character::original_output(&s)))==1340,112);
 let old=character::free_id(&character::binding_scoped(&s,part).destroy_some()).destroy_some();let expected=character::revision(&s);let hash=catalog::policy_hash(catalog::published(&pack,1));let choices=vector[adapter::purchase(policy::definition_hash(&definition_at(b"cape",b"pack-alternate",2)),part,layout())];let exp=expiry(&f);let returned={let F{sc,p:maker,cfg,clock,system,..}=&mut f;adapter::enhance_pack(&mut s,&mut pack,maker,cfg,1,expected,hash,choices,h(31),rev,exp,coin::mint_for_testing<USD>(333,sc.ctx()),clock,system,sc.ctx())};assert!(returned.length()==1 && object::id(&returned[0])==old && character::free_id(&character::binding_scoped(&s,part).destroy_some())!=option::some(old) && output::total_paid(output::artifact_receipt(character::original_output(&s)))==1340 && catalog::wallet_completes(&pack,1,@0xb)==2 && revenue::balance(catalog::income(&pack))==600 && revenue::balance(economics::income(&f.cfg))==183,113);returned.do!(|item|transfer::public_transfer(item,@0xb));f.sc.return_to_sender(s);test_scenario::return_shared(pack);test_scenario::return_to_address(@0xa,control);end(f)
}
#[test]
fun genuine_maker_enhancement_returns_original_free_item_without_second_fixed_fee(){
 let mut f=setup(true);buy_access(&mut f);let id=complete(&mut f,30);f.sc.next_tx(@0xb);let mut s:Soul=f.sc.take_from_sender_by_id(id);let old=character::free_id(&character::binding(&s,b"free").destroy_some()).destroy_some();let original=output::intent_hash(output::artifact_intent(character::original_output(&s)));let expected=character::revision(&s);let hash=catalog::policy_hash(catalog::published(&f.p,1));let choices=vector[adapter::purchase(policy::definition_hash(&definition_at(b"free",b"alternate-style",2)),assembly::root_part(b"free"),layout())];let exp=expiry(&f);let rev=economics::revision(&f.cfg);
 let returned={let F{sc,p,cfg,system,clock,..}=&mut f;adapter::enhance_maker(&mut s,p,cfg,expected,hash,choices,h(31),rev,exp,coin::mint_for_testing<USD>(1000,sc.ctx()),clock,system,sc.ctx())};assert!(returned.length()==1 && object::id(&returned[0])==old && character::free_id(&character::binding(&s,b"free").destroy_some())!=option::some(old) && original==output::intent_hash(output::artifact_intent(character::original_output(&s))) && catalog::wallet_completes(&f.p,1,@0xb)==2 && revenue::balance(catalog::income(&f.p))==1890 && revenue::balance(economics::income(&f.cfg))==217,114);returned.do!(|it|transfer::public_transfer(it,@0xb));f.sc.return_to_sender(s);end(f)
}
fun attempt_rebuy_held(part:vector<u8>,rights:u8){
 let mut f=setup(true);buy_access(&mut f);let id=complete(&mut f,30);f.sc.next_tx(@0xb);let mut s:Soul=f.sc.take_from_sender_by_id(id);let expected=character::revision(&s);let hash=catalog::policy_hash(catalog::published(&f.p,1));let choices=vector[adapter::purchase(policy::definition_hash(&definition(part,rights)),assembly::root_part(part),layout())];let exp=expiry(&f);let rev=economics::revision(&f.cfg);
 let returned={let F{sc,p,cfg,system,clock,..}=&mut f;adapter::enhance_maker(&mut s,p,cfg,expected,hash,choices,h(31),rev,exp,coin::mint_for_testing<USD>(1000,sc.ctx()),clock,system,sc.ctx())};returned.do!(|item|transfer::public_transfer(item,@0xb));f.sc.return_to_sender(s);end(f)
}
#[test,expected_failure(abort_code=11,location=soulidity_application::character)]
fun paid_enhancement_cannot_rebuy_held_reference(){attempt_rebuy_held(b"ref",0)}
#[test,expected_failure(abort_code=11,location=soulidity_application::character)]
fun paid_enhancement_cannot_rebuy_held_bound(){attempt_rebuy_held(b"bound",1)}
#[test,expected_failure(abort_code=1,location=soulidity_maker_manufacturing::maker_release)]
fun fresh_service_config_cannot_rebind_original_product(){
 let mut f=setup(false);let release:RoleCertificate<ReleaseInstaller1,ReleaseRevision3> =f.sc.take_immutable();let creator:RoleCertificate<CreatorAuthority1,CreatorRevision3> =f.sc.take_immutable();let(mut fresh,mut admin)=factory::new_service<USD>(&release,&creator,1000,500,0,@0xf,&f.system,h(82),h(83),f.sc.ctx());test_scenario::return_immutable(release);test_scenario::return_immutable(creator);let rev=economics::revision(&fresh);let hash=economics::commitment(&fresh);economics::set_primary_enabled(&mut fresh,&mut admin,rev,hash,true);let rev=economics::revision(&fresh);let hash=economics::commitment(&fresh);release::activate(&mut fresh,&mut admin,&f.system,rev,hash);
 assert!(catalog::protocol(&f.p)==object::id(&f.cfg) && object::id(&fresh)!=object::id(&f.cfg),115);let i=intent(&f,30,recipe(&f));let exp=expiry(&f);let rev=economics::revision(&fresh);let b={let F{sc,p,clock,system,..}=&mut f;adapter::begin(p,&mut fresh,i,b"default",rev,exp,coin::zero<USD>(sc.ctx()),clock,system,sc.ctx())};finish(&mut f,b);economics::finalize_manufacturing_instance(fresh,admin,f.sc.ctx());end(f)
}
#[test,expected_failure(abort_code=4,location=soulidity_maker_soul_adapter::maker_soul)]
fun paid_pack_without_selection_cannot_finish(){let mut f=setup(false);let(mut pack,control)=setup_pack(&mut f,333);let mut b=begin(&mut f,30);include_pack(&mut f,&mut b,&mut pack,333);select(&mut f,&mut b,false);initial(&mut f,&mut b,option::none());finish(&mut f,b);test_scenario::return_shared(pack);f.sc.return_to_sender(control);end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_maker_soul_adapter::maker_soul)]
fun duplicate_pack_contribution_cannot_settle_twice(){let mut f=setup(false);let(mut pack,control)=setup_pack(&mut f,333);let mut b=begin(&mut f,30);include_pack(&mut f,&mut b,&mut pack,333);include_pack(&mut f,&mut b,&mut pack,333);select(&mut f,&mut b,false);initial(&mut f,&mut b,option::none());finish(&mut f,b);test_scenario::return_shared(pack);f.sc.return_to_sender(control);end(f)}

/// Real paid source flow reaches the protected completion guard after actual
/// settlement and three authored supply actions. VM rejection is evidence of
/// the late guard; post-abort chain rollback readback is a separate later gate.
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun paid_funded_supplied_creation_cannot_finish_after_config_revocation(){
 let mut f=setup(true);buy_access(&mut f);let mut b=begin(&mut f,30);select(&mut f,&mut b,false);initial(&mut f,&mut b,option::none());
 assert!(revenue::balance(catalog::income(&f.p))==990 && revenue::balance(economics::income(&f.cfg))==117,301);
 let names=vector[b"ref",b"bound",b"free"];let mut i=0;while(i < 3){assert!(catalog::issued_count(&f.p,1,policy::definition_hash(&definition(names[i],i as u8)))==1,302);i=i+1};
 let rev=economics::revision(&f.cfg);let hash=economics::commitment(&f.cfg);economics::set_primary_enabled(&mut f.cfg,&mut f.admin,rev,hash,false);finish(&mut f,b);end(f)
}
#[test,expected_failure(abort_code=3,location=soulidity_foundation::economics)]
fun paid_funded_supplied_creation_cannot_finish_after_expiry(){
 let mut f=setup(true);buy_access(&mut f);let mut b=begin(&mut f,30);select(&mut f,&mut b,false);initial(&mut f,&mut b,option::none());
 assert!(revenue::balance(catalog::income(&f.p))==990 && revenue::balance(economics::income(&f.cfg))==117,303);
 assert!(catalog::issued_count(&f.p,1,policy::definition_hash(&definition(b"free",2)))==1,304);
 clock::increment_for_testing(&mut f.clock,1001);finish(&mut f,b);end(f)
}
