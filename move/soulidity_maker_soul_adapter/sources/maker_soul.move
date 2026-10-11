/// Complete canonical Maker -> Character construction, with owned Standard delivery.
/// Execution values and unfinished construction remain private to this package.
module soulidity_maker_soul_adapter::maker_soul;
use soulidity_custody::lifecycle;
use std::string::String;
use sui::coin::{Self,Coin};
use sui::clock::{Self,Clock};
use walrus::blob::Blob;
use walrus::system::{Self,System};
use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,Self as manufacture,Product,Version,Session};
use soulidity_maker_manufacturing::maker_factory as factory;
use soulidity_maker_manufacturing::maker_release as release;
use soulidity_maker_manufacturing::maker_player::{Self as player,Player};
use soulidity_foundation::economics::{Self,Config};
use soulidity_origin_protocol::producer_origin as origin;
use soulidity_maker_admission::maker_issuance as admission;
use soulidity_standard::soul::{Self as standard,Soul};
use soulidity_custody::lifecycle::{Construction};
use soulidity_application::character as soul;
use soulidity_application::output;
use soulidity_maker_publication::output_data::{Intent,Policy,PayLine};
use soulidity_content_kinds::content_kind_registry::KindRegistry;
use soulidity_model::policy::{Self,Layout};
use soulidity_model::assembly::{Self,PartKey,Scope};
use soulidity_visual::visual::ColorChoice;
const EPayment:u64=3;const EChoices:u64=7;const EProduct:u64=1;const EActor:u64=2;const EUnused:u64=4;const EInitial:u64=5;const ERecipe:u64=6;const ESystem:u64=8;
public struct MakerSoulAuthority1 has drop {}
public struct MakerSoulRevision1 has drop {}
fun authority():MakerSoulAuthority1{MakerSoulAuthority1{}}
fun revision():MakerSoulRevision1{MakerSoulRevision1{}}
public fun with_execution(v:Version):Version{catalog::with_execution<MakerSoulAuthority1,MakerSoulRevision1,Soul>(v,authority(),revision())}
fun ensure_access<C>(p:&mut Product<C>,cfg:&Config<C>,version:u64,attempt:vector<u8>,rev:u64,expiry:u64,clock:&Clock,system:&System,ctx:&mut TxContext){
    catalog::assert_access(p,version,ctx.sender());
    if(!catalog::access_held(p,version,ctx.sender())){let hash=catalog::policy_hash(catalog::published(p,version));factory::claim_access(p,cfg,version,hash,rev,expiry,attempt,system,clock,ctx)}
}
fun assert_access_time<C>(p:&Product<C>,version:u64,clock:&Clock,ctx:&TxContext){catalog::access_record(p,version,ctx.sender()).do_ref!(|a|assert!(catalog::access_issued_at(a)<=clock::timestamp_ms(clock),EProduct))}
fun assert_access<C>(p:&Product<C>,cfg:&Config<C>,version:u64,rev:u64,clock:&Clock,ctx:&TxContext){economics::assert_manufacturing_snapshot(cfg,catalog::protocol(p),rev,economics::commitment(cfg));catalog::assert_access(p,version,ctx.sender());assert_access_time(p,version,clock,ctx)}
public struct Contribution has copy,drop {product:ID,version:u64,used:u64}
/// No key, store or drop: unfinished assemblies cannot survive transaction execution.
public struct Assembly {
    construction:Construction,sessions:vector<Session>,draft:soulidity_application::character::Draft,actor:address,maker:ID,maker_version:u64,protocol:ID,
    attempt:vector<u8>,contributions:vector<Contribution>,intent:Intent,output_policy:Policy,pay_lines:vector<PayLine>,platform_recipient:address,fee_revision:u64,
}

