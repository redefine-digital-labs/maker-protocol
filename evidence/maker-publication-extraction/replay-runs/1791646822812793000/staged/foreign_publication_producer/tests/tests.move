#[test_only]
module foreign_publication_producer::tests;
use std::bcs;
use std::string::{Self,String};
use sui::test_scenario::{Self,Scenario};
use soulidity_content_kinds::content_kind_registry::{Self as kind_registry,KindRegistry,KindAdminCap};
use soulidity_content_kinds::document_policy;
use soulidity_maker_publication::output_data::{Self,Policy,Intent,InitialRule,Selection,RecipeSlot,PayLine};
use soulidity_maker_publication::publication_validation as publication_rules;
use soulidity_foundation::economics::{Self,Config,PrimaryReceipt};
use soulidity_model::policy::{Self,Definition,Source,Layout,Adapter};
use soulidity_model::assembly::{Self,PartKey,ProfileSnapshot};
use soulidity_model::components;
use soulidity_visual::visual::{Self,Scene,ColorChoice};
use foreign_publication_producer::producer::{Self,Product,Target};
public struct USD has drop {}
fun h(n:u8):vector<u8>{vector::tabulate!(32,|_|n)}
fun layout():Layout{policy::layout(false,0,false,0,1000000,0,vector[])}
fun scene():Scene{visual::scene(1024,1024,visual::signed(false,0),visual::signed(false,0),0,h(14),b"body",b"pose",vector[b"main"],vector[visual::track(b"main",0,false)],vector[],vector[visual::anchor(b"root",vector[],visual::signed(false,0),visual::signed(false,0))],vector[])}
fun definition(rights:u8):Definition{
 let scene=scene();let fragment=visual::fragment(b"image",h(11),b"image/png",1024,1024,1024,0,0,1024,1024,512000,512000,b"main",0,b"root",visual::transform(visual::signed(false,0),visual::signed(false,0),1000000,visual::signed(false,0)),1000000,0,option::none(),option::none(),option::none(),vector[]);
 policy::definition(b"main",b"item",b"style",rights,h(11),h(12),visual::representation(&scene,1024,1024,vector[fragment],vector[]),10,layout(),policy::bounds(0,0,1000000,1000000,0,vector[]),vector[],vector[],true)
}
fun setup():(Scenario,KindRegistry,KindAdminCap,Config<USD>){
 let mut sc=test_scenario::begin(@0xa);kind_registry::init_for_testing(sc.ctx());let(c,a)=foreign_publication_producer::native_binding::create<USD>(sc.ctx());economics::share_config_for_testing(c,a,sc.ctx());sc.next_tx(@0xa);
 let r:KindRegistry=sc.take_shared();let cap:KindAdminCap=sc.take_from_sender();let cfg:Config<USD> =sc.take_shared();(sc,r,cap,cfg)
}
fun end(sc:Scenario,r:KindRegistry,cap:KindAdminCap,cfg:Config<USD>){test_scenario::return_shared(r);sc.return_to_sender(cap);test_scenario::return_shared(cfg);sc.end();}
fun publish(sc:&mut Scenario,p:Product,t:Target){transfer::public_transfer(p,@0xa);transfer::public_transfer(t,@0xa)}
fun rights(rights:u8){let(mut sc,r,cap,cfg)=setup();let mut p=producer::create(&cfg,definition(rights),sc.ctx());let t=producer::new_target(sc.ctx());let source=producer::preview(&p);let permit=producer::authorize(&mut p,&t);assert!(components::target(&permit)==object::id(&t),0);let(meta,item)=components::materialize(permit,object::id(&t),sc.ctx());assert!(meta==source && policy::source_type(&meta)==std::type_name::with_defining_ids<Product>() && producer::issued(&p)==1,1);assert!(item.is_some()==(rights==2),2);item.do!(|i|{assert!(*components::source(&i)==source,3);transfer::public_transfer(i,@0xa)});publish(&mut sc,p,t);end(sc,r,cap,cfg)}
#[test]fun foreign_reference_target_consumes_supply_without_item(){rights(0)}
#[test]fun foreign_bound_target_consumes_supply_without_item(){rights(1)}
#[test]fun foreign_free_target_consumes_supply_and_issues_exact_source(){rights(2)}
#[test,expected_failure(abort_code=3,location=soulidity_model::components)]
fun wrong_target_id_rejects_consumption(){let(mut sc,r,cap,cfg)=setup();let mut p=producer::create(&cfg,definition(2),sc.ctx());let t=producer::new_target(sc.ctx());let other=producer::new_target(sc.ctx());let(meta,item)=components::materialize(producer::authorize(&mut p,&t),object::id(&other),sc.ctx());let _=meta;item.do!(|i|transfer::public_transfer(i,@0xa));transfer::public_transfer(other,@0xa);publish(&mut sc,p,t);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=2,location=soulidity_model::components)]
fun copied_foreign_source_rejects_other_actual_product(){let(mut sc,r,cap,cfg)=setup();let p=producer::create(&cfg,definition(2),sc.ctx());let other=producer::create(&cfg,definition(2),sc.ctx());let t=producer::new_target(sc.ctx());let(meta,item)=components::materialize(producer::authorize_source(&p,&t,producer::preview(&other)),object::id(&t),sc.ctx());let _=meta;item.do!(|i|transfer::public_transfer(i,@0xa));transfer::public_transfer(other,@0xa);publish(&mut sc,p,t);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=1,location=soulidity_model::components)]
fun copied_source_is_not_producer_witness(){let(mut sc,r,cap,cfg)=setup();let p=producer::create(&cfg,definition(2),sc.ctx());let t=producer::new_target(sc.ctx());let s=producer::preview(&p);let(meta,item)=components::materialize(components::authorize(s,&p,&t,s),object::id(&t),sc.ctx());let _=meta;item.do!(|i|transfer::public_transfer(i,@0xa));publish(&mut sc,p,t);end(sc,r,cap,cfg)}
public struct ComponentProducer has drop {}
#[test,expected_failure(abort_code=1,location=soulidity_model::components)]
fun same_named_foreign_module_witness_rejected(){let(mut sc,r,cap,cfg)=setup();let p=producer::create(&cfg,definition(2),sc.ctx());let t=producer::new_target(sc.ctx());let s=producer::preview(&p);let(meta,item)=components::materialize(components::authorize(ComponentProducer{},&p,&t,s),object::id(&t),sc.ctx());let _=meta;item.do!(|i|transfer::public_transfer(i,@0xa));publish(&mut sc,p,t);end(sc,r,cap,cfg)}
#[test]fun registry_builtin_and_custom_reactivation_preserves_descriptor(){let(mut sc,mut r,mut cap,cfg)=setup();assert!(kind_registry::next_kind(&r)==16 && kind_registry::registry_version(&r)==1,0);let kind=kind_registry::register_kind(&mut r,&mut cap,string::utf8(b"custom"),1,3,false,false,2,sc.ctx());assert!(kind==16 && kind_registry::kind_for_name(&r,string::utf8(b"custom"))==16,1);kind_registry::deprecate_kind(&mut r,&mut cap,kind,sc.ctx());assert!(kind_registry::descriptor_deprecated(kind_registry::borrow_descriptor(&r,kind)),2);kind_registry::reactivate_kind(&mut r,&mut cap,kind,sc.ctx());let rule=output_data::initial_rule(&r,kind,string::utf8(b"custom"),3,0);assert!(output_data::rule_kind(&rule)==16 && output_data::rule_read(&rule)==3,3);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=15,location=soulidity_content_kinds::content_kind_registry)]
fun cap_registry_mismatch_rejected_before_name_validation(){let(mut sc,mut r,cap,cfg)=setup();let id=kind_registry::registry_id(&r);test_scenario::return_shared(r);sc.return_to_sender(cap);sc.next_tx(@0xb);kind_registry::init_for_testing(sc.ctx());sc.next_tx(@0xb);let mut r:KindRegistry=sc.take_shared_by_id(id);let mut other:KindAdminCap=sc.take_from_sender();let _=kind_registry::register_kind(&mut r,&mut other,string::utf8(b"!"),0,1,false,false,0,sc.ctx());end(sc,r,other,cfg)}
#[test,expected_failure(abort_code=3,location=soulidity_content_kinds::content_kind_registry)]
fun missing_kind_rejects_actual_registry(){let(sc,r,cap,cfg)=setup();let _=output_data::initial_rule(&r,900,string::utf8(b"valid"),1,0);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=1,location=soulidity_content_kinds::document_policy)]
fun founding_name_cannot_fork(){let(sc,r,cap,cfg)=setup();let _=output_data::initial_rule(&r,1,string::utf8(b"other"),3,0);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=2,location=soulidity_content_kinds::document_policy)]
fun owner_mode_required(){let(sc,r,cap,cfg)=setup();let _=output_data::initial_rule(&r,3,string::utf8(b"image"),8,0);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=2,location=soulidity_content_kinds::document_policy)]
fun private_memory_cannot_request_public(){let(sc,r,cap,cfg)=setup();let _=output_data::initial_rule(&r,1,document_policy::memory_name(),9,0);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=2,location=soulidity_content_kinds::document_policy)]
fun public_read_requires_public_download(){let(sc,r,cap,cfg)=setup();let _=output_data::initial_rule(&r,3,string::utf8(b"image"),9,1);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=2,location=soulidity_content_kinds::document_policy)]
fun private_kind_requires_zero_download(){let(sc,r,cap,cfg)=setup();let _=output_data::initial_rule(&r,2,string::utf8(b"skill"),3,1);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=3,location=soulidity_content_kinds::document_policy)]
fun deprecated_kind_precedes_invalid_read_mask(){let(mut sc,mut r,mut cap,cfg)=setup();kind_registry::deprecate_kind(&mut r,&mut cap,3,sc.ctx());let _=output_data::initial_rule(&r,3,string::utf8(b"image"),0,9);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=1,location=soulidity_maker_publication::output_data)]
fun duplicate_initials_rejected(){let(sc,r,cap,cfg)=setup();let d=output_data::initial_rule(&r,0,document_policy::soul_doc_name(),3,0);let m=output_data::initial_rule(&r,1,document_policy::memory_name(),3,0);let _=output_data::policy(b"p",false,vector[],h(14),true,vector[],vector[d,d,m]);end(sc,r,cap,cfg)}
#[test,expected_failure(abort_code=1,location=soulidity_model::policy)]
fun protected_policy_requires_scope(){let(sc,r,cap,cfg)=setup();let d=output_data::initial_rule(&r,0,document_policy::soul_doc_name(),3,0);let m=output_data::initial_rule(&r,1,document_policy::memory_name(),3,0);let _=output_data::policy(b"p",true,vector[],h(14),true,vector[],vector[d,m]);end(sc,r,cap,cfg)}
/// Explicit BCS preimage structures independently fix field order and domains.
public struct RulePreimage has drop {kind:u32,name:String,read_mask:u64,download_policy:u8}
public struct PolicyPreimage has drop {key:vector<u8>,protected:bool,scope:vector<u8>,renderer:vector<u8>,all_packs:bool,allowed_packs:vector<vector<u8>>,initials:vector<InitialRule>}
public struct IntentPreimage has drop {domain:vector<u8>,schema:u16,protocol:ID,maker:ID,maker_version:u64,policy_hash:vector<u8>,output_policy_hash:vector<u8>,actor:address,attempt:vector<u8>,name:String,recipe:vector<u8>,nonce:vector<u8>}
public struct SelectionPreimage has drop {source:Source,layout:Layout,adapter:Option<Adapter>}
public struct SlotPreimage has drop {part:PartKey,selection:Option<Selection>}
public struct RecipePreimage has drop {domain:vector<u8>,schema:u16,scene:vector<u8>,colors:vector<ColorChoice>,profiles:vector<ProfileSnapshot>,slots:vector<RecipeSlot>}
public struct NamespacePreimage has drop {domain:vector<u8>,schema:u16,intent:vector<u8>,kind:u32,name:String}
public struct LinePreimage has drop {product:ID,version:u64,policy_hash:vector<u8>,receipt:PrimaryReceipt}
public struct ReceiptPreimage has drop {lines:vector<PayLine>,total:u128,platform_recipient:address,fee_revision:u64}
#[test]fun all_nine_canonical_bcs_fields_domains_and_hashes_match_exact_preimages(){
 let(mut sc,r,cap,cfg)=setup();let p=producer::create(&cfg,definition(2),sc.ctx());let t=producer::new_target(sc.ctx());let scene=scene();let colors=visual::default_colors(&scene);let out=producer::output_policy(&r,h(14));let rules=output_data::initials(&out);let d=rules[0];assert!(bcs::to_bytes(&d)==bcs::to_bytes(&RulePreimage{kind:0,name:document_policy::soul_doc_name(),read_mask:3,download_policy:0}),0);
 let pb=bcs::to_bytes(&PolicyPreimage{key:b"foreign",protected:false,scope:vector[],renderer:h(14),all_packs:true,allowed_packs:vector[],initials:rules});assert!(bcs::to_bytes(&out)==pb && output_data::policy_hash(&out)==policy::hash_bytes(pb),1);
 let s=producer::preview(&p);let selection=output_data::selection(s,layout(),option::none());assert!(bcs::to_bytes(&selection)==bcs::to_bytes(&SelectionPreimage{source:s,layout:layout(),adapter:option::none()}),2);let slot=output_data::slot(b"main",option::some(selection));assert!(bcs::to_bytes(&slot)==bcs::to_bytes(&SlotPreimage{part:assembly::root_part(b"main"),selection:option::some(selection)}),3);
 let slots=vector[slot];let recipe=output_data::profile_recipe_hash(&scene,&colors,vector[],slots);assert!(recipe==policy::hash_bytes(bcs::to_bytes(&RecipePreimage{domain:b"soulidity-semantic-recipe",schema:2,scene:visual::scene_hash(&scene),colors,profiles:vector[],slots})),4);
 let i=output_data::intent(object::id(&cfg),object::id(&p),1,h(2),output_data::policy_hash(&out),@0xa,h(3),string::utf8(b"foreign"),recipe,vector::tabulate!(16,|_|4));let ib=bcs::to_bytes(&IntentPreimage{domain:b"soulidity-complete-intent",schema:1,protocol:object::id(&cfg),maker:object::id(&p),maker_version:1,policy_hash:h(2),output_policy_hash:output_data::policy_hash(&out),actor:@0xa,attempt:h(3),name:string::utf8(b"foreign"),recipe,nonce:vector::tabulate!(16,|_|4)});assert!(bcs::to_bytes(&i)==ib && output_data::intent_hash(&i)==policy::hash_bytes(ib),5);output_data::assert_intent(&i,object::id(&cfg),object::id(&p),1,h(2),&out,@0xa);
 assert!(output_data::content_id(&i,1,document_policy::memory_name())==bcs::to_bytes(&NamespacePreimage{domain:b"soulidity-complete-content",schema:1,intent:output_data::intent_hash(&i),kind:1,name:document_policy::memory_name()}),6);
 assert!(output_data::render_id(&i)==bcs::to_bytes(&NamespacePreimage{domain:b"soulidity-complete-render",schema:1,intent:output_data::intent_hash(&i),kind:0,name:string::utf8(vector[])}),7);assert!(output_data::recovery_id(&i)==bcs::to_bytes(&NamespacePreimage{domain:b"soulidity-upload-recovery",schema:1,intent:output_data::intent_hash(&i),kind:0,name:string::utf8(vector[])}),8);
 let quote=economics::primary_quote(&economics::primary_policy(&cfg),&cfg,101,true,@0xd,object::id(&p),h(2),@0xa,h(3),999);let line=output_data::pay_line(object::id(&p),1,h(2),quote);assert!(bcs::to_bytes(&line)==bcs::to_bytes(&LinePreimage{product:object::id(&p),version:1,policy_hash:h(2),receipt:quote}),9);let receipt=output_data::receipt(vector[line],@0xf,economics::revision(&cfg));let rb=bcs::to_bytes(&ReceiptPreimage{lines:vector[line],total:108,platform_recipient:@0xf,fee_revision:economics::revision(&cfg)});assert!(bcs::to_bytes(&receipt)==rb && output_data::receipt_hash(&receipt)==policy::hash_bytes(rb) && output_data::total_paid(&receipt)==108,10);
 assert!(publication_rules::validate_outputs(&vector[out])==0 && publication_rules::validate_outputs(&vector[out,out])==9,11);let(rows,code)=publication_rules::expected_assets(&vector[definition(0),definition(1),definition(2)]);assert!(code==0 && rows.length()==1 && publication_rules::expected_lookup(&rows,h(11))==option::some(1024),12);publish(&mut sc,p,t);end(sc,r,cap,cfg)
}

