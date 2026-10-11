/// Exact published visual scopes and typed slots. Values are metadata, not rights.
/// Profiles live in separate Table fields; adding Packs cannot inflate one Scene.
module soulidity_model::assembly;
use std::bcs;
use std::hash;
use std::type_name::{Self,TypeName};
use sui::table::{Self,Table};
use soulidity_visual::visual::{Self,Scene,ColorChoice,Fact,Layer};
use soulidity_model::policy::{Self,Source,Layout,Adapter};
const EScope:u64=1;const EPart:u64=2;const ECapacity:u64=3;const EColor:u64=4;
const EVariant:u64=5;

public struct Scope has copy,drop,store {protocol:ID,product:ID,source_type:TypeName,version:u64,policy:vector<u8>}
public struct PartKey has copy,drop,store {scope:Option<Scope>,key:vector<u8>}
public struct Profile has copy,drop,store {scope:Scope,parent:Option<Scope>,scene:Scene,parts:vector<vector<u8>>,adapters:vector<Adapter>}
public struct ProfileSnapshot has copy,drop,store {scope:Scope,parent:Option<Scope>,scene:vector<u8>,parts:vector<vector<u8>>,colors:vector<ColorChoice>,adapters:vector<vector<u8>>}
public struct State has store {root:Scope,base_parts:vector<vector<u8>>,scopes:vector<Scope>,parts:vector<PartKey>,profiles:Table<Scope,Profile>,palettes:Table<Scope,vector<ColorChoice>>}
public struct Equipped has copy,drop {part:PartKey,source:Source,layout:Layout,adapter:Option<Adapter>}
/// Creator-attested visual metadata. It is neither an Item nor an issuance,
/// payment, entitlement or Soul update capability. Private fields are deliberate.
public struct Variant has copy,drop,store {
    domain:vector<u8>,schema:u16,original:Profile,target:Scene,adapters:vector<Adapter>,
    target_hash:vector<u8>,commitment:vector<u8>,
}
public struct VariantCommitment has drop {
    domain:vector<u8>,schema:u16,original:Profile,target:Scene,adapters:vector<Adapter>,
}
public fun variant<W:drop,P:key>(w:W,product:&P,original:Profile,target:Scene,adapters:vector<Adapter>):Variant{
    policy::assert_producer<W,P>(w);
    assert!(original.scope.product==object::id(product)
        && original.scope.source_type==type_name::with_defining_ids<P>(),EScope);
    visual::assert_variant_contract(&original.scene,&target);
    assert!(adapters.length()<=512,ECapacity);let target_hash=visual::scene_hash(&target);
    let mut keys=vector[];adapters.do_ref!(|a|{
        let part=policy::adapter_part(a);assert!(original.parts.contains(&part)
            && policy::adapter_scene(a)==target_hash,EVariant);
        let mut key=policy::adapter_source(a);key.append(part);assert!(!keys.contains(&key),EVariant);keys.push_back(key)
    });
    let domain=b"soulidity/visual-variant/v1";let schema=1;
    let commitment=policy::hash_bytes(bcs::to_bytes(&VariantCommitment{domain,schema,original,target,adapters}));
    let v=Variant{domain,schema,original,target,adapters,target_hash,commitment};
    assert!(bcs::to_bytes(&v).length()<=196608,ECapacity);v
}
public fun variant_scope(v:&Variant):Scope{v.original.scope}
public fun variant_original(v:&Variant):&Profile{&v.original}
public fun variant_scene(v:&Variant):&Scene{&v.target}
public fun variant_adapters(v:&Variant):vector<Adapter>{v.adapters}
public fun variant_hash(v:&Variant):vector<u8>{v.commitment}
public fun variant_scene_hash(v:&Variant):vector<u8>{v.target_hash}
/// Stable scope ordering makes equivalent creator sets one commitment.
public fun canonical_variants(mut values:vector<Variant>):vector<Variant>{
    let mut i=1;while(i < values.length()){let mut j=i;
        while(j>0 && less(&bcs::to_bytes(&variant_scope(&values[j])),&bcs::to_bytes(&variant_scope(&values[j-1])))){values.swap(j,j-1);j=j-1};i=i+1
    };values
}
public fun variant_commitments(values:&vector<Variant>):vector<vector<u8>>{
    canonical_variants(*values).map_ref!(|v|variant_hash(v))
}
fun find_variant(v:&vector<Variant>,scope:Scope):Option<u64>{
    let mut found=option::none();let mut i=0;
    while(i < v.length()){if(v[i].original.scope==scope){assert!(found.is_none(),EVariant);found=option::some(i)};i=i+1};found
}
/// Pin every creator attestation to the exact admitted publication, including
/// the original policy commitment and parent. Identical scenes are not identity.
public fun assert_variants(s:&State,base:&Scene,variants:&vector<Variant>){
    assert!(variants.length()<=65,ECapacity);let mut scopes=vector[];
    variants.do_ref!(|v|{
        let p=&v.original;assert!(!scopes.contains(&p.scope),EVariant);scopes.push_back(p.scope);
        if(p.scope==s.root)assert!(p.parent.is_none() && p.scene==*base && p.parts==s.base_parts,EScope)
        else assert!(admitted(s,p.scope) && *published_profile(s,p.scope)==*p,EScope)
    })
}
/// Copyable visual metadata, not an entitlement or asset issuance capability.
public fun scope<W:drop,P:key>(witness:W,product:&P,protocol:ID,version:u64,commitment:vector<u8>):Scope{
    policy::assert_producer<W,P>(witness);policy::assert_hash(&commitment);assert!(version>0,EScope);
    Scope{protocol,product:object::id(product),source_type:type_name::with_defining_ids<P>(),version,policy:commitment}
}
public fun profile<W:drop,P:key>(witness:W,product:&P,scope:Scope,parent:Option<Scope>,scene:Scene,parts:vector<vector<u8>>,adapters:vector<Adapter>):Profile{
    policy::assert_producer<W,P>(witness);
    assert!(scope.product==object::id(product) && scope.source_type==type_name::with_defining_ids<P>(),EScope);
    if(parent.is_some()){let p=parent.borrow();assert!(p.protocol==scope.protocol && p.source_type==scope.source_type && p.product!=scope.product,EScope)};
    assert!(parts.length()<=512,ECapacity);let mut seen=vector[];
    parts.do_ref!(|part|{policy::assert_key(part);assert!(visual::parts(&scene).contains(part) && !seen.contains(part),EPart);seen.push_back(*part)});
    Profile{scope,parent,scene,parts,adapters}
}
public fun profile_scope(p:&Profile):Scope{p.scope}
public fun profile_scene(p:&Profile):&Scene{&p.scene}
public fun profile_adapters(p:&Profile):vector<Adapter>{p.adapters}
public fun profile_parent(p:&Profile):Option<Scope>{p.parent}
public fun scope_product(s:&Scope):ID{s.product}
public fun scope_type(s:&Scope):TypeName{s.source_type}
public fun scope_protocol(s:&Scope):ID{s.protocol}
public fun scope_version(s:&Scope):u64{s.version}
public fun scope_policy(s:&Scope):vector<u8>{s.policy}
public fun root_part(key:vector<u8>):PartKey{policy::assert_key(&key);PartKey{scope:option::none(),key}}
public fun scoped_part(scope:Scope,key:vector<u8>):PartKey{policy::assert_key(&key);PartKey{scope:option::some(scope),key}}
public fun part_scope(p:&PartKey):Option<Scope>{p.scope}
public fun part_name(p:&PartKey):vector<u8>{p.key}
public fun part_commitment(p:&PartKey):vector<u8>{hash::sha2_256(bcs::to_bytes(p))}
public fun new(root:&Profile,ctx:&mut TxContext):State{
    assert!(root.parent.is_none(),EScope);State{root:root.scope,base_parts:root.parts,scopes:vector[],parts:root.parts.map_ref!(|p|root_part(*p)),profiles:table::new(ctx),palettes:table::new(ctx)}
}
public fun root(s:&State):Scope{s.root}
public fun parts(s:&State):vector<PartKey>{s.parts}
public fun scopes(s:&State):vector<Scope>{s.scopes}
public fun admitted(s:&State,scope:Scope):bool{s.profiles.contains(scope)}
public fun published_profile(s:&State,scope:Scope):&Profile{assert!(admitted(s,scope),EScope);s.profiles.borrow(scope)}
/// Mutates only the caller-owned value. Profile provenance is already attested;
/// no Soul, publication, entitlement or extra asset is issued.
public fun admit(s:&mut State,base:&Scene,p:Profile){
    assert!(p.parent==option::some(s.root) && p.scope.protocol==s.root.protocol && p.scope.source_type==s.root.source_type && p.scope.product!=s.root.product,EScope);visual::assert_additive(base,&p.scene);
    if(visual::scene_hash(base)==visual::scene_hash(&p.scene) && p.adapters.is_empty()){
        assert!(p.parts.all!(|part|s.base_parts.contains(part)),EPart);return
    };
    if(s.profiles.contains(p.scope)){assert!(*s.profiles.borrow(p.scope)==p,EScope);return};assert!(s.scopes.length()<64,ECapacity);
    // A reserved inherited Scene Part is not implicitly a published root slot.
    p.parts.do_ref!(|part|{if(visual::parts(base).contains(part))assert!(s.base_parts.contains(part),EPart)});
    s.profiles.add(p.scope,p);s.palettes.add(p.scope,visual::default_colors(&p.scene));s.scopes.push_back(p.scope);
    let mut i=1;while(i < s.scopes.length()){let mut j=i;while(j>0 && less(&bcs::to_bytes(&s.scopes[j]),&bcs::to_bytes(&s.scopes[j-1]))){s.scopes.swap(j,j-1);j=j-1};i=i+1};
    let mut parts=s.base_parts.map_ref!(|p|root_part(*p));s.scopes.do_ref!(|scope|{s.profiles.borrow(*scope).parts.do_ref!(|part|{if(!s.base_parts.contains(part))parts.push_back(scoped_part(*scope,*part))})});assert!(parts.length()<=512,ECapacity);s.parts=parts;
    assert!(bcs::to_bytes(&snapshots(s)).length()<=131072,ECapacity)
}
fun less(a:&vector<u8>,b:&vector<u8>):bool{let mut i=0;while(i < a.length() && i < b.length()){if(a[i]!=b[i])return a[i]<b[i];i=i+1};a.length()<b.length()}
public fun source_part(s:&State,base:&Scene,source:&Source):PartKey{
    assert!(policy::source_type(source)==s.root.source_type && policy::source_protocol(source)==s.root.protocol && policy::source_maker(source)==s.root.product && policy::maker_version(source)==s.root.version,EScope);
    let key=policy::part(source);
    if(visual::representation_scene(policy::source_representation(source))==visual::scene_hash(base)){assert!(s.base_parts.contains(&key),EPart);return root_part(key)};
    let scope=source_scope(s,source);let profile=s.profiles.borrow(scope);visual::assert_native(policy::source_representation(source),&profile.scene);assert!(profile.parts.contains(&key),EPart);
    if(s.base_parts.contains(&key))root_part(key) else scoped_part(scope,key)
}
fun source_scope(s:&State,source:&Source):Scope{
    let mut found=option::none();s.scopes.do_ref!(|scope|{if(scope.product==policy::source_product(source) && scope.version==policy::source_version(source)){assert!(found.is_none(),EScope);found=option::some(*scope)}});assert!(found.is_some(),EScope);found.destroy_some()
}
public fun pack_colors(s:&State,scope:Scope):vector<ColorChoice>{assert!(admitted(s,scope),EScope);*s.palettes.borrow(scope)}
public fun set_pack_colors(s:&mut State,base:&Scene,scope:Scope,colors:vector<ColorChoice>){
    let p=published_profile(s,scope);visual::assert_colors(&p.scene,&colors);
    colors.do_ref!(|c|{if(visual::channels(base).any!(|b|visual::channel_key(b)==visual::choice_channel(c)))assert!(visual::choice_swatch(c).is_none(),EColor)});
    *s.palettes.borrow_mut(scope)=colors;assert!(bcs::to_bytes(&snapshots(s)).length()<=131072,ECapacity)
}
public fun snapshots(s:&State):vector<ProfileSnapshot>{s.scopes.map_ref!(|scope|{let p=s.profiles.borrow(*scope);ProfileSnapshot{scope:*scope,parent:p.parent,scene:visual::scene_hash(&p.scene),parts:p.parts,colors:*s.palettes.borrow(*scope),adapters:p.adapters.map_ref!(|a|policy::hash_bytes(bcs::to_bytes(a)))}})}
/// Cached UI preferences are not an unused Pack contribution to Complete.
/// A profile is active only when an actual selection uses that publication.
public fun active_scopes(s:&State,equipped:&vector<Equipped>):vector<Scope>{let mut active=vector[];s.scopes.do_ref!(|scope|{if(equipped.any!(|e|e.part.scope==option::some(*scope) || (policy::source_product(&e.source)==scope.product && policy::source_version(&e.source)==scope.version)))active.push_back(*scope)});active}
public fun active_snapshots(s:&State,equipped:&vector<Equipped>):vector<ProfileSnapshot>{let active=active_scopes(s,equipped);let mut snapshots=vector[];snapshots(s).do!(|p|{if(active.contains(&p.scope))snapshots.push_back(p)});snapshots}
public fun active_parts(s:&State,equipped:&vector<Equipped>):vector<PartKey>{let active=active_scopes(s,equipped);let mut parts=vector[];s.parts.do_ref!(|p|{if(p.scope.is_none() || active.contains(p.scope.borrow()))parts.push_back(*p)});parts}
public fun snapshot_scope(p:&ProfileSnapshot):Scope{p.scope}
public fun snapshot_scene(p:&ProfileSnapshot):vector<u8>{p.scene}
public fun snapshot_colors(p:&ProfileSnapshot):vector<ColorChoice>{p.colors}
public fun equipped(part:PartKey,source:Source,layout:Layout):Equipped{Equipped{part,source,layout,adapter:option::none()}}
public fun mapped_equipped(part:PartKey,source:Source,layout:Layout,adapter:Option<Adapter>):Equipped{Equipped{part,source,layout,adapter}}
public fun equipped_part(e:&Equipped):PartKey{e.part}
public fun equipped_source(e:&Equipped):&Source{&e.source}
public fun equipped_layout(e:&Equipped):Layout{e.layout}
public fun equipped_adapter(e:&Equipped):Option<Adapter>{e.adapter}
fun local_facts(equipped:&vector<Equipped>,scope:Option<Scope>):vector<Fact>{
    let mut facts=vector[];equipped.do_ref!(|e|{if(e.part.scope.is_none() || e.part.scope==scope)facts.push_back(policy::visual_fact(&e.source,e.part.key))});facts
}
fun owned_facts(equipped:&vector<Equipped>,scope:Scope):vector<Fact>{
    let mut facts=vector[];equipped.do_ref!(|e|{if(e.part.scope==option::some(scope) || (e.part.scope.is_none() && policy::source_product(&e.source)==scope.product && policy::source_version(&e.source)==scope.version))facts.push_back(policy::visual_fact(&e.source,e.part.key))});facts
}
fun effective_colors(s:&State,root:&vector<ColorChoice>,scope:Scope):vector<ColorChoice>{
    let mut colors=*s.palettes.borrow(scope);let mut i=0;while(i < colors.length()){root.do_ref!(|c|{if(visual::choice_channel(c)==visual::choice_channel(&colors[i]))*colors.borrow_mut(i)=*c});i=i+1};colors
}
/// Native status is derived from actual admitted publication, never caller metadata.
public fun native_matches(s:&State,base:&Scene,source:&Source,part:PartKey):bool{
    if(policy::source_type(source)!=s.root.source_type || policy::source_protocol(source)!=s.root.protocol || policy::source_maker(source)!=s.root.product || policy::maker_version(source)!=s.root.version || policy::part(source)!=part.key)return false;
    native_matches_scene(s,source,part,&visual::scene_hash(base))
}
/// The hash is computed from the actual immutable base Scene by this module.
/// Reuse it only within a single render call; no caller-supplied or stored cache.
fun native_matches_scene(s:&State,source:&Source,part:PartKey,base_hash:&vector<u8>):bool{
    if(policy::source_type(source)!=s.root.source_type || policy::source_protocol(source)!=s.root.protocol || policy::source_maker(source)!=s.root.product || policy::maker_version(source)!=s.root.version || policy::part(source)!=part.key)return false;
    if(visual::representation_scene(policy::source_representation(source))==*base_hash)return part.scope.is_none() && s.base_parts.contains(&part.key);
    s.scopes.any!(|scope|{let p=s.profiles.borrow(*scope);scope.product==policy::source_product(source) && scope.version==policy::source_version(source) && visual::representation_scene(policy::source_representation(source))==visual::scene_hash(&p.scene) && p.parts.contains(&part.key) && (if(s.base_parts.contains(&part.key))part.scope.is_none() else part.scope==option::some(*scope))})
}
public fun target_scene(s:&State,base:&Scene,part:PartKey):&Scene{if(part.scope.is_none())base else &published_profile(s,part.scope.destroy_some()).scene}
public fun render(s:&State,base:&Scene,colors:&vector<ColorChoice>,equipped:&vector<Equipped>):vector<Layer>{
    visual::assert_colors(base,colors);let root_facts=local_facts(equipped,option::none());visual::assert_rules(base,&root_facts);
    s.scopes.do_ref!(|scope|{let local=local_facts(equipped,option::some(*scope));visual::assert_pack_rules(base,&s.profiles.borrow(*scope).scene,&local,&owned_facts(equipped,*scope))});
    if(equipped.is_empty())return vector[];
    let base_hash=visual::scene_hash(base);
    let mut layers=vector[];equipped.do_ref!(|e|{
        let is_native=native_matches_scene(s,&e.source,e.part,&base_hash);assert!(is_native || e.adapter.is_some(),EPart);
        let target=if(e.adapter.is_some())e.part.scope else if(visual::representation_scene(policy::source_representation(&e.source))==base_hash)option::none() else option::some(source_scope(s,&e.source));
        let mapping=e.adapter.map_ref!(|a|policy::adapter_mapping(a));
        if(target.is_none())layers.append(visual::render_layers(base,policy::source_representation(&e.source),&mapping,policy::source_hash(&e.source),policy::visual_fact(&e.source,e.part.key),&root_facts,colors,policy::visual_transform(&e.layout),policy::layout_color(&e.layout)))
        else {let scope=target.destroy_some();let p=s.profiles.borrow(scope);let local=local_facts(equipped,option::some(scope));layers.append(visual::render_layers(&p.scene,policy::source_representation(&e.source),&mapping,policy::source_hash(&e.source),policy::visual_fact(&e.source,e.part.key),&local,&effective_colors(s,colors,scope),policy::visual_transform(&e.layout),policy::layout_color(&e.layout)))}
    });visual::ordered(layers)
}
/// Deterministic cross-Scene projection using the actual selected Sources.
/// No object is minted, consumed, retargeted or mutated by this value operation.
/// Soul activation must separately verify custody and atomically restore assets.
public fun render_variants(s:&State,base:&Scene,colors:&vector<ColorChoice>,equipped:&vector<Equipped>,variants:&vector<Variant>):vector<Layer>{
    if(variants.is_empty())return render(s,base,colors,equipped);
    assert_variants(s,base,variants);let root_variant=find_variant(variants,s.root);
    let target=if(root_variant.is_some())&variants[*root_variant.borrow()].target else base;
    let target_hash=visual::scene_hash(target);
    visual::assert_colors(target,colors);let root_facts=local_facts(equipped,option::none());visual::assert_rules(target,&root_facts);
    // An active Pack needs the same target frame and inherited rules. Inactive
    // admitted Packs do not force creation of unrelated unused view metadata.
    active_scopes(s,equipped).do_ref!(|scope|{
        let v=find_variant(variants,*scope);let scene=if(v.is_some())&variants[*v.borrow()].target else &published_profile(s,*scope).scene;
        visual::assert_additive(target,scene);let local=local_facts(equipped,option::some(*scope));
        visual::assert_pack_rules(target,scene,&local,&owned_facts(equipped,*scope))
    });
    let mut layers=vector[];equipped.do_ref!(|e|{
        assert!(native_matches(s,base,&e.source,e.part) || e.adapter.is_some(),EPart);
        policy::assert_layout(policy::source_bounds(&e.source),&e.layout);
        let scope=if(e.adapter.is_some())e.part.scope
            else if(visual::representation_scene(policy::source_representation(&e.source))==visual::scene_hash(base))option::none()
            else option::some(source_scope(s,&e.source));
        let v=find_variant(variants,if(scope.is_some())*scope.borrow() else s.root);
        let scene=if(v.is_some())&variants[*v.borrow()].target
            else if(scope.is_some())&published_profile(s,*scope.borrow()).scene else base;
        let mut adapter=option::none();
        if(v.is_some()){
            let source=policy::source_hash(&e.source);
            variants[*v.borrow()].adapters.do_ref!(|a|{
                if(policy::adapter_source(a)==source && policy::adapter_part(a)==e.part.key){
                    assert!(adapter.is_none(),EVariant);adapter=option::some(*a)
                }
            })
        };
        if(adapter.is_none())adapter=e.adapter;
        if(adapter.is_some())policy::assert_layout(policy::adapter_bounds(adapter.borrow()),&e.layout);
        let mapping=adapter.map_ref!(|a|policy::adapter_mapping(a));
        if(scope.is_none()){
            assert!(visual::scene_hash(scene)==target_hash,EVariant);
            layers.append(visual::render_layers(scene,policy::source_representation(&e.source),&mapping,policy::source_hash(&e.source),policy::visual_fact(&e.source,e.part.key),&root_facts,colors,policy::visual_transform(&e.layout),policy::layout_color(&e.layout)))
        }else{
            let scope=*scope.borrow();let local=local_facts(equipped,option::some(scope));
            layers.append(visual::render_layers(scene,policy::source_representation(&e.source),&mapping,policy::source_hash(&e.source),policy::visual_fact(&e.source,e.part.key),&local,&effective_colors(s,colors,scope),policy::visual_transform(&e.layout),policy::layout_color(&e.layout)))
        }
    });visual::ordered(layers)
}
public fun destroy(s:State){let State{root:_,base_parts:_,scopes,parts:_,mut profiles,mut palettes}=s;scopes.do!(|scope|{profiles.remove(scope);palettes.remove(scope)});profiles.destroy_empty();palettes.destroy_empty()}