fun begin_assembly<C>(maker:&mut Product<C>,cfg:&mut Config<C>,intent:Intent,output_key:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,system:&System,ctx:&mut TxContext):Assembly {
    let version=output::intent_version(&intent);let policy_hash=output::intent_policy(&intent);let attempt=output::intent_attempt(&intent);let name=output::intent_name(&intent);
    assert!(catalog::parent(maker).is_none() && catalog::protocol(maker)==object::id(cfg),EProduct);
    assert!(name.length()>0 && name.length()<=128,EProduct);
    economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock);
    ensure_access(maker,cfg,version,attempt,fee_revision,expiry,clock,system,ctx);
    assert_access(maker,cfg,version,fee_revision,clock,ctx);
    let v=*catalog::published(maker,version);let output_policy=catalog::output_policy(&v,output_key);output::assert_intent(&intent,object::id(cfg),object::id(maker),version,policy_hash,&output_policy,ctx.sender());
    let(request,witness)=factory::request_with_witness<C,MakerSoulAuthority1,MakerSoulRevision1,Soul>(maker,cfg,version,policy_hash,name,attempt,expiry,authority(),revision(),system,clock,ctx);let snapshot=origin::snapshot(&request);let mut construction=lifecycle::new(witness,maker,request,ctx);
    let mut session=factory::begin(maker,lifecycle::construction_ref(&construction),cfg,snapshot,payment,authority(),revision(),system,clock,ctx);let receipt=manufacture::session_receipt(&session);let action=manufacture::take_action(&mut session,maker,lifecycle::construction_ref(&construction),ctx);
    let resale=soulidity_maker_terms::maker_resale::snapshot(object::id(cfg),object::id(maker),version,policy_hash,catalog::creator(maker),catalog::soul_rates(&v),ctx);let profile=catalog::assembly_profile(maker,version);let metadata=soul::genesis_hash(object::id(cfg),object::id(maker),version,catalog::manifest(&v),catalog::configuration(&v),profile,catalog::required_parts(&v),catalog::adapters(&v),*catalog::scene(&v),resale,catalog::beneficiary(&v),ctx);
    let genesis=admission::authorize_manufacturing_genesis_action(cfg,maker,lifecycle::construction_ref(&construction),action,receipt,metadata,authority(),revision(),ctx);
    let draft=soul::initialize_creation(genesis,lifecycle::construction_mut(&mut construction),object::id(cfg),object::id(maker),version,catalog::manifest(&v),catalog::configuration(&v),profile,catalog::required_parts(&v),catalog::adapters(&v),*catalog::scene(&v),resale,catalog::beneficiary(&v),ctx);
    let primary=catalog::version_primary(&v);
    let line=output::pay_line(object::id(maker),version,policy_hash,receipt);
    Assembly{construction,sessions:vector[session],draft,actor:ctx.sender(),maker:object::id(maker),maker_version:version,protocol:object::id(cfg),attempt,contributions:vector[Contribution{product:object::id(maker),version,used:0}],intent,output_policy,pay_lines:vector[line],platform_recipient:economics::primary_policy_platform(&primary),fee_revision}
}

