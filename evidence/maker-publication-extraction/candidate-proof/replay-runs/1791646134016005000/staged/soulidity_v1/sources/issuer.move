/// A non-storable assembly ticket makes selection, fees, issuance and transfer one PTB.
/// There is no public fresh Soul or public forgeable issuance witness.
module soulidity_v1::issuer;

use std::string::String;
use sui::coin::{Self,Coin};
use sui::clock::Clock;
use soulidity_v1::catalog::{Self,Product};
use soulidity_foundation::economics::{Self,Config};
use soulidity_model::policy::Layout;
use soulidity_application::character::{Self as soul};
use soulidity_standard::soul::Soul;
use soulidity_application::output::{Self};
use soulidity_maker_publication::output_data::{Intent,Policy,PayLine};
use soulidity_content_kinds::content_kind_registry::KindRegistry;
use walrus::blob::Blob;
use walrus::system::System;
use soulidity_v1::player::{Self,Player};
use soulidity_model::policy;

const EProduct:u64=1;
const EActor:u64=2;const EPayment:u64=3;
const EUnused:u64=4;const EInitial:u64=5;const ERecipe:u64=6;
const EChoices:u64=7;
public struct Purchase has copy,drop,store {definition:vector<u8>,part:soulidity_model::assembly::PartKey,layout:Layout}
public struct InstalledChoice has copy,drop {source:vector<u8>,part:soulidity_model::assembly::PartKey,layout:Layout,item:Option<ID>,returned:Option<ID>}
public struct EnhancementIntent has drop {domain:vector<u8>,schema:u16,soul:ID,product:ID,version:u64,policy:vector<u8>,actor:address,attempt:vector<u8>,before_revision:u64,before_recipe:vector<u8>,choices:vector<InstalledChoice>}
/// A purchase description is untrusted input; only actual catalog issuance grants rights.
public fun purchase(definition:vector<u8>,part:soulidity_model::assembly::PartKey,layout:Layout):Purchase{policy::assert_hash(&definition);Purchase{definition,part,layout}}
/// Existing OC enhancement does not mint another Soul or rewrite its genesis Output.
/// One actual product contribution charges its published completion price/quota
/// once, without charging the OC mint fixed fee again. Old free objects return.
public(package) fun enhance_maker<C>(s:&mut Soul,maker:&mut Product<C>,cfg:&mut Config<C>,expected:u64,policy_hash:vector<u8>,choices:vector<Purchase>,attempt:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):vector<soulidity_model::components::Item>{
    soul::assert_revision(s,expected);assert!(catalog::parent(maker).is_none() && object::id(maker)==soul::maker(s) && catalog::protocol(maker)==soul::protocol(s) && soul::protocol(s)==object::id(cfg),EProduct);
    let version=soul::maker_version(s);economics::assert_primary_live(cfg,fee_revision,expiry,clock);catalog::ensure_access(maker,cfg,version,attempt,fee_revision,expiry,clock,ctx);
    let v=catalog::published(maker,version);assert!(catalog::policy_hash(v)==policy_hash,EProduct);catalog::assert_runtime_access(maker,cfg,version,policy_hash,catalog::manifest(v),fee_revision,economics::commitment(cfg),clock,ctx);
    enhance(s,maker,cfg,version,expected,policy_hash,choices,attempt,expiry,payment,clock,ctx)
}
public(package) fun enhance_pack<C>(s:&mut Soul,pack:&mut Product<C>,maker:&Product<C>,cfg:&mut Config<C>,version:u64,expected:u64,policy_hash:vector<u8>,choices:vector<Purchase>,attempt:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):vector<soulidity_model::components::Item>{
    soul::assert_revision(s,expected);assert!(object::id(maker)==soul::maker(s) && soul::protocol(s)==object::id(cfg) && catalog::protocol(pack)==soul::protocol(s),EProduct);
    economics::assert_primary_live(cfg,fee_revision,expiry,clock);let v=catalog::published(pack,version);assert!(catalog::policy_hash(v)==policy_hash,EProduct);
    catalog::assert_runtime_pack(pack,maker,soul::maker_version(s),version,cfg,policy_hash,catalog::manifest(v),fee_revision,economics::commitment(cfg),clock,ctx);
    soul::admit_profile(soulidity_v1::application_operator::operator(),s,catalog::assembly_profile(pack,version));enhance(s,pack,cfg,version,expected,policy_hash,choices,attempt,expiry,payment,clock,ctx)
}
fun enhance<C>(s:&mut Soul,p:&mut Product<C>,cfg:&mut Config<C>,version:u64,expected:u64,policy_hash:vector<u8>,choices:vector<Purchase>,attempt:vector<u8>,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):vector<soulidity_model::components::Item>{
    assert!(!choices.is_empty() && choices.length()<=512,EChoices);policy::assert_hash(&attempt);let mut parts=vector[];
    choices.do_ref!(|c|{assert!(!parts.contains(&c.part),EChoices);parts.push_back(c.part);let src=catalog::preview_source(p,version,c.definition);soul::assert_fresh_issuance(s,&src,c.part,&c.layout)});
    // Preserve the native enhancement error boundary. This preview is never a
    // paid proof: Catalog reserves quota and settles the exact Coin again below.
    let v=catalog::published(p,version);
    let quote=economics::primary_quote(&catalog::version_primary(v),cfg,catalog::completion_price(p,version,ctx.sender()),false,catalog::beneficiary(v),object::id(s),policy_hash,ctx.sender(),attempt,expiry);
    assert!(coin::value(&payment)==economics::primary_receipt_total(&quote),EPayment);
    let before_recipe=soul::semantic_recipe_hash(s);let product=object::id(p);
    let contribution=catalog::complete_contribution(p,s,cfg,version,policy_hash,attempt,expiry,payment,clock,ctx);
    let enhancement=soul::begin_enhancement(contribution,s,expected,ctx);
    let mut returned=vector[];let mut installed=vector[];
    choices.do!(|c|{let permit=catalog::issue(p,version,c.definition,s);let src=*soulidity_model::components::preview(&permit);let previous=soul::replace_issued(&enhancement,s,permit,c.part,c.layout,ctx);let old=previous.map_ref!(|it|object::id(it));previous.do!(|it|returned.push_back(it));let binding=soul::binding_scoped(s,c.part).destroy_some();installed.push_back(InstalledChoice{source:policy::source_hash(&src),part:c.part,layout:c.layout,item:soul::free_id(&binding),returned:old})});
    let commitment=policy::hash_bytes(std::bcs::to_bytes(&EnhancementIntent{domain:b"soulidity/enhancement/v1",schema:1,soul:object::id(s),product,version,policy:policy_hash,actor:ctx.sender(),attempt,before_revision:expected,before_recipe,choices:installed}));
    soul::finish_enhancement(enhancement,s,commitment,ctx);returned
}
public struct Contribution has copy,drop {product:ID,version:u64,used:u64}
/// No key, store or drop: unfinished assemblies cannot survive transaction execution.
public struct Build {
    soul:Soul,draft:soulidity_application::character::Draft,actor:address,maker:ID,maker_version:u64,protocol:ID,
    attempt:vector<u8>,contributions:vector<Contribution>,intent:Intent,output_policy:Policy,pay_lines:vector<PayLine>,platform_recipient:address,fee_revision:u64,
}

