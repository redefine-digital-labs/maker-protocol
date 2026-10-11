/// Structural validation of copyable publication metadata. No product, rights,
/// payment, registry, publication installation or mutable asset is accepted here.
/// Codes are returned to the issuer, which preserves its native abort location.
module soulidity_maker_publication::publication_validation;
use std::bcs;
use soulidity_model::policy::{Self,Definition,Adapter};
use soulidity_visual::visual::{Self,Scene};
const EPolicy:u64=9;const EDefinition:u64=5;const EBounds:u64=10;
public struct AdapterKey has drop {source:vector<u8>,part:vector<u8>}
/// Required digest/byte-length metadata, never certified custody or authority.
public struct Expected has copy,drop,store {asset:vector<u8>,bytes:u64}
fun digest_less(a:&vector<u8>,b:&vector<u8>):bool{
    // Every digest originates in a private constructor-validated Fragment.
    let mut i=0u64;while(i < 32){if(a[i]!=b[i])return a[i] < b[i];i=i+1};false
}
fun sift_expected(rows:&mut vector<Expected>,start:u64,end:u64){
    let mut parent=start;while(parent < end/2){let mut child=parent*2+1;
        if(child+1 < end && digest_less(&rows[child].asset,&rows[child+1].asset))child=child+1;
        if(!digest_less(&rows[parent].asset,&rows[child].asset))return;
        rows.swap(parent,child);parent=child
    }
}
fun sort_expected(rows:&mut vector<Expected>){
    let n=rows.length();let mut start=n/2;while(start>0){start=start-1;sift_expected(rows,start,n)};
    let mut end=n;while(end>1){end=end-1;rows.swap(0,end);sift_expected(rows,0,end)}
}
/// Exact lexicographic ordering. First-byte buckets reduce work for distributed
/// SHA digests; each bucket still uses heap sort for adversarial shared prefixes.
/// Only this small projection is reordered, never Fragment/mask/display indices.
public fun expected_assets(definitions:&vector<Definition>):(vector<Expected>,u64){
    let mut buckets:vector<vector<Expected>> = vector::tabulate!(256,|_|vector[]);
    definitions.do_ref!(|d|visual::fragments(policy::representation(d)).do_ref!(|f|{
        let asset=visual::fragment_asset(f);let index=(asset[0] as u64);
        buckets[index].push_back(Expected{asset,bytes:visual::fragment_bytes(f)})
    }));
    let mut rows:vector<Expected> = vector[];
    buckets.reverse();while(!buckets.is_empty()){
        let mut bucket=buckets.pop_back();
        sort_expected(&mut bucket);bucket.reverse();while(!bucket.is_empty()){
            let r=bucket.pop_back();if(rows.is_empty() || rows[rows.length()-1].asset!=r.asset)rows.push_back(r)
            else if(rows[rows.length()-1].bytes!=r.bytes)return (vector[],4)
        }
    };
    if(rows.length()>500)(vector[],6) else (rows,0)
}
public fun expected_digest(r:&Expected):vector<u8>{r.asset}
public fun expected_size(r:&Expected):u64{r.bytes}
public fun expected_index(rows:&vector<Expected>,asset:vector<u8>):Option<u64>{
    policy::assert_hash(&asset);let prefix=asset[0];let mut low=0u64;let mut high=rows.length();
    while(low < high){let mid=low+(high-low)/2;let r=&rows[mid];let head=r.asset[0];
        if(head < prefix)low=mid+1
        else if(head>prefix)high=mid
        else {if(r.asset==asset)return option::some(mid);if(digest_less(&r.asset,&asset))low=mid+1 else high=mid}
    };option::none()
}
/// Read-only directory position; this is metadata, never issuance authority.
public fun expected_lookup(rows:&vector<Expected>,asset:vector<u8>):Option<u64>{
    let index=expected_index(rows,asset);if(index.is_some())option::some(rows[index.destroy_some()].bytes) else option::none()
}

public fun validate(manifest:&vector<u8>,configuration:&vector<u8>,access_mode:u8,access_price:u64,completion_mode:u8,completion_price:u64,quota:u64,royalty_bps:u16,beneficiary:address,parts:&vector<vector<u8>>,required_parts:&vector<vector<u8>>,definitions:&vector<Definition>,adapters:&vector<Adapter>,scene:&Scene):u64{
    policy::assert_hash(manifest);policy::assert_hash(configuration);
    if(!(access_mode<=2 && completion_mode<=3 && royalty_bps<=10000 && beneficiary!=@0x0))return EPolicy;
    if(!((access_mode==1 && access_price>0)||(access_mode!=1 && access_price==0)))return EPolicy;
    if(!((completion_mode==0 && completion_price==0 && quota==0)||(completion_mode==1 && completion_price>0 && quota==0)||(completion_mode==2 && completion_price>0 && quota>0)||(completion_mode==3 && completion_price==0 && quota>0)))return EPolicy;
    if(parts.is_empty() || parts.length()>64 || definitions.length()>256 || adapters.length()>256)return EBounds;
    let mut seen=vector[];let mut i=0;
    while(i < parts.length()){let p=&parts[i];policy::assert_key(p);if(seen.contains(p))return EDefinition;seen.push_back(*p);i=i+1};
    i=0;while(i < required_parts.length()){if(!parts.contains(&required_parts[i]))return EDefinition;i=i+1};
    let scene_parts=visual::parts(scene);i=0;while(i < parts.length()){if(!scene_parts.contains(&parts[i]))return EDefinition;i=i+1};
    let mut seen_defs=vector[];let mut fragments=0;i=0;
    while(i < definitions.length()){
        let d=&definitions[i];if(!parts.contains(&policy::definition_part(d)))return EDefinition;
        visual::assert_native(policy::representation(d),scene);fragments=fragments+visual::fragments(policy::representation(d)).length();
        let hash=policy::definition_key(d);if(seen_defs.contains(&hash))return EDefinition;seen_defs.push_back(hash);i=i+1
    };if(fragments>500)return EBounds;
    let mut seen_adapters=vector[];i=0;
    while(i < adapters.length()){
        let a=&adapters[i];if(!parts.contains(&policy::adapter_part(a)) || policy::adapter_scene(a)!=visual::scene_hash(scene))return EDefinition;
        let k=policy::hash_bytes(bcs::to_bytes(&AdapterKey{source:policy::adapter_source(a),part:policy::adapter_part(a)}));if(seen_adapters.contains(&k))return EDefinition;seen_adapters.push_back(k);i=i+1
    };0
}