/// Pack fees/counts are charged once; finish refuses an included Pack with no selection.
fun include_pack_assembly<C>(b:&mut Assembly,pack:&mut Product<C>,maker:&Product<C>,cfg:&mut Config<C>,version:u64,policy_hash:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,system:&System,ctx:&mut TxContext) {
    actor(b,ctx);
    assert!(b.fee_revision==fee_revision && b.protocol==object::id(cfg) && catalog::protocol(pack)==b.protocol && object::id(maker)==b.maker,EProduct);
    assert!(!b.contributions.any!(|c| c.product==object::id(pack)),EProduct);
    economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock);
    economics::assert_manufacturing_snapshot(cfg,b.protocol,fee_revision,economics::commitment(cfg));catalog::assert_pack(pack,maker,b.maker_version,version,ctx.sender());assert_access_time(pack,version,clock,ctx);assert_access_time(maker,b.maker_version,clock,ctx);
    let v=*catalog::published(pack,version);output::assert_pack(&b.output_policy,catalog::pack_key(&v));
    let primary=catalog::version_primary(&v);assert!(economics::primary_policy_platform(&primary)==b.platform_recipient,EProduct);
    let snapshot=factory::request_contribution(pack,lifecycle::construction_ref(&b.construction),cfg,version,policy_hash,origin::name(&lifecycle::construction_snapshot(&b.construction)),b.attempt,expiry,authority(),revision(),system,clock,ctx);let mut session=factory::begin_pack(pack,maker,lifecycle::construction_ref(&b.construction),cfg,snapshot,payment,authority(),revision(),system,clock,ctx);let paid=manufacture::session_receipt(&session);let action=manufacture::take_action(&mut session,pack,lifecycle::construction_ref(&b.construction),ctx);let contribution=admission::authorize_manufacturing_contribution_action(cfg,pack,lifecycle::construction_ref(&b.construction),action,paid,authority(),revision(),ctx);
    let receipt=soul::admit_contribution_creation(&b.draft,lifecycle::construction_mut(&mut b.construction),contribution,catalog::assembly_profile(pack,version),ctx);b.sessions.push_back(session);
    b.contributions.push_back(Contribution{product:object::id(pack),version,used:0});b.pay_lines.push_back(output::pay_line(object::id(pack),version,policy_hash,receipt));
}

fun select_scoped_assembly<C>(b:&mut Assembly,product:&mut Product<C>,definition_hash:vector<u8>,part:soulidity_model::assembly::PartKey,layout:Layout,ctx:&mut TxContext) {
    actor(b,ctx);assert!(catalog::protocol(product)==b.protocol,EProduct);
    let index=contribution_index(b,object::id(product));
    let (source,selection)=manufacture::select(&mut b.sessions[index],product,lifecycle::construction_ref(&b.construction),definition_hash,ctx);
    soul::add_issued_creation(&b.draft,lifecycle::construction_mut(&mut b.construction),source,part,layout,ctx);manufacture::selected(&mut b.sessions[index],selection,lifecycle::construction_ref(&b.construction),authority(),revision(),ctx);
    b.contributions[index].used=b.contributions[index].used+1;
}
/// Complete may consume the same actual Player selection used by Physical.
/// This is the first OC issuance; copying a Player selection never issues rights.
fun select_player_scoped_assembly<C>(b:&mut Assembly,product:&mut Product<C>,p:&Player,part:soulidity_model::assembly::PartKey,expected_player:u64,ctx:&mut TxContext) {
    actor(b,ctx);player::assert_owner(p,expected_player,ctx);assert!(player::maker(p)==b.maker && player::maker_version(p)==b.maker_version && player::protocol(p)==b.protocol,EProduct);
    let selected=player::scoped_selection(p,part).destroy_some();let source=player::source(&selected);let c=contribution_index(b,object::id(product));
    assert!(policy::source_product(source)==object::id(product) && policy::source_version(source)==b.contributions[c].version && catalog::preview_source(product,b.contributions[c].version,policy::source_definition_hash(source))==*source,EProduct);
    soul::set_initial_colors_creation(&b.draft,lifecycle::construction_mut(&mut b.construction),player::colors(p),ctx);player::profiles(p).do_ref!(|profile|{let scope=soulidity_model::assembly::snapshot_scope(profile);if(soul::profile_snapshots(lifecycle::construction_ref(&b.construction)).any!(|x|soulidity_model::assembly::snapshot_scope(x)==scope))soul::set_initial_pack_colors_creation(&b.draft,lifecycle::construction_mut(&mut b.construction),scope,player::pack_colors(p,scope),ctx)});select_scoped_assembly(b,product,policy::source_definition_hash(source),part,player::layout(&selected),ctx)
}

