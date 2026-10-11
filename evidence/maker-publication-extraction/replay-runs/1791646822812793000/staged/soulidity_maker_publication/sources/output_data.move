/// Canonical copyable publication data; none of these values prove payment or confer custody.
module soulidity_maker_publication::output_data;
use std::bcs;
use std::string::String;
use soulidity_model::policy::{Self,Source,Layout,Adapter};
use soulidity_content_kinds::document_policy as document;
use soulidity_content_kinds::content_kind_registry::{Self as kind_registry,KindRegistry};
use soulidity_foundation::economics::{Self,PrimaryReceipt};
use soulidity_visual::visual::{Self,Scene,ColorChoice};
use soulidity_model::assembly::{Self,PartKey,ProfileSnapshot};
const EPolicy:u64=1;const EIntent:u64=2;
public struct InitialRule has copy,drop,store {kind:u32,name:String,read_mask:u64,download_policy:u8}
public struct Policy has copy,drop,store {key:vector<u8>,protected:bool,scope:vector<u8>,renderer:vector<u8>,all_packs:bool,allowed_packs:vector<vector<u8>>,initials:vector<InitialRule>}
public struct Intent has copy,drop,store {
    domain:vector<u8>,schema:u16,protocol:ID,maker:ID,maker_version:u64,policy_hash:vector<u8>,output_policy_hash:vector<u8>,actor:address,attempt:vector<u8>,name:String,recipe:vector<u8>,nonce:vector<u8>,
}
public struct Selection has copy,drop,store {source:Source,layout:Layout,adapter:Option<Adapter>}
public struct RecipeSlot has copy,drop,store {part:PartKey,selection:Option<Selection>}
public struct Recipe has copy,drop,store {domain:vector<u8>,schema:u16,scene:vector<u8>,colors:vector<ColorChoice>,profiles:vector<ProfileSnapshot>,slots:vector<RecipeSlot>}
public struct Namespace has copy,drop,store {domain:vector<u8>,schema:u16,intent:vector<u8>,kind:u32,name:String}
public struct PayLine has copy,drop,store {product:ID,version:u64,policy_hash:vector<u8>,receipt:PrimaryReceipt}
public struct Receipt has copy,drop,store {lines:vector<PayLine>,total:u128,platform_recipient:address,fee_revision:u64}
public fun initial_rule(registry:&KindRegistry,kind:u32,name:String,read_mask:u64,download_policy:u8):InitialRule {
    document::assert_name(kind,&name);document::assert_read_policy(kind_registry::borrow_descriptor(registry,kind),read_mask,download_policy);
    InitialRule{kind,name,read_mask,download_policy}
}
public fun policy(key:vector<u8>,protected:bool,scope:vector<u8>,renderer:vector<u8>,all_packs:bool,allowed_packs:vector<vector<u8>>,initials:vector<InitialRule>):Policy {
    policy::assert_key(&key);policy::assert_hash(&renderer);
    if(protected)policy::assert_key(&scope) else assert!(scope.is_empty(),EPolicy);
    assert!(allowed_packs.length()<=64 && initials.length()>=2 && initials.length()<=256,EPolicy);
    if(all_packs)assert!(allowed_packs.is_empty(),EPolicy);
    let mut seen=vector[];allowed_packs.do_ref!(|p|{policy::assert_key(p);assert!(!seen.contains(p),EPolicy);seen.push_back(*p)});
    let mut names=vector[];let mut doc=false;let mut memory=false;
    initials.do_ref!(|r|{let mut name_key=bcs::to_bytes(&r.kind);name_key.append(bcs::to_bytes(&r.name));assert!(!names.contains(&name_key),EPolicy);names.push_back(name_key);if(r.kind==0)doc=true;if(r.kind==1)memory=true});
    assert!(doc && memory,EPolicy);Policy{key,protected,scope,renderer,all_packs,allowed_packs,initials}
}
public fun policy_key(p:&Policy):vector<u8>{p.key}
public fun policy_hash(p:&Policy):vector<u8>{policy::hash_bytes(bcs::to_bytes(p))}
public fun protected(p:&Policy):bool{p.protected}
public fun scope(p:&Policy):vector<u8>{p.scope}
public fun renderer(p:&Policy):vector<u8>{p.renderer}
public fun allows_all_packs(p:&Policy):bool{p.all_packs}
public fun allowed_packs(p:&Policy):vector<vector<u8>>{p.allowed_packs}
public fun initials(p:&Policy):vector<InitialRule>{p.initials}
public fun rule_kind(r:&InitialRule):u32{r.kind}
public fun rule_name(r:&InitialRule):String{r.name}
public fun rule_read(r:&InitialRule):u64{r.read_mask}
public fun rule_download(r:&InitialRule):u8{r.download_policy}
public fun rule(p:&Policy,kind:u32,name:String):InitialRule {
    let mut found=option::none();p.initials.do_ref!(|r|{if(r.kind==kind && r.name==name)found=option::some(*r)});assert!(found.is_some(),EPolicy);found.destroy_some()
}
public fun assert_pack(p:&Policy,key:vector<u8>){assert!(p.all_packs || p.allowed_packs.contains(&key),EPolicy)}
public fun intent(protocol:ID,maker:ID,maker_version:u64,policy_hash:vector<u8>,output_policy_hash:vector<u8>,actor:address,attempt:vector<u8>,name:String,recipe:vector<u8>,nonce:vector<u8>):Intent {
    policy::assert_hash(&policy_hash);policy::assert_hash(&output_policy_hash);policy::assert_hash(&attempt);policy::assert_hash(&recipe);
    assert!(actor!=@0x0 && maker_version>0 && nonce.length()==16 && name.length()>0 && name.length()<=128,EIntent);
    Intent{domain:b"soulidity-complete-intent",schema:1,protocol,maker,maker_version,policy_hash,output_policy_hash,actor,attempt,name,recipe,nonce}
}
public fun intent_hash(i:&Intent):vector<u8>{policy::hash_bytes(bcs::to_bytes(i))}
public fun intent_protocol(i:&Intent):ID{i.protocol}
public fun intent_maker(i:&Intent):ID{i.maker}
public fun intent_version(i:&Intent):u64{i.maker_version}
public fun intent_policy(i:&Intent):vector<u8>{i.policy_hash}
public fun intent_output_policy(i:&Intent):vector<u8>{i.output_policy_hash}
public fun intent_actor(i:&Intent):address{i.actor}
public fun intent_attempt(i:&Intent):vector<u8>{i.attempt}
public fun intent_name(i:&Intent):String{i.name}
public fun intent_recipe(i:&Intent):vector<u8>{i.recipe}
public fun intent_nonce(i:&Intent):vector<u8>{i.nonce}
public fun assert_intent(i:&Intent,protocol:ID,maker:ID,version:u64,policy_hash:vector<u8>,p:&Policy,actor:address) {
    assert!(i.protocol==protocol && i.maker==maker && i.maker_version==version && i.policy_hash==policy_hash && i.output_policy_hash==policy_hash(p) && i.actor==actor,EIntent)
}
public fun selection(source:Source,layout:Layout,adapter:Option<Adapter>):Selection{Selection{source,layout,adapter}}
public fun slot(part:vector<u8>,selection:Option<Selection>):RecipeSlot{scoped_slot(assembly::root_part(part),selection)}
public fun scoped_slot(part:PartKey,selection:Option<Selection>):RecipeSlot{RecipeSlot{part,selection}}
public fun slot_part(s:&RecipeSlot):PartKey{s.part}
public fun slot_selection(s:&RecipeSlot):Option<Selection>{s.selection}
public fun selection_source(s:&Selection):&Source{&s.source}
public fun selection_layout(s:&Selection):Layout{s.layout}
public fun selection_adapter(s:&Selection):Option<Adapter>{s.adapter}
public fun recipe_hash(scene:&Scene,colors:&vector<ColorChoice>,slots:vector<RecipeSlot>):vector<u8>{profile_recipe_hash(scene,colors,vector[],slots)}
public fun profile_recipe_hash(scene:&Scene,colors:&vector<ColorChoice>,profiles:vector<ProfileSnapshot>,slots:vector<RecipeSlot>):vector<u8>{visual::assert_colors(scene,colors);policy::hash_bytes(bcs::to_bytes(&Recipe{domain:b"soulidity-semantic-recipe",schema:2,scene:visual::scene_hash(scene),colors:*colors,profiles,slots}))}
public fun content_id(i:&Intent,kind:u32,name:String):vector<u8> {
    document::assert_name(kind,&name);bcs::to_bytes(&Namespace{domain:b"soulidity-complete-content",schema:1,intent:intent_hash(i),kind,name})
}
public fun render_id(i:&Intent):vector<u8>{bcs::to_bytes(&Namespace{domain:b"soulidity-complete-render",schema:1,intent:intent_hash(i),kind:0,name:std::string::utf8(vector[])})}
public fun recovery_id(i:&Intent):vector<u8>{bcs::to_bytes(&Namespace{domain:b"soulidity-upload-recovery",schema:1,intent:intent_hash(i),kind:0,name:std::string::utf8(vector[])})}
public fun pay_line(product:ID,version:u64,policy_hash:vector<u8>,receipt:PrimaryReceipt):PayLine {assert!(policy_hash==economics::primary_receipt_commitment(&receipt),EPolicy);PayLine{product,version,policy_hash,receipt}}
public fun receipt(lines:vector<PayLine>,platform_recipient:address,fee_revision:u64):Receipt {let mut total=0;lines.do_ref!(|l|{assert!(economics::primary_policy_platform(&economics::primary_receipt_policy(&l.receipt))==platform_recipient && economics::primary_receipt_revision(&l.receipt)==fee_revision,EPolicy);total=total+(economics::primary_receipt_total(&l.receipt) as u128)});Receipt{lines,total,platform_recipient,fee_revision}}
public fun total_paid(r:&Receipt):u128{r.total}
public fun pay_lines(r:&Receipt):&vector<PayLine>{&r.lines}
public fun platform_recipient(r:&Receipt):address{r.platform_recipient}
public fun fee_revision(r:&Receipt):u64{r.fee_revision}
public fun line_product(l:&PayLine):ID{l.product}
public fun line_version(l:&PayLine):u64{l.version}
public fun line_policy_hash(l:&PayLine):vector<u8>{l.policy_hash}
public fun line_beneficiary(l:&PayLine):address{economics::primary_receipt_beneficiary(&l.receipt)}
public fun line_gross(l:&PayLine):u64{economics::primary_receipt_gross(&l.receipt)}
public fun line_platform(l:&PayLine):u64{economics::primary_receipt_fee(&l.receipt)}
public fun line_fixed(l:&PayLine):u64{economics::primary_receipt_fixed(&l.receipt)}
public fun line_receipt(l:&PayLine):PrimaryReceipt{l.receipt}
public fun receipt_hash(r:&Receipt):vector<u8>{policy::hash_bytes(bcs::to_bytes(r))}