/// Supplied vectors are copyable metadata, never installed Product state.
public fun fragment_count(definitions:&vector<Definition>):u64{let mut n=0;definitions.do_ref!(|d|n=n+visual::fragments(policy::representation(d)).length());n}
public fun validate_added_definitions(parts:&vector<vector<u8>>,definitions:&vector<Definition>,extra:&vector<Definition>,scene:&Scene):u64{
    if(definitions.length()+extra.length()>256)return EBounds;
    let mut seen=definitions.map_ref!(|d|policy::definition_key(d));let mut fragments=fragment_count(definitions);let mut i=0;
    while(i < extra.length()){
        let d=&extra[i];if(!parts.contains(&policy::definition_part(d)))return EDefinition;
        visual::assert_native(policy::representation(d),scene);let k=policy::definition_key(d);if(seen.contains(&k))return EDefinition;seen.push_back(k);
        fragments=fragments+visual::fragments(policy::representation(d)).length();if(fragments>500)return EBounds;i=i+1
    };0
}
public fun validate_added_adapters(parts:&vector<vector<u8>>,adapters:&vector<Adapter>,extra:&vector<Adapter>,scene:&Scene):u64{
    if(adapters.length()+extra.length()>256)return EBounds;
    let mut seen=adapters.map_ref!(|a|adapter_key(a));let mut i=0;
    while(i < extra.length()){
        let a=&extra[i];if(!parts.contains(&policy::adapter_part(a)) || policy::adapter_scene(a)!=visual::scene_hash(scene))return EDefinition;
        let k=adapter_key(a);if(seen.contains(&k))return EDefinition;seen.push_back(k);i=i+1
    };0
}
fun adapter_key(a:&Adapter):vector<u8>{policy::hash_bytes(bcs::to_bytes(&AdapterKey{source:policy::adapter_source(a),part:policy::adapter_part(a)}))}
public fun validate_outputs(outputs:&vector<soulidity_maker_publication::output_data::Policy>):u64{
    if(outputs.is_empty() || outputs.length()>256)return EPolicy;let mut seen=vector[];let mut i=0;
    while(i < outputs.length()){let key=soulidity_maker_publication::output_data::policy_key(&outputs[i]);if(seen.contains(&key))return EPolicy;seen.push_back(key);i=i+1};0
}
public fun validate_physical(definitions:&vector<Definition>,terms:&vector<soulidity_model::material_policy::Terms>):u64{
    if(terms.length()>10000)return EPolicy;let mut seen=vector[];let mut i=0;
    while(i < terms.length()){let hash=soulidity_model::material_policy::definition(&terms[i]);if(seen.contains(&hash) || !definitions.any!(|d|policy::definition_hash(d)==hash))return EDefinition;seen.push_back(hash);i=i+1};0
}

/// All arguments are metadata. Native publication passes its actual frozen
/// parent and previous immutable version after Control/version/lifecycle checks.
public fun validate_binding(scene:&Scene,parts:&vector<vector<u8>>,required:&vector<vector<u8>>,definitions:&vector<Definition>,outputs:&vector<soulidity_maker_publication::output_data::Policy>,pack_key:&vector<u8>,rates:&soulidity_maker_terms::maker_resale::Rates,access_mode:u8,parent_scene:Option<Scene>,parent_paths:vector<visual::Selector>,prior_key:Option<vector<u8>>):u64{
    let own=definitions.map_ref!(|d|policy::definition_path(d));let mut rows=own;
    if(parent_scene.is_none()){
        if(access_mode==2 || outputs.is_empty() || !pack_key.is_empty())return EPolicy;
        let mut i=0;while(i < outputs.length()){if(soulidity_maker_publication::output_data::renderer(&outputs[i])!=visual::renderer(scene))return EPolicy;i=i+1}
    }else{
        let parent=parent_scene.borrow();visual::assert_additive(parent,scene);if(!required.is_empty())return 8;
        let all_parts=visual::parts(scene);let mut i=0;while(i < all_parts.length()){let part=&all_parts[i];if(!visual::parts(parent).contains(part) && !parts.contains(part))return EDefinition;i=i+1};
        i=0;while(i < own.length()){if(parent_paths.contains(&own[i]))return EDefinition;i=i+1};
        visual::assert_pack_rule_owners(parent,scene,parts,&own);rows.append(parent_paths);policy::assert_key(pack_key);
        if(!outputs.is_empty() || soulidity_maker_terms::maker_resale::oc_bps(rates)!=0 || soulidity_maker_terms::maker_resale::maker_bps(rates)!=0)return EPolicy;
        if(prior_key.is_some() && *prior_key.borrow()!=*pack_key)return EPolicy
    };
    visual::assert_scene_references(scene,&rows);
    definitions.do_ref!(|d|visual::assert_representation_references(scene,&rows,policy::representation(d)));0
}