fun append_initial_content_assembly(b:&mut Assembly,registry:&KindRegistry,kind:u32,name:String,blob:Blob,system:&System,sha256:vector<u8>,envelope:vector<u8>,clock:&Clock,ctx:&TxContext):u64 {
    actor(b,ctx);let rule=output::rule(&b.output_policy,kind,name);
    soul::append_initial_output_content_creation(&b.draft,lifecycle::construction_mut(&mut b.construction),registry,&rule,&b.intent,blob,system,sha256,envelope,clock,ctx)
}
fun set_initial_state_config_assembly(b:&mut Assembly,key:String,value:vector<u8>,ctx:&mut TxContext){
    actor(b,ctx);soul::set_initial_state_config_creation(&b.draft,lifecycle::construction_mut(&mut b.construction),key,value,ctx)
}
/// Production finalization rechecks the same Config/Clock before Standard delivery.
fun finish_live_assembly<C>(b:Assembly,cfg:&Config<C>,clock:&Clock,render:Blob,system:&System,sha256:vector<u8>,envelope:vector<u8>,ctx:&mut TxContext):ID{
    let (construction,mut sessions,recipient)=prepare_finish(b,render,system,sha256,envelope,ctx);
    while(sessions.length()>1){let session=sessions.pop_back();let snapshot=manufacture::session_snapshot(&session);let completion=factory::finish(session,lifecycle::construction_ref(&construction),cfg,authority(),revision(),system,clock,ctx);origin::consume_completion<MakerSoulAuthority1,MakerSoulRevision1,Soul>(completion,lifecycle::construction_ref(&construction),&snapshot,ctx)};
    let session=sessions.pop_back();sessions.destroy_empty();let completion=factory::finish(session,lifecycle::construction_ref(&construction),cfg,authority(),revision(),system,clock,ctx);lifecycle::deliver(construction,completion,recipient,ctx)
}
fun prepare_finish(b:Assembly,render:Blob,system:&System,sha256:vector<u8>,envelope:vector<u8>,ctx:&mut TxContext):(Construction,vector<Session>,address){
    actor(&b,ctx);let mut i=1;while(i < b.contributions.length()){assert!(b.contributions[i].used>0,EUnused);i=i+1};
    output::initials(&b.output_policy).do_ref!(|r|assert!(soul::content_index(lifecycle::construction_ref(&b.construction),output::rule_kind(r),output::rule_name(r),0).is_some(),EInitial));let recipe=soul::semantic_recipe(lifecycle::construction_ref(&b.construction));assert!(soul::semantic_recipe_hash(lifecycle::construction_ref(&b.construction))==output::intent_recipe(&b.intent),ERecipe);
    let Assembly{mut construction,sessions,draft,actor,maker:_,maker_version:_,protocol:_,attempt:_,contributions:_,intent,output_policy,pay_lines,platform_recipient,fee_revision}=b;let receipt=output::receipt(pay_lines,platform_recipient,fee_revision);
    let root=lifecycle::construction_ref(&construction);let scene=*soul::scene(root);let colors=soul::colors(root);let artifact=soul::create_output(&draft,root,intent,output_policy,recipe,scene,colors,soul::semantic_profiles(root),soul::published_profiles(root),render,system,sha256,envelope,receipt,ctx);soul::install_output_creation(authority(),lifecycle::construction_mut(&mut construction),artifact);soul::finalize_creation(draft,lifecycle::construction_mut(&mut construction),actor,ctx);(construction,sessions,actor)
}
/// The recovery policy is unavailable after any successful Complete for this attempt.
/// Already fetched plaintext/keys remain outside onchain revocation guarantees.
fun upload_recovery<C>(id:vector<u8>,maker:&Product<C>,intent:Intent,output_key:vector<u8>,ctx:&TxContext) {
    let version=output::intent_version(&intent);let v=catalog::published(maker,version);let policy=catalog::output_policy(v,output_key);
    output::assert_intent(&intent,catalog::protocol(maker),object::id(maker),version,catalog::policy_hash(v),&policy,ctx.sender());
    assert!(id==output::recovery_id(&intent) && catalog::receipt(maker,ctx.sender(),2,output::intent_attempt(&intent)).is_none(),EInitial)
}
fun output_intent_assembly(b:&Assembly):&Intent{&b.intent}
fun output_policy_assembly(b:&Assembly):&Policy{&b.output_policy}
fun semantic_recipe_hash_assembly(b:&Assembly):vector<u8>{soul::semantic_recipe_hash(lifecycle::construction_ref(&b.construction))}
fun select_colors_assembly(b:&mut Assembly,colors:vector<soulidity_visual::visual::ColorChoice>,ctx:&TxContext){actor(b,ctx);soul::set_initial_colors_creation(&b.draft,lifecycle::construction_mut(&mut b.construction),colors,ctx)}
fun soul_id_assembly(b:&Assembly):ID{object::id(lifecycle::construction_ref(&b.construction))}
fun actor(b:&Assembly,ctx:&TxContext){assert!(b.actor==ctx.sender(),EActor)}
fun contribution_index(b:&Assembly,product:ID):u64 {
    let mut i=0;while(i < b.contributions.length()){if(b.contributions[i].product==product)return i;i=i+1};abort EProduct
}