fun mismatched_cap(op:u8){let(mut sc,r,cap,cfg)=setup();let id=kind_registry::registry_id(&r);test_scenario::return_shared(r);sc.return_to_sender(cap);sc.next_tx(@0xb);kind_registry::init_for_testing(sc.ctx());sc.next_tx(@0xb);let mut r:KindRegistry=sc.take_shared_by_id(id);let mut other:KindAdminCap=sc.take_from_sender();if(op==0)kind_registry::deprecate_kind(&mut r,&mut other,3,sc.ctx()) else kind_registry::reactivate_kind(&mut r,&mut other,3,sc.ctx());end(sc,r,other,cfg)}
#[test,expected_failure(abort_code=15,location=soulidity_content_kinds::content_kind_registry)]
fun mismatched_cap_cannot_deprecate(){mismatched_cap(0)}
#[test,expected_failure(abort_code=15,location=soulidity_content_kinds::content_kind_registry)]
fun mismatched_cap_cannot_reactivate(){mismatched_cap(1)}
#[test]fun canonical_scope_bits_are_stable(){assert!(soulidity_content_kinds::content_permissions::scope_seal()==1 && soulidity_content_kinds::content_permissions::scope_memory()==2 && soulidity_content_kinds::content_permissions::scope_skills()==4 && soulidity_content_kinds::content_permissions::scope_assets()==8,0)}
