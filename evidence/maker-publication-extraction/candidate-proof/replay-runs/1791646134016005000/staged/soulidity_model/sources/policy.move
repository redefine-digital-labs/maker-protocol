/// Value types and validation shared by every issuer and container.
module soulidity_model::policy;

use std::bcs;
use std::hash;
use std::type_name::{Self,TypeName};
use soulidity_foundation::economics::{Self,MarketPolicy,PrimaryPolicy};
use soulidity_visual::visual::{Self,Scene,Representation,Mapping,Fact};

const EInvalid: u64 = 1;
const EBounds: u64 = 2;
const ELicense: u64 = 3;
const EAuthority: u64 = 4;

public struct Layout has copy, drop, store {
    x_negative: bool, x: u64, y_negative: bool, y: u64,
    scale_ppm: u64, rotation_mdeg: u64, rotation_negative:bool,color: vector<u8>,
}
public struct Bounds has copy, drop, store {
    max_x: u64, max_y: u64, min_scale: u64, max_scale: u64,
    max_rotation: u64, colors: vector<vector<u8>>,
}
public struct Definition has copy, drop, store {
    part: vector<u8>, item: vector<u8>, style: vector<u8>,
    rights: u8, content_hash: vector<u8>, license_hash: vector<u8>,
    representation: Representation,
    supply: u64, default_layout: Layout, bounds: Bounds,
    required_styles: vector<vector<u8>>, forbidden_styles: vector<vector<u8>>,
    transferable_use: bool,
}
public struct DefinitionKey has copy,drop,store {part:vector<u8>,item:vector<u8>,style:vector<u8>}
public struct Source has copy, drop, store {
    product: ID, source_type:TypeName, maker: ID, maker_version: u64, version: u64,
    protocol:ID,royalty_bps:u16,beneficiary:address,market:MarketPolicy,primary:PrimaryPolicy,
    definition_hash: vector<u8>, definition: Definition,
}
public struct Adapter has copy, drop, store {
    source_hash: vector<u8>, target_part: vector<u8>, mapping: Mapping, bounds: Bounds,
}