public(package) fun begin<C>(binding:soulidity_maker_admission::maker_issuance::Binding,maker:&mut Product<C>,cfg:&mut Config<C>,intent:Intent,output_key:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):Build {
    let version=output::intent_version(&intent);let policy_hash=output::intent_policy(&intent);let attempt=output::intent_attempt(&intent);let name=output::intent_name(&intent);
    assert!(catalog::parent(maker).is_none() && catalog::protocol(maker)==object::id(cfg),EProduct);
    assert!(name.length()>0 && name.length()<=128,EProduct);
    economics::assert_primary_live(cfg,fee_revision,expiry,clock);
    catalog::ensure_access(maker,cfg,version,attempt,fee_revision,expiry,clock,ctx);
    let av=catalog::published(maker,version);catalog::assert_runtime_access(maker,cfg,version,catalog::policy_hash(av),catalog::manifest(av),fee_revision,economics::commitment(cfg),clock,ctx);
    let v=*catalog::published(maker,version);let output_policy=catalog::output_policy(&v,output_key);output::assert_intent(&intent,object::id(cfg),object::id(maker),version,policy_hash,&output_policy,ctx.sender());
    let (root,genesis,receipt)=catalog::mint_soul(binding,maker,cfg,version,name,policy_hash,attempt,fee_revision,expiry,payment,clock,ctx);
    let (s,draft)=soul::new(genesis,root,object::id(cfg),object::id(maker),version,catalog::manifest(&v),catalog::configuration(&v),catalog::assembly_profile(maker,version),catalog::required_parts(&v),catalog::adapters(&v),*catalog::scene(&v),soulidity_maker_terms::maker_resale::snapshot(object::id(cfg),object::id(maker),version,policy_hash,catalog::creator(maker),catalog::soul_rates(&v),ctx),catalog::beneficiary(&v),ctx);
    let primary=catalog::version_primary(&v);
    let line=output::pay_line(object::id(maker),version,policy_hash,receipt);
    Build{soul:s,draft,actor:ctx.sender(),maker:object::id(maker),maker_version:version,protocol:object::id(cfg),attempt,contributions:vector[Contribution{product:object::id(maker),version,used:0}],intent,output_policy,pay_lines:vector[line],platform_recipient:economics::primary_policy_platform(&primary),fee_revision}
}