fun product_version(b:&Assembly,product:ID):u64{b.contributions[contribution_index(b,product)].version}

/// Linear execution pins the original Walrus System and epoch through finish.
public struct Build {inner:Assembly,system:ID,epoch:u32}
fun guard(b:&Build,system:&System){assert!(b.system==object::id(system) && b.epoch==system::epoch(system),ESystem)}
public fun begin<C>(maker:&mut Product<C>,cfg:&mut Config<C>,intent:Intent,output_key:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,system:&System,ctx:&mut TxContext):Build{
    release::assert_current(maker,cfg,output::intent_version(&intent),system);Build{system:object::id(system),epoch:system::epoch(system),inner:begin_assembly(maker,cfg,intent,output_key,fee_revision,expiry,payment,clock,system,ctx)}
}
public fun include_pack<C>(b:&mut Build,pack:&mut Product<C>,maker:&Product<C>,cfg:&mut Config<C>,version:u64,policy_hash:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,system:&System,ctx:&mut TxContext){guard(b,system);release::assert_current(maker,cfg,b.inner.maker_version,system);release::assert_current(pack,cfg,version,system);include_pack_assembly(&mut b.inner,pack,maker,cfg,version,policy_hash,fee_revision,expiry,payment,clock,system,ctx)}
public fun select_scoped<C>(b:&mut Build,product:&mut Product<C>,definition:vector<u8>,part:PartKey,layout:Layout,cfg:&Config<C>,system:&System,ctx:&mut TxContext){guard(b,system);release::assert_current(product,cfg,product_version(&b.inner,object::id(product)),system);select_scoped_assembly(&mut b.inner,product,definition,part,layout,ctx)}
public fun select_player_scoped<C>(b:&mut Build,product:&mut Product<C>,p:&Player,part:PartKey,expected_player:u64,cfg:&Config<C>,system:&System,ctx:&mut TxContext){guard(b,system);release::assert_current(product,cfg,product_version(&b.inner,object::id(product)),system);select_player_scoped_assembly(&mut b.inner,product,p,part,expected_player,ctx)}
public fun select<C>(b:&mut Build,product:&mut Product<C>,definition:vector<u8>,part:vector<u8>,layout:Layout,cfg:&Config<C>,system:&System,ctx:&mut TxContext){select_scoped(b,product,definition,assembly::root_part(part),layout,cfg,system,ctx)}
public fun select_player<C>(b:&mut Build,product:&mut Product<C>,p:&Player,part:vector<u8>,expected_player:u64,cfg:&Config<C>,system:&System,ctx:&mut TxContext){select_player_scoped(b,product,p,assembly::root_part(part),expected_player,cfg,system,ctx)}
public fun append_initial_content(b:&mut Build,registry:&KindRegistry,kind:u32,name:String,blob:Blob,system:&System,sha256:vector<u8>,envelope:vector<u8>,clock:&Clock,ctx:&TxContext):u64{guard(b,system);append_initial_content_assembly(&mut b.inner,registry,kind,name,blob,system,sha256,envelope,clock,ctx)}
public fun set_initial_state_config(b:&mut Build,key:String,value:vector<u8>,system:&System,ctx:&mut TxContext){guard(b,system);set_initial_state_config_assembly(&mut b.inner,key,value,ctx)}
public fun select_colors(b:&mut Build,colors:vector<ColorChoice>,ctx:&TxContext){select_colors_assembly(&mut b.inner,colors,ctx)}
public fun select_pack_colors(b:&mut Build,scope:Scope,colors:vector<ColorChoice>,ctx:&TxContext){actor(&b.inner,ctx);soul::set_initial_pack_colors_creation(&b.inner.draft,lifecycle::construction_mut(&mut b.inner.construction),scope,colors,ctx)}
public fun finish<C>(b:Build,cfg:&Config<C>,clock:&Clock,render:Blob,system:&System,sha256:vector<u8>,envelope:vector<u8>,ctx:&mut TxContext):ID{guard(&b,system);let Build{inner,system:_,epoch:_}=b;finish_live_assembly(inner,cfg,clock,render,system,sha256,envelope,ctx)}
public fun soul_id(b:&Build):ID{soul_id_assembly(&b.inner)}
public fun output_intent(b:&Build):&Intent{output_intent_assembly(&b.inner)}
public fun output_policy(b:&Build):&Policy{output_policy_assembly(&b.inner)}
public fun semantic_recipe_hash(b:&Build):vector<u8>{semantic_recipe_hash_assembly(&b.inner)}
public fun seal_approve_upload_recovery<C>(id:vector<u8>,maker:&Product<C>,intent:Intent,output_key:vector<u8>,ctx:&TxContext){upload_recovery(id,maker,intent,output_key,ctx)}
public fun set_state_config<C>(s:&mut Soul,cfg:&Config<C>,key:String,value:vector<u8>,expected:u64,ctx:&mut TxContext){soul::set_manufacturing_state_config(authority(),s,cfg,key,value,expected,ctx)}
public fun delete_state_config<C>(s:&mut Soul,cfg:&Config<C>,key:String,expected:u64,ctx:&TxContext){soul::delete_manufacturing_state_config(authority(),s,cfg,key,expected,ctx)}
public fun assert_content_read(id:vector<u8>,s:&Soul,index:u64,system:&System,mode:u64){soul::assert_content_read(authority(),id,s,index,system,mode)}
public fun assert_delegate(s:&Soul,owner:address,grantee:address,scope:u64,clock:&Clock){soul::assert_delegate(authority(),s,owner,grantee,scope,clock)}
public fun assert_original_output_read(id:vector<u8>,s:&Soul,system:&System){soul::assert_original_output_read(authority(),id,s,system)}