public fun reference(): u8 { 0 }
public fun soul_bound(): u8 { 1 }
public fun transferable(): u8 { 2 }
public fun hash_bytes(bytes: vector<u8>): vector<u8> { hash::sha2_256(bytes) }
public fun assert_hash(hash: &vector<u8>) { assert!(hash.length() == 32, EInvalid) }
public fun assert_key(key: &vector<u8>) { assert!(!key.is_empty() && key.length() <= 64, EInvalid) }
public fun bounds(max_x:u64,max_y:u64,min_scale:u64,max_scale:u64,max_rotation:u64,colors:vector<vector<u8>>): Bounds {
    assert!(min_scale > 0 && min_scale <= max_scale && max_scale <= 100000000, EInvalid);
    assert!(max_rotation <= 360000 && colors.length() <= 64, EInvalid);
    colors.do_ref!(|c| assert!(c.length() == 4, EInvalid));
    Bounds { max_x,max_y,min_scale,max_scale,max_rotation,colors }
}
public fun layout(x_negative:bool,x:u64,y_negative:bool,y:u64,scale_ppm:u64,rotation_mdeg:u64,color:vector<u8>): Layout {
    layout_signed(x_negative,x,y_negative,y,scale_ppm,false,rotation_mdeg,color)
}
public fun layout_signed(x_negative:bool,x:u64,y_negative:bool,y:u64,scale_ppm:u64,rotation_negative:bool,rotation_mdeg:u64,color:vector<u8>):Layout{assert!(color.is_empty() || color.length()==4,EInvalid);let _=visual::transform(visual::signed(x_negative,x),visual::signed(y_negative,y),scale_ppm,visual::signed(rotation_negative,rotation_mdeg));Layout{x_negative:x_negative && x>0,x,y_negative:y_negative && y>0,y,scale_ppm,rotation_mdeg,rotation_negative:rotation_negative && rotation_mdeg>0,color}}
public fun visual_transform(l:&Layout):soulidity_visual::visual::Transform{visual::transform(visual::signed(l.x_negative,l.x),visual::signed(l.y_negative,l.y),l.scale_ppm,visual::signed(l.rotation_negative,l.rotation_mdeg))}
public fun layout_color(l:&Layout):vector<u8>{l.color}
public fun assert_layout(b:&Bounds,l:&Layout) {
    assert!(l.x<=b.max_x && l.y<=b.max_y && l.scale_ppm>=b.min_scale && l.scale_ppm<=b.max_scale && l.rotation_mdeg<=b.max_rotation, EBounds);
    assert!(l.color.is_empty() || b.colors.contains(&l.color), EBounds);
}
public fun definition(part:vector<u8>,item:vector<u8>,style:vector<u8>,rights:u8,content_hash:vector<u8>,license_hash:vector<u8>,representation:Representation,supply:u64,default_layout:Layout,bounds:Bounds,required_styles:vector<vector<u8>>,forbidden_styles:vector<vector<u8>>,transferable_use:bool): Definition {
    assert_key(&part);assert_key(&item);assert_key(&style);
    assert!(rights<=2 && supply>0 && required_styles.length()<=64 && forbidden_styles.length()<=64,EInvalid);
    assert_hash(&content_hash);assert_hash(&license_hash);
    required_styles.do_ref!(|s| assert_hash(s));forbidden_styles.do_ref!(|s| assert_hash(s));
    assert_layout(&bounds,&default_layout);
    Definition { part,item,style,rights,content_hash,license_hash,representation,supply,default_layout,bounds,required_styles,forbidden_styles,transferable_use }
}
public fun definition_key(d:&Definition):vector<u8>{hash_bytes(bcs::to_bytes(&DefinitionKey{part:d.part,item:d.item,style:d.style}))}
public fun definition_part(d:&Definition):vector<u8>{d.part}
public fun definition_path(d:&Definition):soulidity_visual::visual::Selector{visual::selector(option::none(),option::none(),d.part,option::some(d.item),option::some(d.style))}
public fun definition_hash(d:&Definition): vector<u8> { hash_bytes(bcs::to_bytes(d)) }
/// Metadata attestation from the actual source object's defining module.
/// Private Witness construction replaces the former package-only boundary.
/// This is a copyable preview, NEVER a supply/payment or Item issuance permit.
/// Maker relationships/version/rights declarations are attested by the producer.
public fun source<W:drop,P:key>(witness:W,product:&P,maker:ID,maker_version:u64,version:u64,protocol:ID,royalty_bps:u16,beneficiary:address,market:MarketPolicy,primary:PrimaryPolicy,d:Definition): Source {
    assert_producer<W,P>(witness);
    assert!(maker_version>0 && version>0 && royalty_bps<=10000 && beneficiary!=@0x0,EInvalid);
    assert!(economics::market_config(&market)==protocol && economics::primary_policy_config(&primary)==protocol,EInvalid);
    Source {product:object::id(product),source_type:type_name::with_defining_ids<P>(),maker,maker_version,version,protocol,royalty_bps,beneficiary,market,primary,definition_hash:definition_hash(&d),definition:d}
}
/// Only the actual object's defining module can construct the designated marker.
/// Public same-module metadata is never a producer marker.
public fun assert_producer<W:drop,P:key>(witness:W){
    let w=type_name::with_original_ids<W>();let p=type_name::with_original_ids<P>();
    assert!(!w.is_primitive() && w.address_string()==p.address_string() && w.module_string()==p.module_string()
        && *w.datatype_string().as_bytes()==b"PolicyProducer",EAuthority);let _=witness;
}
public fun adapter(source:&Source,target:&Scene,target_part:vector<u8>,mapping:Mapping,bounds:Bounds): Adapter {
    assert_key(&target_part);assert!(visual::parts(target).contains(&target_part),EInvalid);
    visual::assert_mapping(&source.definition.representation,target,&mapping);
    Adapter {source_hash:source_hash(source),target_part,mapping,bounds}
}
public fun source_product(s:&Source): ID {s.product}
public fun source_type(s:&Source):TypeName{s.source_type}
public fun source_maker(s:&Source): ID {s.maker}
public fun maker_version(s:&Source): u64 {s.maker_version}
public fun source_version(s:&Source): u64 {s.version}
/// Full provenance commitment prevents identical definitions from spoofing an adapter source.
public fun source_hash(s:&Source): vector<u8> {hash_bytes(bcs::to_bytes(s))}
public fun source_definition_hash(s:&Source):vector<u8>{s.definition_hash}
public fun source_definition(s:&Source): &Definition {&s.definition}
public fun rights(s:&Source): u8 {s.definition.rights}
public fun part(s:&Source): vector<u8> {s.definition.part}
public fun default_layout(s:&Source): Layout {s.definition.default_layout}
public fun source_bounds(s:&Source): &Bounds {&s.definition.bounds}
public fun use_follows_soul(s:&Source) { assert!(s.definition.transferable_use, ELicense) }
public fun adapter_source(a:&Adapter): vector<u8> {a.source_hash}
public fun adapter_part(a:&Adapter): vector<u8> {a.target_part}
public fun adapter_bounds(a:&Adapter): &Bounds {&a.bounds}
public fun adapter_mapping(a:&Adapter):Mapping{a.mapping}
public fun adapter_scene(a:&Adapter):vector<u8>{visual::mapping_scene(&a.mapping)}
public fun representation(d:&Definition):&Representation{&d.representation}
/// Returns a new creator-owned value. No mutable reference to an existing
/// publication, Source, Item or Soul is exposed; original fields stay unchanged.
public fun extended_definition(d:&Definition,scene:&soulidity_visual::visual::Scene,extra:vector<soulidity_visual::visual::Fragment>):Definition{
    let mut result=*d;result.representation=visual::extend_representation(&d.representation,scene,extra);result
}
public fun source_representation(s:&Source):&Representation{&s.definition.representation}
public fun visual_fact(s:&Source,target_part:vector<u8>):Fact{visual::fact(s.product,s.version,target_part,s.definition.item,s.definition.style)}
public fun assert_rules(s:&Source, selections:&vector<vector<u8>>) {
    s.definition.required_styles.do_ref!(|h| assert!(selections.contains(h),ELicense));
    s.definition.forbidden_styles.do_ref!(|h| assert!(!selections.contains(h),ELicense));
}
public fun supply(d:&Definition): u64 {d.supply}

public fun source_protocol(s:&Source):ID{s.protocol}
public fun source_market(s:&Source):MarketPolicy{s.market}
public fun source_primary(s:&Source):PrimaryPolicy{s.primary}
public fun royalty(s:&Source):u16{s.royalty_bps}
public fun beneficiary(s:&Source):address{s.beneficiary}