/// Pack fees/counts are charged once; finish refuses an included Pack with no selection.
public(package) fun include_pack<C>(b:&mut Build,pack:&mut Product<C>,maker:&Product<C>,cfg:&mut Config<C>,version:u64,policy_hash:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    actor(b,ctx);
    assert!(b.fee_revision==fee_revision && b.protocol==object::id(cfg) && catalog::protocol(pack)==b.protocol && object::id(maker)==b.maker,EProduct);
    assert!(!b.contributions.any!(|c| c.product==object::id(pack)),EProduct);
    economics::assert_primary_live(cfg,fee_revision,expiry,clock);
    let av=catalog::published(pack,version);catalog::assert_runtime_pack(pack,maker,b.maker_version,version,cfg,catalog::policy_hash(av),catalog::manifest(av),fee_revision,economics::commitment(cfg),clock,ctx);
    let v=*catalog::published(pack,version);output::assert_pack(&b.output_policy,catalog::pack_key(&v));
    let primary=catalog::version_primary(&v);assert!(economics::primary_policy_platform(&primary)==b.platform_recipient,EProduct);
    let contribution=catalog::complete_contribution(pack,&b.soul,cfg,version,policy_hash,b.attempt,expiry,payment,clock,ctx);
    let receipt=soul::admit_contribution(&b.draft,&mut b.soul,contribution,catalog::assembly_profile(pack,version),ctx);
    b.contributions.push_back(Contribution{product:object::id(pack),version,used:0});b.pay_lines.push_back(output::pay_line(object::id(pack),version,policy_hash,receipt));
}

public(package) fun select_scoped<C>(b:&mut Build,product:&mut Product<C>,definition_hash:vector<u8>,part:soulidity_model::assembly::PartKey,layout:Layout,ctx:&mut TxContext) {
    actor(b,ctx);assert!(catalog::protocol(product)==b.protocol,EProduct);
    let index=contribution_index(b,object::id(product));
    let version=b.contributions[index].version;
    let source=catalog::issue(product,version,definition_hash,&b.soul);
    soul::add_issued(&b.draft,&mut b.soul,source,part,layout,ctx);
    b.contributions[index].used=b.contributions[index].used+1;
}
/// Complete may consume the same actual Player selection used by Physical.
/// This is the first OC issuance; copying a Player selection never issues rights.
public(package) fun select_player_scoped<C>(b:&mut Build,product:&mut Product<C>,p:&Player,part:soulidity_model::assembly::PartKey,expected_player:u64,ctx:&mut TxContext) {
    actor(b,ctx);player::assert_owner(p,expected_player,ctx);assert!(player::maker(p)==b.maker && player::maker_version(p)==b.maker_version && player::protocol(p)==b.protocol,EProduct);
    let selected=player::scoped_selection(p,part).destroy_some();let source=player::source(&selected);let c=contribution_index(b,object::id(product));
    assert!(policy::source_product(source)==object::id(product) && policy::source_version(source)==b.contributions[c].version && catalog::preview_source(product,b.contributions[c].version,policy::source_definition_hash(source))==*source,EProduct);
    soul::set_initial_colors(&b.draft,&mut b.soul,player::colors(p),ctx);player::profiles(p).do_ref!(|profile|{let scope=soulidity_model::assembly::snapshot_scope(profile);if(soul::profile_snapshots(&b.soul).any!(|x|soulidity_model::assembly::snapshot_scope(x)==scope))soul::set_initial_pack_colors(&b.draft,&mut b.soul,scope,player::pack_colors(p,scope),ctx)});select_scoped(b,product,policy::source_definition_hash(source),part,player::layout(&selected),ctx)
}