public struct Purchase has copy,drop,store {definition:vector<u8>,part:soulidity_model::assembly::PartKey,layout:Layout}
public struct InstalledChoice has copy,drop {source:vector<u8>,part:soulidity_model::assembly::PartKey,layout:Layout,item:Option<ID>,returned:Option<ID>}
public struct EnhancementIntent has drop {domain:vector<u8>,schema:u16,soul:ID,product:ID,version:u64,policy:vector<u8>,actor:address,attempt:vector<u8>,before_revision:u64,before_recipe:vector<u8>,choices:vector<InstalledChoice>}
/// A purchase description is untrusted input; only actual catalog issuance grants rights.
public fun purchase(definition:vector<u8>,part:soulidity_model::assembly::PartKey,layout:Layout):Purchase{policy::assert_hash(&definition);Purchase{definition,part,layout}}
/// Existing OC enhancement does not mint another Soul or rewrite its genesis Output.
/// One actual product contribution charges its published completion price/quota
/// once, without charging the OC mint fixed fee again. Old free objects return.
public fun enhance_maker<C>(s:&mut Soul,maker:&mut Product<C>,cfg:&mut Config<C>,expected:u64,policy_hash:vector<u8>,choices:vector<Purchase>,attempt:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,system:&System,ctx:&mut TxContext):vector<soulidity_model::components::Item>{
 release::assert_current(maker,cfg,soul::maker_version(s),system);enhance_maker_guard(s,maker,cfg,expected,policy_hash,attempt,fee_revision,expiry,clock,system,ctx);let version=soul::maker_version(s);let(snapshot,before_recipe)=enhance_prepare(s,maker,cfg,version,policy_hash,&choices,attempt,expiry,&payment,clock,system,ctx);let session=factory::begin(maker,s,cfg,snapshot,payment,authority(),revision(),system,clock,ctx);let(session,returned)=enhance_apply(s,maker,cfg,version,expected,policy_hash,choices,attempt,snapshot,before_recipe,session,ctx);let completion=factory::finish(session,s,cfg,authority(),revision(),system,clock,ctx);origin::consume_completion<MakerSoulAuthority1,MakerSoulRevision1,Soul>(completion,s,&snapshot,ctx);returned
}
public fun enhance_pack<C>(s:&mut Soul,pack:&mut Product<C>,maker:&Product<C>,cfg:&mut Config<C>,version:u64,expected:u64,policy_hash:vector<u8>,choices:vector<Purchase>,attempt:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,system:&System,ctx:&mut TxContext):vector<soulidity_model::components::Item>{
 release::assert_current(maker,cfg,soul::maker_version(s),system);release::assert_current(pack,cfg,version,system);enhance_pack_guard(s,pack,maker,cfg,version,expected,policy_hash,fee_revision,expiry,clock,ctx);let(snapshot,before_recipe)=enhance_prepare(s,pack,cfg,version,policy_hash,&choices,attempt,expiry,&payment,clock,system,ctx);let session=factory::begin_pack(pack,maker,s,cfg,snapshot,payment,authority(),revision(),system,clock,ctx);let(session,returned)=enhance_apply(s,pack,cfg,version,expected,policy_hash,choices,attempt,snapshot,before_recipe,session,ctx);let completion=factory::finish(session,s,cfg,authority(),revision(),system,clock,ctx);origin::consume_completion<MakerSoulAuthority1,MakerSoulRevision1,Soul>(completion,s,&snapshot,ctx);returned
}
fun enhance_maker_guard<C>(s:&Soul,maker:&mut Product<C>,cfg:&Config<C>,expected:u64,policy_hash:vector<u8>,attempt:vector<u8>,fee_revision:u64,expiry:u64,clock:&Clock,system:&System,ctx:&mut TxContext){
 soul::assert_revision(s,expected);assert!(catalog::parent(maker).is_none() && object::id(maker)==soul::maker(s) && catalog::protocol(maker)==soul::protocol(s) && soul::protocol(s)==object::id(cfg),EProduct);let version=soul::maker_version(s);economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock);ensure_access(maker,cfg,version,attempt,fee_revision,expiry,clock,system,ctx);let v=catalog::published(maker,version);assert!(catalog::policy_hash(v)==policy_hash,EProduct);assert_access(maker,cfg,version,fee_revision,clock,ctx)
}
fun enhance_pack_guard<C>(s:&mut Soul,pack:&Product<C>,maker:&Product<C>,cfg:&Config<C>,version:u64,expected:u64,policy_hash:vector<u8>,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext){
 soul::assert_revision(s,expected);assert!(object::id(maker)==soul::maker(s) && soul::protocol(s)==object::id(cfg) && catalog::protocol(pack)==soul::protocol(s),EProduct);economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock);let v=catalog::published(pack,version);assert!(catalog::policy_hash(v)==policy_hash,EProduct);economics::assert_manufacturing_snapshot(cfg,soul::protocol(s),fee_revision,economics::commitment(cfg));catalog::assert_pack(pack,maker,soul::maker_version(s),version,ctx.sender());assert_access_time(pack,version,clock,ctx);assert_access_time(maker,soul::maker_version(s),clock,ctx);soul::admit_profile(authority(),s,catalog::assembly_profile(pack,version))
}
fun enhance_prepare<C>(s:&Soul,p:&Product<C>,cfg:&Config<C>,version:u64,policy_hash:vector<u8>,choices:&vector<Purchase>,attempt:vector<u8>,expiry:u64,payment:&Coin<C>,clock:&Clock,system:&System,ctx:&TxContext):(origin::Snapshot,vector<u8>){
 assert!(!choices.is_empty() && choices.length()<=512,EChoices);policy::assert_hash(&attempt);let mut parts=vector[];choices.do_ref!(|c|{assert!(!parts.contains(&c.part),EChoices);parts.push_back(c.part);let src=catalog::preview_source(p,version,c.definition);soul::assert_fresh_issuance(s,&src,c.part,&c.layout)});let v=catalog::published(p,version);let quote=economics::manufacturing_primary_quote(&catalog::version_primary(v),cfg,catalog::completion_price(p,version,ctx.sender()),false,catalog::beneficiary(v),object::id(s),policy_hash,ctx.sender(),attempt,expiry);assert!(coin::value(payment)==economics::primary_receipt_total(&quote),EPayment);let before_recipe=soul::semantic_recipe_hash(s);
 // Request metadata uses the current expiry already checked by the outer gate.
 let snapshot=factory::request_contribution(p,s,cfg,version,policy_hash,*standard::name(s),attempt,expiry,authority(),revision(),system,clock,ctx);(snapshot,before_recipe)
}
fun enhance_apply<C>(s:&mut Soul,p:&mut Product<C>,cfg:&Config<C>,version:u64,expected:u64,policy_hash:vector<u8>,choices:vector<Purchase>,attempt:vector<u8>,snapshot:origin::Snapshot,before_recipe:vector<u8>,mut session:Session,ctx:&mut TxContext):(Session,vector<soulidity_model::components::Item>){
 let product=object::id(p);let paid=manufacture::session_receipt(&session);let action=manufacture::take_action(&mut session,p,s,ctx);let contribution=admission::authorize_manufacturing_contribution_action(cfg,p,s,action,paid,authority(),revision(),ctx);let enhancement=soul::begin_enhancement(contribution,s,expected,ctx);let mut returned=vector[];let mut installed=vector[];
 choices.do!(|c|{let(permit,selection)=manufacture::select(&mut session,p,s,c.definition,ctx);let src=*soulidity_model::components::preview(&permit);let previous=soul::replace_issued(&enhancement,s,permit,c.part,c.layout,ctx);manufacture::selected(&mut session,selection,s,authority(),revision(),ctx);let old=previous.map_ref!(|it|object::id(it));previous.do!(|it|returned.push_back(it));let binding=soul::binding_scoped(s,c.part).destroy_some();installed.push_back(InstalledChoice{source:policy::source_hash(&src),part:c.part,layout:c.layout,item:soul::free_id(&binding),returned:old})});let commitment=policy::hash_bytes(std::bcs::to_bytes(&EnhancementIntent{domain:b"soulidity/enhancement/v1",schema:1,soul:object::id(s),product,version,policy:policy_hash,actor:ctx.sender(),attempt,before_revision:expected,before_recipe,choices:installed}));soul::finish_enhancement(enhancement,s,commitment,ctx);let _=snapshot;(session,returned)
}

public fun set_state_config_creation<C>(s:&mut standard::Creation,cfg:&Config<C>,key:String,value:vector<u8>,expected:u64,ctx:&mut TxContext){soul::set_manufacturing_state_config_creation(authority(),s,cfg,key,value,expected,ctx)}
public fun delete_state_config_creation<C>(s:&mut standard::Creation,cfg:&Config<C>,key:String,expected:u64,ctx:&TxContext){soul::delete_manufacturing_state_config_creation(authority(),s,cfg,key,expected,ctx)}