public(package) fun append_initial_content(b:&mut Build,registry:&KindRegistry,kind:u32,name:String,blob:Blob,system:&System,sha256:vector<u8>,envelope:vector<u8>,clock:&Clock,ctx:&TxContext):u64 {
    actor(b,ctx);let rule=output::rule(&b.output_policy,kind,name);
    soul::append_initial_output_content(&b.draft,&mut b.soul,registry,&rule,&b.intent,blob,system,sha256,envelope,clock,ctx)
}
public(package) fun set_initial_state_config(b:&mut Build,key:String,value:vector<u8>,ctx:&mut TxContext){
    actor(b,ctx);soul::set_initial_state_config(&b.draft,&mut b.soul,key,value,ctx)
}
public(package) fun finish(b:Build,render:Blob,system:&System,sha256:vector<u8>,envelope:vector<u8>,ctx:&mut TxContext):ID {
    actor(&b,ctx);
    let mut i=1;while(i < b.contributions.length()){assert!(b.contributions[i].used>0,EUnused);i=i+1};
    output::initials(&b.output_policy).do_ref!(|r| assert!(soul::content_index(&b.soul,output::rule_kind(r),output::rule_name(r),0).is_some(),EInitial));
    let recipe=soul::semantic_recipe(&b.soul);assert!(soul::semantic_recipe_hash(&b.soul)==output::intent_recipe(&b.intent),ERecipe);
    let Build{mut soul,draft,actor,maker:_,maker_version:_,protocol:_,attempt:_,contributions:_,intent,output_policy,pay_lines,platform_recipient,fee_revision}=b;
    let id=object::id(&soul);let receipt=output::receipt(pay_lines,platform_recipient,fee_revision);
    let scene=*soul::scene(&soul);let colors=soul::colors(&soul);let artifact=soul::create_output(&draft,&soul,intent,output_policy,recipe,scene,colors,soul::semantic_profiles(&soul),soul::published_profiles(&soul),render,system,sha256,envelope,receipt,ctx);soul::install_output(soulidity_v1::application_operator::operator(),&mut soul,artifact);soul::finish(draft,soul,actor,ctx);id
}
/// The recovery policy is unavailable after any successful Complete for this attempt.
/// Already fetched plaintext/keys remain outside onchain revocation guarantees.
public fun seal_approve_upload_recovery<C>(id:vector<u8>,maker:&Product<C>,intent:Intent,output_key:vector<u8>,ctx:&TxContext) {
    let version=output::intent_version(&intent);let v=catalog::published(maker,version);let policy=catalog::output_policy(v,output_key);
    output::assert_intent(&intent,catalog::protocol(maker),object::id(maker),version,catalog::policy_hash(v),&policy,ctx.sender());
    assert!(id==output::recovery_id(&intent) && catalog::receipt(maker,ctx.sender(),2,output::intent_attempt(&intent)).is_none(),EInitial)
}
public fun output_intent(b:&Build):&Intent{&b.intent}
public fun output_policy(b:&Build):&Policy{&b.output_policy}
public fun semantic_recipe_hash(b:&Build):vector<u8>{soul::semantic_recipe_hash(&b.soul)}
public(package) fun select_colors(b:&mut Build,colors:vector<soulidity_visual::visual::ColorChoice>,ctx:&TxContext){actor(b,ctx);soul::set_initial_colors(&b.draft,&mut b.soul,colors,ctx)}
public fun soul_id(b:&Build):ID{object::id(&b.soul)}
fun actor(b:&Build,ctx:&TxContext){assert!(b.actor==ctx.sender(),EActor)}
fun contribution_index(b:&Build,product:ID):u64 {
    let mut i=0;while(i < b.contributions.length()){if(b.contributions[i].product==product)return i;i=i+1};abort EProduct
}

/// Root-name convenience for unit fixtures; production Runtime uses scoped paths.
#[test_only]
public(package) fun select<C>(b:&mut Build,product:&mut Product<C>,definition_hash:vector<u8>,part:vector<u8>,layout:Layout,ctx:&mut TxContext){select_scoped(b,product,definition_hash,soulidity_model::assembly::root_part(part),layout,ctx)}
/// Root-name convenience for unit fixtures; production Runtime uses scoped paths.
#[test_only]
public(package) fun select_player<C>(b:&mut Build,product:&mut Product<C>,p:&Player,part:vector<u8>,expected_player:u64,ctx:&mut TxContext){select_player_scoped(b,product,p,soulidity_model::assembly::root_part(part),expected_player,ctx)}

public(package) fun product_version(b:&Build,product:ID):u64{b.contributions[contribution_index(b,product)].version}
