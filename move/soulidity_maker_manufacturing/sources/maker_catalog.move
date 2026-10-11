/// Immutable published product policies, separate tradable control and address-bound use.
module soulidity_maker_manufacturing::maker_catalog;
/// Private values are constructed and consumed only inside this producer.
public struct CreatorAuthority1 has drop {}
/// Retained for compatible type origins; current business uses Revision3.
public struct CreatorRevision1 has drop {}
public struct CreatorRevision2 has drop {}
public struct CreatorRevision3 has drop {}
public struct MAKER_CATALOG has drop {}
fun init(w:MAKER_CATALOG,ctx:&mut TxContext){sui::package::claim_and_keep(w,ctx)}


use std::bcs;
use std::type_name::{Self,TypeName};
use soulidity_origin_protocol::producer_origin::{Self as origin,Snapshot,OriginRequest,PaidAction,CompletionAuthorization};
use soulidity_maker_publication::publication_validation as publication_rules;
use sui::table::{Self,Table};
use sui::coin::Coin;
use sui::clock::Clock;
use walrus::system::{Self as walrus_system,System};
use sui::event;
use sui::dynamic_object_field as dof;
use soulidity_model::policy::{Self,Definition,Source,Adapter};
use soulidity_foundation::economics::{Self,Config,MarketPolicy,PrimaryPolicy,PrimaryReceipt};
use soulidity_maker_publication::output_data as output;
use soulidity_maker_publication::output_data::{Policy};
use soulidity_maker_terms::maker_resale::{Self as resale,Rates};
use soulidity_model::material_policy::{Self,Terms};
use soulidity_foundation::revenue::{Self,Ledger};
use soulidity_visual::visual::{Self,Scene};
use soulidity_model::assembly::{Self,Profile,Scope};
use std::string::String;

/// Source attestation can only be constructed by the actual Product module.
public struct SoulProducer has drop {}
/// Source previews require the real Product and this module's private value.
public struct PolicyProducer has drop {}
public struct ComponentProducer has drop {}
public struct ManufacturingProducer has drop {}
public struct PhysicalExecution has copy,drop,store {producer:TypeName,revision:TypeName}
public struct Execution has copy,drop,store {adapter:TypeName,revision:TypeName,target:TypeName}

/// Minting, quota/replay reservation and full primary settlement are atomic.
/// No producer witness, unpaid root or mutable Product UID is exposed externally.


const EControl:u64=1; const EVersion:u64=2; const ELifecycle:u64=3;
const EAccess:u64=4; const EDefinition:u64=5; const ECap:u64=6; const EAttempt:u64=7;
const EParent:u64=8; const EPolicy:u64=9; const EBounds:u64=10;
public struct Control has key,store {id:UID,product:ID}
public struct Product<phantom C> has key {
    id:UID, protocol:ID, creator:address, market:MarketPolicy,primary:PrimaryPolicy,maker:Option<ID>, parent_version:u64,parent_snapshot:Option<ParentSnapshot>, version:u64, lifecycle:u8,
    versions:Table<u64,Version>, access:Table<AccessKey,Access>,income:Ledger<C>, issued:Table<vector<u8>,u64>,
    completes:Table<CountKey,u64>, attempts:Table<RequestKey,ID>,payments:Table<RequestKey,PrimaryReceipt>,physical_registries:Table<u64,ID>,
}
public struct AccessKey has copy,drop,store {wallet:address,version:u64}
/// Address/version-bound entitlement data cannot be transferred as a Pass.
public struct Access has copy,drop,store {product:ID,version:u64,policy_hash:vector<u8>,manifest:vector<u8>,holder:address,paid:u64,issued_at_ms:u64}
public struct SupplyKey has copy,drop,store { version:u64, definition:vector<u8> }
public struct CountKey has copy,drop,store {version:u64,wallet:address}
public struct RequestKey has copy,drop,store {actor:address,kind:u8,attempt:vector<u8>}
/// Frozen from the actual immutable Maker publication at Pack creation.
public struct ParentSnapshot has copy,drop,store {scope:Scope,policy_hash:vector<u8>,scene:Scene,paths:vector<soulidity_visual::visual::Selector>}
/// Actual publication identity, not a certified Release or a bearer capability.
public struct PublicationContext has copy,drop,store {protocol:ID,product:ID,version:u64,parent:Option<ID>,parent_version:u64,parent_policy:Option<vector<u8>>}
public struct Version has copy,drop,store {
    execution:Option<Execution>,physical_execution:Option<PhysicalExecution>,manifest:vector<u8>, configuration:vector<u8>, policy_hash:vector<u8>,publication:Option<PublicationContext>,
    access_mode:u8, access_price:u64, completion_mode:u8, completion_price:u64,
    quota:u64, cap:u64, royalty_bps:u16, beneficiary:address, soul_rates:Rates,market:Option<MarketPolicy>,primary:Option<PrimaryPolicy>,
    parts:vector<vector<u8>>, required_parts:vector<vector<u8>>,
    definitions:vector<Definition>, adapters:vector<Adapter>,scene:Scene,outputs:vector<Policy>,pack_key:vector<u8>,physical:vector<Terms>,
}
public struct Published has copy,drop {product:ID,maker:Option<ID>,version:u64,policy_hash:vector<u8>}
public struct AccessPurchased has copy,drop {product:ID,buyer:address,version:u64,attempt:vector<u8>}
public struct LifecycleChanged has copy,drop {product:ID,lifecycle:u8}
public struct CertificationKey has copy,drop,store {version:u64}

/// FREE=0, ONE_TIME_PAID=1, INCLUDED_WITH_MAKER=2. Completion: free=0, paid=1,
/// quota-then-paid=2, quota-only=3. A zero cap explicitly means unlimited.
public fun version(manifest:vector<u8>,configuration:vector<u8>,access_mode:u8,access_price:u64,completion_mode:u8,completion_price:u64,quota:u64,cap:u64,royalty_bps:u16,beneficiary:address,soul_rates:Rates,parts:vector<vector<u8>>,required_parts:vector<vector<u8>>,definitions:vector<Definition>,adapters:vector<Adapter>,scene:Scene):Version {
    let invalid=publication_rules::validate(&manifest,&configuration,access_mode,access_price,completion_mode,completion_price,quota,royalty_bps,beneficiary,&parts,&required_parts,&definitions,&adapters,&scene);
    assert!(invalid==0,invalid);
    assert_native_economics(access_price,completion_price,quota,cap,royalty_bps,&soul_rates);
    let mut v=Version {execution:option::none(),physical_execution:option::none(),manifest,configuration,policy_hash:vector[],publication:option::none(),access_mode,access_price,completion_mode,completion_price,quota,cap,royalty_bps,beneficiary,soul_rates,market:option::none(),primary:option::none(),parts,required_parts,definitions,adapters,scene,outputs:vector[],pack_key:vector[],physical:vector[]};
    v.policy_hash=policy::hash_bytes(bcs::to_bytes(&v));v
}
public(package) fun create_maker<C>(cfg:&Config<C>,control_royalty_bps:u16,ctx:&mut TxContext):ID { economics::assert_manufacturing_business<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{});create<C>(cfg,economics::manufacturing_market_policy(cfg,control_royalty_bps,ctx),control_royalty_bps,economics::manufacturing_primary_policy(cfg),option::none(),0,option::none(),ctx) }
public(package) fun create_pack<C>(maker:&Product<C>,parent_version:u64,control:&mut Control,cfg:&Config<C>,control_royalty_bps:u16,ctx:&mut TxContext):ID { create_pack_value(maker,parent_version,control,cfg,control_royalty_bps,ctx,false) }
public(package) fun create_pack_value<C>(maker:&Product<C>,parent_version:u64,control:&mut Control,cfg:&Config<C>,control_royalty_bps:u16,ctx:&mut TxContext,native_route:bool):ID {assert_current_writer(cfg);
    assert_control(maker,control);assert!(maker.maker.is_none(),EParent);let _=published(maker,parent_version);
    assert!(maker.protocol==object::id(cfg),EPolicy);(if(native_route)economics::assert_primary(cfg) else economics::assert_manufacturing_primary(cfg));let v=published(maker,parent_version);let snapshot=ParentSnapshot{scope:assembly::scope(PolicyProducer{},maker,maker.protocol,parent_version,v.policy_hash),policy_hash:v.policy_hash,scene:v.scene,paths:v.definitions.map_ref!(|d|policy::definition_path(d))};assert!(bcs::to_bytes(&snapshot).length()<=196608,EBounds);create<C>(cfg,(if(native_route)economics::market_policy(cfg,control_royalty_bps,ctx) else economics::manufacturing_market_policy(cfg,control_royalty_bps,ctx)),control_royalty_bps,maker.primary,option::some(object::id(maker)),parent_version,option::some(snapshot),ctx)
}
fun create<C>(cfg:&Config<C>,market:MarketPolicy,control_royalty_bps:u16,primary:PrimaryPolicy,maker:Option<ID>,parent_version:u64,parent_snapshot:Option<ParentSnapshot>,ctx:&mut TxContext):ID {
    assert_native_royalty(control_royalty_bps);
    let uid=object::new(ctx);let income=revenue::new<C>(&uid,ctx);
    let p=Product<C>{id:uid,protocol:object::id(cfg),creator:ctx.sender(),market,primary,maker,parent_version,parent_snapshot,version:0,lifecycle:0,versions:table::new(ctx),access:table::new(ctx),income,issued:table::new(ctx),completes:table::new(ctx),attempts:table::new(ctx),payments:table::new(ctx),physical_registries:table::new(ctx)};
    let product=object::id(&p);transfer::public_transfer(Control{id:object::new(ctx),product},ctx.sender());transfer::share_object(p);product
}
public(package) fun publish<C>(p:&mut Product<C>,control:&mut Control,expected_version:u64,mut v:Version):vector<u8> {
    assert_control(p,control);assert!(p.version==expected_version,EVersion);assert!(p.lifecycle!=3,ELifecycle);
    // An older compatible constructor can still return this Version type.
    // Final publication must enforce the invariant independently.
    assert_publication_economics(p,&v);
    let parent_scene=p.parent_snapshot.map_ref!(|parent|parent.scene);let parent_paths=p.parent_snapshot.map_ref!(|parent|parent.paths).get_with_default(vector[]);
    let prior_key=if(p.maker.is_some() && p.version>0)option::some(published(p,p.version).pack_key) else option::none();
    let invalid=publication_rules::validate_binding(&v.scene,&v.parts,&v.required_parts,&v.definitions,&v.outputs,&v.pack_key,&v.soul_rates,v.access_mode,parent_scene,parent_paths,prior_key);assert!(invalid==0,invalid);
    assert!(v.market.is_none() && v.primary.is_none() && v.publication.is_none(),EPolicy);v.market=option::some(p.market);v.primary=option::some(p.primary);v.publication=option::some(PublicationContext{protocol:p.protocol,product:object::id(p),version:p.version+1,parent:p.maker,parent_version:p.parent_version,parent_policy:p.parent_snapshot.map_ref!(|s|s.policy_hash)});v.policy_hash=vector[];
    // Empty and 32-byte vector lengths each use one BCS byte. Filling only
    // policy_hash adds exactly 32 bytes; serialize the immutable payload once.
    let encoded=bcs::to_bytes(&v);assert!(encoded.length()+32<=196608,EBounds);let hash=policy::hash_bytes(encoded);v.policy_hash=hash;
    // Capture the small hash before moving Version into the table. Reading v
    // afterwards makes the compiler copy the entire 500-fragment publication.
    let next=p.version+1;p.versions.add(next,v);p.version=next;p.lifecycle=1;
    event::emit(Published{product:object::id(p),maker:p.maker,version:next,policy_hash:hash});hash
}
fun assert_completion_cap(quota:u64,cap:u64){assert!(cap==0 || quota<=cap,EPolicy)}
/// Native Maker/Pack publishing preserves the original authored parameter
/// domain. Generic balances/quotes and the independent Soul standard remain u64.
fun assert_native_royalty(bps:u16){assert!(bps<=1000 && bps%50==0,EPolicy)}
fun assert_native_economics(access:u64,complete:u64,quota:u64,cap:u64,royalty:u16,rates:&Rates){
    assert!(access<=1000000000000 && complete<=1000000000000 && quota<=1000000000 && cap<=1000000000,EPolicy);
    assert_completion_cap(quota,cap);assert_native_royalty(royalty);
    assert_native_royalty(resale::oc_bps(rates));assert_native_royalty(resale::maker_bps(rates))
}
public(package) fun assert_publication_economics<C>(p:&Product<C>,v:&Version){assert_native_royalty(economics::control_royalty_bps(&p.market));assert_native_economics(v.access_price,v.completion_price,v.quota,v.cap,v.royalty_bps,&v.soul_rates)}
#[test_only]
public fun invalid_completion_cap_for_testing(v:&mut Version){v.quota=2;v.cap=1}
#[test_only]
public fun invalid_financial_domain_for_testing(v:&mut Version,field:u8){
    if(field==0){v.access_mode=1;v.access_price=1000000000001}
    else if(field==1){v.completion_mode=1;v.completion_price=1000000000001;v.quota=0}
    else if(field==2){v.completion_mode=3;v.quota=1000000001;v.cap=0}
    else if(field==3)v.cap=1000000001
    else if(field==4)v.royalty_bps=1001
    else if(field==5)v.royalty_bps=1
    else if(field==6)v.soul_rates=resale::rates(1,0)
    else {assert!(field==7,EPolicy);v.soul_rates=resale::rates(0,1)}
}
public(package) fun lifecycle<C>(p:&mut Product<C>,control:&mut Control,expected:u64,state:u8) {
    assert_control(p,control);assert!(p.version==expected && state>=1 && state<=3,EVersion);
    assert!(p.lifecycle!=3 || state==3,ELifecycle);p.lifecycle=state;
    event::emit(LifecycleChanged{product:object::id(p),lifecycle:state});
}
public fun assert_control<C>(p:&Product<C>,c:&Control) {assert!(c.product==object::id(p),EControl)}
public(package) fun attach_certification<C,T:key+store>(p:&mut Product<C>,version:u64,value:T){assert!(version>0 && p.versions.contains(version),EVersion);dof::add(&mut p.id,CertificationKey{version},value)}
public(package) fun certification<C,T:key+store>(p:&Product<C>,version:u64):&T{dof::borrow(&p.id,CertificationKey{version})}
public(package) fun certification_mut<C,T:key+store>(p:&mut Product<C>,version:u64):&mut T{dof::borrow_mut(&mut p.id,CertificationKey{version})}
public fun control_product(c:&Control):ID {c.product}
public fun current_version<C>(p:&Product<C>):u64 {p.version}
public fun protocol<C>(p:&Product<C>):ID {p.protocol}
public fun creator<C>(p:&Product<C>):address{p.creator}
public fun market_policy<C>(p:&Product<C>):MarketPolicy{p.market}
public fun version_market(v:&Version):MarketPolicy{v.market.destroy_some()}
public fun primary_policy<C>(p:&Product<C>):PrimaryPolicy{p.primary}
public fun version_primary(v:&Version):PrimaryPolicy{v.primary.destroy_some()}
public fun assert_active<C>(p:&Product<C>){assert!(p.lifecycle==1,ELifecycle)}
public fun assert_paused<C>(p:&Product<C>){assert!(p.lifecycle==2,ELifecycle)}
public fun physical_registry<C>(p:&Product<C>,version:u64):Option<ID>{if(p.physical_registries.contains(version))option::some(*p.physical_registries.borrow(version)) else option::none()}
#[test_only]
public(package) fun bind_physical<C>(p:&mut Product<C>,version:u64,registry:ID){let _=published(p,version);assert!(p.maker.is_none() && !p.physical_registries.contains(version),EParent);p.physical_registries.add(version,registry)}
public fun parent<C>(p:&Product<C>):Option<ID>{p.maker}
public fun published<C>(p:&Product<C>,v:u64):&Version {assert!(v>0 && p.versions.contains(v),EVersion);p.versions.borrow(v)}
public fun policy_hash(v:&Version):vector<u8>{v.policy_hash}
#[test_only]
public fun publication_preimage_for_testing(mut v:Version):vector<u8>{v.policy_hash=vector[];bcs::to_bytes(&v)}
public fun manifest(v:&Version):vector<u8>{v.manifest}
public fun configuration(v:&Version):vector<u8>{v.configuration}
public fun scene(v:&Version):&Scene{&v.scene}
public fun publication(v:&Version):Option<PublicationContext>{v.publication}
public fun publication_product(p:&PublicationContext):ID{p.product}
public fun publication_version(p:&PublicationContext):u64{p.version}
public fun publication_parent(p:&PublicationContext):Option<ID>{p.parent}
public fun publication_parent_version(p:&PublicationContext):u64{p.parent_version}
public fun publication_parent_policy(p:&PublicationContext):Option<vector<u8>>{p.parent_policy}
public fun parent_scene<C>(p:&Product<C>):Option<Scene>{p.parent_snapshot.map_ref!(|s|s.scene)}
public fun parent_policy<C>(p:&Product<C>):Option<vector<u8>>{p.parent_snapshot.map_ref!(|s|s.policy_hash)}
/// This profile is derived from the actual immutable publication, not a caller's
/// arbitrary Scene/hash. Copying it still does not issue rights or grant access.
public fun assembly_profile<C>(p:&Product<C>,version:u64):Profile{
    let v=published(p,version);let context=v.publication.borrow();assert!(context.protocol==p.protocol && context.product==object::id(p) && context.version==version,EPolicy);
    let scope=assembly::scope(PolicyProducer{},p,p.protocol,version,v.policy_hash);let parent=p.parent_snapshot.map_ref!(|snapshot|snapshot.scope);assembly::profile(PolicyProducer{},p,scope,parent,v.scene,v.parts,v.adapters)
}
/// Current actual Product controller approves a view of an immutable published
/// version. This creates metadata only; supply, fees and component rights stay.
public fun visual_variant<C>(p:&Product<C>,control:&Control,version:u64,target:Scene,adapters:vector<Adapter>):assembly::Variant{
    assert_control(p,control);let profile=assembly_profile(p,version);
    assembly::variant(PolicyProducer{},p,profile,target,adapters)
}
public fun parts(v:&Version):vector<vector<u8>>{v.parts}
public fun definitions(v:&Version):vector<Definition>{v.definitions}
public fun definitions_ref(v:&Version):&vector<Definition>{&v.definitions}
/// Reconstruct an unpublished Version with the original economics/visual contract.
fun rebuilt(v:&Version,definitions:vector<Definition>,adapters:vector<Adapter>):Version{
    assert!(v.market.is_none() && v.primary.is_none() && v.publication.is_none(),EPolicy);
    let mut n=version(v.manifest,v.configuration,v.access_mode,v.access_price,v.completion_mode,v.completion_price,v.quota,v.cap,v.royalty_bps,v.beneficiary,v.soul_rates,v.parts,v.required_parts,definitions,adapters,v.scene);
    n.outputs=v.outputs;n.pack_key=v.pack_key;n.execution=v.execution;n.physical_execution=v.physical_execution;with_physical(n,v.physical)
}
public(package) fun assert_unpublished(v:&Version){assert!(v.market.is_none() && v.primary.is_none() && v.publication.is_none(),EPolicy)}
public(package) fun append_definitions(v:&mut Version,extra:vector<Definition>){
    assert_unpublished(v);let invalid=publication_rules::validate_added_definitions(&v.parts,&v.definitions,&extra,&v.scene);assert!(invalid==0,invalid);v.definitions.append(extra);v.policy_hash=vector[]
}
public(package) fun extend_definition(v:&mut Version,index:u64,extra:vector<visual::Fragment>){
    assert_unpublished(v);assert!(index < v.definitions.length(),EDefinition);assert!(publication_rules::fragment_count(&v.definitions)+extra.length()<=500,EBounds);
    if(!v.physical.is_empty()){let before=policy::definition_hash(&v.definitions[index]);assert!(!v.physical.any!(|t|material_policy::definition(t)==before),EDefinition)};
    let next=policy::extended_definition(&v.definitions[index],&v.scene,extra);*v.definitions.borrow_mut(index)=next;v.policy_hash=vector[]
}
public(package) fun append_adapters(v:&mut Version,extra:vector<Adapter>){
    assert_unpublished(v);let invalid=publication_rules::validate_added_adapters(&v.parts,&v.adapters,&extra,&v.scene);assert!(invalid==0,invalid);v.adapters.append(extra);v.policy_hash=vector[]
}
public(package) fun append_physical(v:&mut Version,extra:vector<Terms>){let mut terms=v.physical;terms.append(extra);*v=with_physical(*v,terms);v.policy_hash=vector[]}
/// Draft mutations use an empty policy hash; only finalization creates a canonical Version.
public(package) fun finalize_metadata(v:&Version):Version{rebuilt(v,v.definitions,v.adapters)}
public(package) fun unpublished_hash(v:&Version):vector<u8>{assert_unpublished(v);let mut candidate=*v;candidate.policy_hash=vector[];policy::hash_bytes(bcs::to_bytes(&candidate))}
public fun required_parts(v:&Version):vector<vector<u8>>{v.required_parts}
public fun soul_rates(v:&Version):Rates{v.soul_rates}
public fun royalty(v:&Version):u16 {v.royalty_bps}
public fun beneficiary(v:&Version):address {v.beneficiary}
public fun adapters(v:&Version):vector<Adapter>{v.adapters}
public fun access_held<C>(p:&Product<C>,version:u64,wallet:address):bool {p.access.contains(AccessKey{wallet,version})}
public fun assert_access<C>(p:&Product<C>,v:u64,wallet:address) {
    assert_active(p);let version=published(p,v);assert!(wallet!=@0x0 && version.access_mode<=1,EAccess);
    if(version.access_mode==1 || access_held(p,v,wallet))assert_access_entitlement(p,v,wallet)
}
/// Exact address/version data is an entitlement record, never an independently
/// transferable capability. Free records must carry zero payment too.
public fun assert_access_entitlement<C>(p:&Product<C>,v:u64,wallet:address){
    assert_active(p);let version=published(p,v);assert!(wallet!=@0x0 && version.access_mode<=1 && access_held(p,v,wallet),EAccess);
    let a=p.access.borrow(AccessKey{wallet,version:v});
    assert!(a.product==object::id(p) && a.version==v && a.holder==wallet && a.policy_hash==version.policy_hash && a.manifest==version.manifest && a.paid==version.access_price,EAccess)
}
public fun access_commitment(a:&Access):vector<u8>{policy::hash_bytes(bcs::to_bytes(a))}
#[test_only]
public fun corrupt_access_for_testing<C>(p:&mut Product<C>,v:u64,wallet:address,field:u8){
    let a=p.access.borrow_mut(AccessKey{wallet,version:v});
    if(field==0)a.product=object::id_from_address(@0x99)
    else if(field==1)a.version=a.version+1
    else if(field==2)a.policy_hash=vector[]
    else if(field==3)a.manifest=vector[]
    else if(field==4)a.holder=@0x99
    else if(field==5)a.paid=a.paid+1
    else {assert!(field==6,EAccess);a.issued_at_ms=1001}
}
/// Public runtime checks derive the actor from TxContext, not a supplied owner.
/// A successful check is not a reusable Seal token or ciphertext certificate.
public(package) fun assert_runtime_access<C>(p:&Product<C>,cfg:&Config<C>,v:u64,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext){ assert_runtime_access_value(p,cfg,v,expected_policy,expected_manifest,expected_config_revision,expected_config_commitment,clock,ctx,false) }
public(package) fun assert_runtime_access_value<C>(p:&Product<C>,cfg:&Config<C>,v:u64,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext,native_route:bool){assert_current_writer(cfg);
    assert_runtime_access_with_current_writer(p,cfg,v,expected_policy,expected_manifest,expected_config_revision,expected_config_commitment,clock,ctx,native_route)
}
/// Private continuation: the same immutable Config passed the current writer check.
fun assert_runtime_access_with_current_writer<C>(p:&Product<C>,cfg:&Config<C>,v:u64,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext,native_route:bool){
    (if(native_route)economics::assert_primary_snapshot(cfg,p.protocol,expected_config_revision,expected_config_commitment) else economics::assert_manufacturing_snapshot(cfg,p.protocol,expected_config_revision,expected_config_commitment));
    assert_runtime_access_product(p,v,expected_policy,expected_manifest,clock,ctx)
}
/// Only called after a full snapshot check for this protocol in this immutable call.
fun assert_runtime_access_product<C>(p:&Product<C>,v:u64,expected_policy:vector<u8>,expected_manifest:vector<u8>,clock:&Clock,ctx:&TxContext){let version=published(p,v);
    assert_runtime_access_published(p,v,version,expected_policy,expected_manifest,clock,ctx)
}
/// Private continuation with the exact Version already borrowed by published.
/// Product and Version remain immutable until all repeated access checks finish.
fun assert_access_published<C>(p:&Product<C>,v:u64,version:&Version,wallet:address){
    assert_active(p);assert!(wallet!=@0x0 && version.access_mode<=1,EAccess);
    if(version.access_mode==1 || access_held(p,v,wallet))assert_access_entitlement_published(p,v,version,wallet)
}
fun assert_access_entitlement_published<C>(p:&Product<C>,v:u64,version:&Version,wallet:address){
    assert_active(p);assert!(wallet!=@0x0 && version.access_mode<=1 && access_held(p,v,wallet),EAccess);
    let a=p.access.borrow(AccessKey{wallet,version:v});
    assert!(a.product==object::id(p) && a.version==v && a.holder==wallet && a.policy_hash==version.policy_hash && a.manifest==version.manifest && a.paid==version.access_price,EAccess)
}
fun assert_runtime_access_published<C>(p:&Product<C>,v:u64,version:&Version,expected_policy:vector<u8>,expected_manifest:vector<u8>,clock:&Clock,ctx:&TxContext){
    assert!(version.policy_hash==expected_policy && version.manifest==expected_manifest,EPolicy);assert_access_published(p,v,version,ctx.sender());
    if(access_held(p,v,ctx.sender()))assert!(p.access.borrow(AccessKey{wallet:ctx.sender(),version:v}).issued_at_ms<=sui::clock::timestamp_ms(clock),EAccess)
}
/// Entering a free Maker records its exact zero-price entitlement in the same
/// transaction as Player creation or Complete. Paid access never auto-claims.
public(package) fun ensure_access<C>(p:&mut Product<C>,cfg:&Config<C>,v:u64,attempt:vector<u8>,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&mut TxContext){ ensure_access_value(p,cfg,v,attempt,fee_revision,expiry,clock,ctx,false) }
public(package) fun ensure_access_value<C>(p:&mut Product<C>,cfg:&Config<C>,v:u64,attempt:vector<u8>,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&mut TxContext,native_route:bool){
    let (access_mode,hash)={let version=published(p,v);(version.access_mode,version.policy_hash)};if(access_mode==0 && !access_held(p,v,ctx.sender()))claim_access_value(p,cfg,v,hash,fee_revision,expiry,attempt,clock,ctx,native_route);
    assert_access(p,v,ctx.sender())
}
public fun assert_pack<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,wallet:address) {
    assert_active(p);assert_active(maker);assert!(maker.maker.is_none() && p.protocol==maker.protocol && p.maker==option::some(object::id(maker)) && p.parent_version==maker_version,EParent);
    assert!(parent_policy(p)==option::some(published(maker,maker_version).policy_hash),EParent);
    let v=published(p,version);
    if(v.access_mode==2)assert_access_entitlement(maker,maker_version,wallet) else assert_access(p,version,wallet);
}
public(package) fun assert_runtime_pack<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,cfg:&Config<C>,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext){ assert_runtime_pack_value(p,maker,maker_version,version,cfg,expected_policy,expected_manifest,expected_config_revision,expected_config_commitment,clock,ctx,false) }
public(package) fun assert_runtime_pack_value<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,cfg:&Config<C>,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext,native_route:bool){
    if(native_route){
        economics::assert_role_primary_snapshot<C,CreatorAuthority1,CreatorRevision3>(cfg,2,p.protocol,expected_config_revision,expected_config_commitment);
        assert_runtime_pack_product(p,maker,maker_version,version,expected_policy,expected_manifest,clock,ctx)
    }else{
        assert_current_writer(cfg);assert_runtime_pack_with_current_writer(p,maker,maker_version,version,cfg,expected_policy,expected_manifest,expected_config_revision,expected_config_commitment,clock,ctx,false)
    }
}
/// Private continuation; no mutable borrow, external call or reusable authority.
fun assert_runtime_pack_with_current_writer<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,cfg:&Config<C>,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext,native_route:bool){
    (if(native_route)economics::assert_primary_snapshot(cfg,p.protocol,expected_config_revision,expected_config_commitment) else economics::assert_manufacturing_snapshot(cfg,p.protocol,expected_config_revision,expected_config_commitment));assert_runtime_pack_product(p,maker,maker_version,version,expected_policy,expected_manifest,clock,ctx)
}
/// Private product continuation after a full writer and Config snapshot check.
fun assert_runtime_pack_product<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,expected_policy:vector<u8>,expected_manifest:vector<u8>,clock:&Clock,ctx:&TxContext){
    let v=published(p,version);assert_runtime_pack_published(p,maker,maker_version,version,v,expected_policy,expected_manifest,clock,ctx)
}
fun assert_runtime_pack_published<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,v:&Version,expected_policy:vector<u8>,expected_manifest:vector<u8>,clock:&Clock,ctx:&TxContext){
    assert!(v.policy_hash==expected_policy && v.manifest==expected_manifest,EPolicy);
    assert_active(p);assert_active(maker);assert!(maker.maker.is_none() && p.protocol==maker.protocol && p.maker==option::some(object::id(maker)) && p.parent_version==maker_version,EParent);
    let parent=parent_policy(p);let mv=published(maker,maker_version);assert!(parent==option::some(mv.policy_hash),EParent);
    if(v.access_mode==2)assert_access_entitlement_published(maker,maker_version,mv,ctx.sender()) else assert_access_published(p,version,v,ctx.sender());
    // Exact same immutable publications; retain repeated access and Clock checks.
    if(v.access_mode==2)assert_runtime_access_published(maker,maker_version,mv,mv.policy_hash,mv.manifest,clock,ctx)
    else assert_runtime_access_published(p,version,v,expected_policy,expected_manifest,clock,ctx)
}
public(package) fun buy_access<C>(p:&mut Product<C>,cfg:&mut Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) { buy_access_value(p,cfg,v,hash,fee_revision,expiry,attempt,payment,clock,ctx,false) }
public(package) fun buy_access_value<C>(p:&mut Product<C>,cfg:&mut Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext,native_route:bool) {
    assert!(p.protocol==object::id(cfg),EPolicy);(if(native_route)economics::assert_primary_live(cfg,fee_revision,expiry,clock) else economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock));assert!(p.lifecycle==1,ELifecycle);
    let version=*published(p,v);assert!(version.policy_hash==hash && version.access_mode==1,EPolicy);
    assert!(!access_held(p,v,ctx.sender()),EAccess);let product_id=object::id(p);record_attempt(p,1,attempt,product_id,ctx);
    let r=if(native_route)access_quote_native(p,cfg,v,ctx.sender(),attempt,expiry) else access_quote(p,cfg,v,ctx.sender(),attempt,expiry);collect_primary_value(p,cfg,r,payment,clock,ctx,native_route);p.payments.add(RequestKey{actor:ctx.sender(),kind:1,attempt},r);
    issue_access(p,v,r,clock,ctx);event::emit(AccessPurchased{product:object::id(p),buyer:ctx.sender(),version:v,attempt});
}
public fun access_quote<C>(p:&Product<C>,cfg:&Config<C>,version:u64,actor:address,attempt:vector<u8>,expiry:u64):PrimaryReceipt {
    let v=published(p,version);assert!(v.access_mode==1,EPolicy);
    economics::route_primary(economics::manufacturing_primary_quote(&v.primary.destroy_some(),cfg,v.access_price,false,v.beneficiary,object::id(p),v.policy_hash,actor,attempt,expiry),object::id(p))
}
public(package) fun collect_primary<C>(p:&mut Product<C>,cfg:&mut Config<C>,r:PrimaryReceipt,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext){ collect_primary_value(p,cfg,r,payment,clock,ctx,false) }
fun collect_primary_value<C>(p:&mut Product<C>,cfg:&mut Config<C>,r:PrimaryReceipt,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext,native_route:bool){
    assert!(p.protocol==object::id(cfg) && economics::primary_receipt_revenue(&r)==option::some(object::id(p)),EPolicy);
    revenue::deposit(&p.id,&mut p.income,(if(native_route)economics::collect_primary<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{},r,payment,clock,ctx) else economics::collect_manufacturing_primary<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{},r,payment,clock,ctx)))
}
fun issue_access<C>(p:&mut Product<C>,v:u64,r:PrimaryReceipt,clock:&Clock,ctx:&TxContext){
    let version=*published(p,v);let product=object::id(p);p.access.add(AccessKey{wallet:ctx.sender(),version:v},Access{product,version:v,policy_hash:version.policy_hash,manifest:version.manifest,holder:ctx.sender(),paid:economics::primary_receipt_gross(&r),issued_at_ms:sui::clock::timestamp_ms(clock)})
}
public(package) fun claim_access<C>(p:&mut Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext){ claim_access_value(p,cfg,v,hash,fee_revision,expiry,attempt,clock,ctx,false) }
public(package) fun claim_access_value<C>(p:&mut Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext,native_route:bool){assert_current_writer(cfg);
    assert!(p.protocol==object::id(cfg),EPolicy);(if(native_route)economics::assert_primary_live(cfg,fee_revision,expiry,clock) else economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock));assert_active(p);
    let version=*published(p,v);assert!(version.access_mode==0 && version.policy_hash==hash,EPolicy);assert!(!access_held(p,v,ctx.sender()),EAccess);
    let id=object::id(p);record_attempt(p,1,attempt,id,ctx);
    let r=economics::route_primary(if(native_route)economics::primary_quote(&version.primary.destroy_some(),cfg,0,false,version.beneficiary,id,hash,ctx.sender(),attempt,expiry) else economics::manufacturing_primary_quote(&version.primary.destroy_some(),cfg,0,false,version.beneficiary,id,hash,ctx.sender(),attempt,expiry),id);
    p.payments.add(RequestKey{actor:ctx.sender(),kind:1,attempt},r);issue_access(p,v,r,clock,ctx);event::emit(AccessPurchased{product:id,buyer:ctx.sender(),version:v,attempt})
}
public fun access_record<C>(p:&Product<C>,version:u64,holder:address):Option<Access>{let k=AccessKey{wallet:holder,version};if(p.access.contains(k))option::some(*p.access.borrow(k)) else option::none()}
public fun access_product(a:&Access):ID{a.product}
public fun access_version(a:&Access):u64{a.version}
public fun access_policy_hash(a:&Access):vector<u8>{a.policy_hash}
public fun access_manifest(a:&Access):vector<u8>{a.manifest}
public fun access_holder(a:&Access):address{a.holder}
public fun access_paid(a:&Access):u64{a.paid}
public fun access_issued_at(a:&Access):u64{a.issued_at_ms}
public fun income<C>(p:&Product<C>):&Ledger<C>{&p.income}
public fun deposit_income<C>(p:&mut Product<C>,cfg:&Config<C>,payment:Coin<C>){assert!(p.protocol==object::id(cfg),EPolicy);assert_active(p);economics::assert_operation(cfg);assert!(sui::coin::value(&payment)>0,EPolicy);revenue::deposit(&p.id,&mut p.income,payment)}
/// Only a mutable current Control grants withdrawal. No cached creator/owner
/// address can grant it; public Control transfer naturally transfers this right.
public fun withdraw_income<C>(p:&mut Product<C>,control:&mut Control,expected:u64,amount:u64,recipient:address,attempt:vector<u8>,ctx:&mut TxContext){
    assert_control(p,control);revenue::withdraw(&p.id,&mut p.income,expected,amount,recipient,attempt,ctx)
}
public fun payment_receipt<C>(p:&Product<C>,actor:address,kind:u8,attempt:vector<u8>):Option<PrimaryReceipt>{let k=RequestKey{actor,kind,attempt};if(p.payments.contains(k))option::some(*p.payments.borrow(k)) else option::none()}
public fun completion_price<C>(p:&Product<C>,v:u64,wallet:address):u64 {
    let version=published(p,v);let count=wallet_completes(p,v,wallet);
    if (version.completion_mode == 0) { 0 } else if (version.completion_mode == 1) { version.completion_price } else if (count < version.quota) { 0 } else { assert!(version.completion_mode == 2, ECap); version.completion_price }
}
public fun wallet_completes<C>(p:&Product<C>,v:u64,wallet:address):u64 {
    let key=CountKey{version:v,wallet};if(p.completes.contains(key))*p.completes.borrow(key) else 0
}
public(package) fun authorize_complete<C>(p:&mut Product<C>,v:u64,hash:vector<u8>,attempt:vector<u8>,soul:ID,ctx:&TxContext):u64 {
    assert!(p.lifecycle==1,ELifecycle);let version=published(p,v);assert!(version.policy_hash==hash,EPolicy);
    let price=completion_price(p,v,ctx.sender());let all=wallet_completes(p,v,@0x0);
    assert!(version.cap==0 || all < version.cap,ECap);
    record_attempt(p,2,attempt,soul,ctx);increment_count(p,CountKey{version:v,wallet:@0x0});
    // @0x0 is reserved for aggregate counts and cannot be a transaction sender.
    increment_count(p,CountKey{version:v,wallet:ctx.sender()});price
}
fun increment_count<C>(p:&mut Product<C>,key:CountKey) {
    if(p.completes.contains(key))*p.completes.borrow_mut(key)=*p.completes.borrow(key)+1 else p.completes.add(key,1)
}
fun issue_internal<C,T:key>(p:&mut Product<C>,v:u64,definition_hash:vector<u8>,target:&T):soulidity_model::components::Permit {
    // End the immutable borrow before supply mutation; copy only the selected
    // Definition and small settlement terms, never the complete publication.
    let (d,royalty_bps,beneficiary,market,primary)={
        let version=published(p,v);
        (*published_definition(&version.definitions,&definition_hash),version.royalty_bps,version.beneficiary,version.market,version.primary)
    };
    let supply_key=policy::hash_bytes(bcs::to_bytes(&SupplyKey{version:v,definition:definition_hash}));
    let issued=if(p.issued.contains(supply_key))*p.issued.borrow(supply_key) else 0;
    assert!(issued < policy::supply(&d),ECap);
    if(p.issued.contains(supply_key))*p.issued.borrow_mut(supply_key)=issued+1 else p.issued.add(supply_key,issued+1);
    let maker=if(p.maker.is_some())*p.maker.borrow() else object::id(p);
    let maker_version=if(p.maker.is_some())p.parent_version else v;
    let source=policy::source(PolicyProducer{},p,maker,maker_version,v,p.protocol,royalty_bps,beneficiary,market.destroy_some(),primary.destroy_some(),d);
    soulidity_model::components::authorize(ComponentProducer{},p,target,source)
}
public fun issued_count<C>(p:&Product<C>,v:u64,definition_hash:vector<u8>):u64{
    let _=preview_source(p,v,definition_hash);let key=policy::hash_bytes(bcs::to_bytes(&SupplyKey{version:v,definition:definition_hash}));if(p.issued.contains(key))*p.issued.borrow(key) else 0
}
public fun receipt<C>(p:&Product<C>,actor:address,kind:u8,attempt:vector<u8>):Option<ID> {
    let key=RequestKey{actor,kind,attempt};if(p.attempts.contains(key))option::some(*p.attempts.borrow(key)) else option::none()
}
public(package) fun record_attempt<C>(p:&mut Product<C>,kind:u8,attempt:vector<u8>,result:ID,ctx:&TxContext) {
    policy::assert_hash(&attempt);let key=RequestKey{actor:ctx.sender(),kind,attempt};assert!(!p.attempts.contains(key),EAttempt);p.attempts.add(key,result)
}

/// Draft-only constructors: publishing freezes the complete policy commitment.
public fun with_outputs(mut v:Version,outputs:vector<Policy>):Version {
    let invalid=publication_rules::validate_outputs(&outputs);assert!(invalid==0,invalid);v.outputs=outputs;v.policy_hash=vector[];v.policy_hash=policy::hash_bytes(bcs::to_bytes(&v));v
}
public fun with_pack_key(mut v:Version,key:vector<u8>):Version {
    policy::assert_key(&key);v.pack_key=key;v.policy_hash=vector[];v.policy_hash=policy::hash_bytes(bcs::to_bytes(&v));v
}
public fun output_policy(v:&Version,key:vector<u8>):Policy {
    let mut found=option::none();v.outputs.do_ref!(|p|{if(output::policy_key(p)==key)found=option::some(*p)});assert!(found.is_some(),EPolicy);found.destroy_some()
}
public fun pack_key(v:&Version):vector<u8>{v.pack_key}
public fun physical_terms(v:&Version):vector<Terms>{v.physical}
public fun with_physical(mut v:Version,terms:vector<Terms>):Version {
    let invalid=publication_rules::validate_physical(&v.definitions,&terms);assert!(invalid==0,invalid);v.physical=terms;v.policy_hash=vector[];v.policy_hash=policy::hash_bytes(bcs::to_bytes(&v));v
}
// The previous forward scan overwrote every match. Search backwards and stop
// at that same last match; no metadata/supply/producer validation is cached.
fun published_definition(definitions:&vector<Definition>,hash:&vector<u8>):&Definition {
    let mut i=definitions.length();
    while(i>0){
        i=i-1;let d=&definitions[i];
        if(policy::definition_hash(d)==*hash)return d
    };
    abort EDefinition
}
/// Read-only provenance preview does not issue supply or an Item object.
public fun preview_source<C>(p:&Product<C>,v:u64,definition_hash:vector<u8>):Source {
    let version=published(p,v);let d=*published_definition(&version.definitions,&definition_hash);let maker=if(p.maker.is_some())*p.maker.borrow() else object::id(p);let maker_version=if(p.maker.is_some())p.parent_version else v;
    policy::source(PolicyProducer{},p,maker,maker_version,v,p.protocol,version.royalty_bps,version.beneficiary,version.market.destroy_some(),version.primary.destroy_some(),d)
}

public fun register<C>(cfg:&mut soulidity_foundation::economics::Config<C>,admin:&mut soulidity_foundation::economics::Admin,expected:u64,hash:vector<u8>,publisher:&sui::package::Publisher,cap:&sui::package::UpgradeCap){
    economics::register_role<C,CreatorAuthority1,CreatorRevision3>(cfg,admin,expected,hash,2,CreatorAuthority1{},CreatorRevision3{},publisher,cap)
}
public(package) fun attest_role(p:&sui::package::Publisher,cap:&sui::package::UpgradeCap,ctx:&mut TxContext):ID{soulidity_foundation::package_roles::attest_role(2,CreatorAuthority1{},CreatorRevision3{},p,cap,ctx)}
#[test_only]
public fun publisher_for_testing(ctx:&mut TxContext):sui::package::Publisher{sui::package::test_claim(MAKER_CATALOG{},ctx)}
#[test_only]
public fun select_certificate_state_for_testing(state:&mut soulidity_foundation::package_roles::State,certificate:&soulidity_foundation::package_roles::RoleCertificate<CreatorAuthority1,CreatorRevision3>){soulidity_foundation::package_roles::register_from_certificate(state,2,CreatorAuthority1{},CreatorRevision3{},certificate)}
public fun register_from_certificate<C>(cfg:&mut Config<C>,admin:&mut economics::Admin,expected:u64,hash:vector<u8>,certificate:&soulidity_foundation::package_roles::RoleCertificate<CreatorAuthority1,CreatorRevision3>){economics::register_role_from_certificate(cfg,admin,expected,hash,2,CreatorAuthority1{},CreatorRevision3{},certificate)}
public(package) fun new_service<C,WR:drop,RR:drop>(release:&soulidity_foundation::package_roles::RoleCertificate<WR,RR>,creator:&soulidity_foundation::package_roles::RoleCertificate<CreatorAuthority1,CreatorRevision3>,wr:WR,rr:RR,primary:u16,secondary:u16,fixed:u64,recipient:address,ctx:&mut TxContext):(Config<C>,economics::Admin){economics::new_manufacturing_instance(release,creator,wr,rr,CreatorAuthority1{},CreatorRevision3{},primary,secondary,fixed,recipient,ctx)}

#[test_only]
public fun settle_quote_for_testing<C>(cfg:&mut Config<C>,receipt:PrimaryReceipt,payment:sui::coin::Coin<C>,clock:&Clock,ctx:&mut TxContext):sui::coin::Coin<C>{economics::collect_manufacturing_primary<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{},receipt,payment,clock,ctx)}

/// Native admission proof is returned only after quota reservation and actual Coin
/// settlement; copyable PrimaryReceipt alone never grants an application action.


#[test_only]
public fun create_pack_for_testing<C>(maker:&Product<C>,parent_version:u64,control:&mut Control,cfg:&Config<C>,control_royalty_bps:u16,ctx:&mut TxContext):ID { soulidity_maker_manufacturing::maker_catalog::create_pack(maker,parent_version,control,cfg,control_royalty_bps,ctx) }

#[test_only]
public fun publish_for_testing<C>(p:&mut Product<C>,control:&mut Control,expected_version:u64,mut v:Version):vector<u8> { soulidity_maker_manufacturing::maker_catalog::publish(p,control,expected_version,v) }

#[test_only]
public fun assert_publication_economics_for_testing<C>(p:&Product<C>,v:&Version){ soulidity_maker_manufacturing::maker_catalog::assert_publication_economics(p,v) }

#[test_only]
public fun lifecycle_for_testing<C>(p:&mut Product<C>,control:&mut Control,expected:u64,state:u8) { soulidity_maker_manufacturing::maker_catalog::lifecycle(p,control,expected,state) }

#[test_only]
public fun attach_certification_for_testing<C,T:key+store>(p:&mut Product<C>,version:u64,value:T){ soulidity_maker_manufacturing::maker_catalog::attach_certification(p,version,value) }

#[test_only]
public fun certification_for_testing<C,T:key+store>(p:&Product<C>,version:u64):&T{ soulidity_maker_manufacturing::maker_catalog::certification(p,version) }

#[test_only]
public fun certification_mut_for_testing<C,T:key+store>(p:&mut Product<C>,version:u64):&mut T{ soulidity_maker_manufacturing::maker_catalog::certification_mut(p,version) }

#[test_only]
public fun bind_physical_for_testing<C>(p:&mut Product<C>,version:u64,registry:ID){ soulidity_maker_manufacturing::maker_catalog::bind_physical(p,version,registry) }

#[test_only]
public fun assert_unpublished_for_testing(v:&Version){ soulidity_maker_manufacturing::maker_catalog::assert_unpublished(v) }

#[test_only]
public fun append_definitions_for_testing(v:&mut Version,extra:vector<Definition>){ soulidity_maker_manufacturing::maker_catalog::append_definitions(v,extra) }

#[test_only]
public fun extend_definition_for_testing(v:&mut Version,index:u64,extra:vector<visual::Fragment>){ soulidity_maker_manufacturing::maker_catalog::extend_definition(v,index,extra) }

#[test_only]
public fun append_adapters_for_testing(v:&mut Version,extra:vector<Adapter>){ soulidity_maker_manufacturing::maker_catalog::append_adapters(v,extra) }

#[test_only]
public fun append_physical_for_testing(v:&mut Version,extra:vector<Terms>){ soulidity_maker_manufacturing::maker_catalog::append_physical(v,extra) }

#[test_only]
public fun finalize_metadata_for_testing(v:&Version):Version{ soulidity_maker_manufacturing::maker_catalog::finalize_metadata(v) }

#[test_only]
public fun unpublished_hash_for_testing(v:&Version):vector<u8>{ soulidity_maker_manufacturing::maker_catalog::unpublished_hash(v) }

#[test_only]
public fun ensure_access_for_testing<C>(p:&mut Product<C>,cfg:&Config<C>,v:u64,attempt:vector<u8>,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&mut TxContext){ soulidity_maker_manufacturing::maker_catalog::ensure_access(p,cfg,v,attempt,fee_revision,expiry,clock,ctx) }

#[test_only]
public fun buy_access_for_testing<C>(p:&mut Product<C>,cfg:&mut Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) { soulidity_maker_manufacturing::maker_catalog::buy_access(p,cfg,v,hash,fee_revision,expiry,attempt,payment,clock,ctx) }

#[test_only]
public fun collect_primary_for_testing<C>(p:&mut Product<C>,cfg:&mut Config<C>,r:PrimaryReceipt,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext){ soulidity_maker_manufacturing::maker_catalog::collect_primary(p,cfg,r,payment,clock,ctx) }

#[test_only]
public fun claim_access_for_testing<C>(p:&mut Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext){ soulidity_maker_manufacturing::maker_catalog::claim_access(p,cfg,v,hash,fee_revision,expiry,attempt,clock,ctx) }

#[test_only]
public fun authorize_complete_for_testing<C>(p:&mut Product<C>,v:u64,hash:vector<u8>,attempt:vector<u8>,soul:ID,ctx:&TxContext):u64 { soulidity_maker_manufacturing::maker_catalog::authorize_complete(p,v,hash,attempt,soul,ctx) }

#[test_only]
public fun issue_internal_for_testing<C,T:key>(p:&mut Product<C>,v:u64,definition_hash:vector<u8>,target:&T):soulidity_model::components::Permit { soulidity_maker_manufacturing::maker_catalog::issue_internal(p,v,definition_hash,target) }

#[test_only]
public fun record_attempt_for_testing<C>(p:&mut Product<C>,kind:u8,attempt:vector<u8>,result:ID,ctx:&TxContext) { soulidity_maker_manufacturing::maker_catalog::record_attempt(p,kind,attempt,result,ctx) }

public fun assert_current_writer<C>(cfg:&Config<C>){economics::assert_role_types<C,CreatorAuthority1,CreatorRevision3>(cfg,2)}
public(package) fun authorize_activation<C>(cfg:&Config<C>,admin:&mut economics::Admin,expected:u64,hash:vector<u8>):economics::ManufacturingActivation{economics::authorize_manufacturing_activation(cfg,admin,expected,hash,CreatorAuthority1{},CreatorRevision3{})}

public fun assert_runtime_access_native<C,A:drop,R:drop,T:key>(p:&Product<C>,cfg:&Config<C>,v:u64,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext,a:A,r:R){ assert_current_writer(cfg);assert_adapter<A,R,T>(published(p,v),a,r);assert_runtime_access_with_current_writer(p,cfg,v,expected_policy,expected_manifest,expected_config_revision,expected_config_commitment,clock,ctx,true) }

public fun assert_runtime_pack_native<C,A:drop,R:drop,T:key>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,cfg:&Config<C>,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext,a:A,r:R){ assert_current_writer(cfg);assert_adapter<A,R,T>(published(p,version),a,r);assert_runtime_pack_with_current_writer(p,maker,maker_version,version,cfg,expected_policy,expected_manifest,expected_config_revision,expected_config_commitment,clock,ctx,true) }

public(package) fun buy_access_native<C,A:drop,R:drop,T:key>(p:&mut Product<C>,cfg:&mut Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext,a:A,r:R) { assert_current_writer(cfg);assert_adapter<A,R,T>(published(p,v),a,r);buy_access_value(p,cfg,v,hash,fee_revision,expiry,attempt,payment,clock,ctx,true) }

public(package) fun claim_access_native<C,A:drop,R:drop,T:key>(p:&mut Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext,a:A,r:R){ assert_current_writer(cfg);assert_adapter<A,R,T>(published(p,v),a,r);claim_access_value(p,cfg,v,hash,fee_revision,expiry,attempt,clock,ctx,true) }

public(package) fun collect_primary_native<C,A:drop,R:drop,T:key>(p:&mut Product<C>,cfg:&mut Config<C>,r:PrimaryReceipt,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext,a:A,revision:R){ assert_current_writer(cfg);assert_adapter_types<A,R,T>(&published(p,1).execution.destroy_some());let _=a;let _=revision;collect_primary_value(p,cfg,r,payment,clock,ctx,true) }

public(package) fun create_pack_native<C,A:drop,R:drop,T:key>(maker:&Product<C>,parent_version:u64,control:&mut Control,cfg:&Config<C>,control_royalty_bps:u16,ctx:&mut TxContext,a:A,r:R):ID { assert_current_writer(cfg);assert_adapter<A,R,T>(published(maker,parent_version),a,r);create_pack_value(maker,parent_version,control,cfg,control_royalty_bps,ctx,true) }

public(package) fun ensure_access_native<C,A:drop,R:drop,T:key>(p:&mut Product<C>,cfg:&Config<C>,v:u64,attempt:vector<u8>,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&mut TxContext,a:A,r:R){ assert_current_writer(cfg);assert_adapter<A,R,T>(published(p,v),a,r);ensure_access_value(p,cfg,v,attempt,fee_revision,expiry,clock,ctx,true) }

public fun create_native_maker<C>(cfg:&Config<C>,bps:u16,ctx:&mut TxContext):ID{economics::assert_business<C,CreatorAuthority1,CreatorRevision3>(cfg,2,CreatorAuthority1{},CreatorRevision3{});create(cfg,economics::market_policy(cfg,bps,ctx),bps,economics::primary_policy(cfg),option::none(),0,option::none(),ctx)}
public fun with_execution<A:drop,R:drop,T:key>(mut v:Version,_a:A,_r:R):Version{assert_unpublished(&v);let a=type_name::with_original_ids<A>();let r=type_name::with_original_ids<R>();assert!(!a.is_primitive() && !r.is_primitive() && a.address_string()==r.address_string() && a.module_string()==r.module_string(),EPolicy);v.execution=option::some(Execution{adapter:type_name::with_defining_ids<A>(),revision:type_name::with_defining_ids<R>(),target:type_name::with_defining_ids<T>()});v.policy_hash=vector[];v.policy_hash=policy::hash_bytes(bcs::to_bytes(&v));v}
fun assert_adapter_types<A,R,T>(route:&Execution){assert!(route.adapter==type_name::with_defining_ids<A>() && route.revision==type_name::with_defining_ids<R>() && route.target==type_name::with_defining_ids<T>(),EPolicy)}
fun assert_adapter<A:drop,R:drop,T:key>(v:&Version,_a:A,_r:R){assert!(v.execution.is_some(),EPolicy);assert_adapter_types<A,R,T>(v.execution.borrow())}
/// Request alone carries provenance. Funding and owned-only delivery are separate.
public(package) fun request_origin<C,A:drop,R:drop,T:key>(p:&Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,name:String,attempt:vector<u8>,expiry:u64,a:A,r:R,clock:&Clock,ctx:&TxContext):OriginRequest{
 assert_current_writer(cfg);economics::assert_manufacturing_live(cfg,economics::revision(cfg),expiry,clock);let version=published(p,v);assert!(p.maker.is_none() && p.protocol==object::id(cfg) && version.policy_hash==hash,EPolicy);assert_access(p,v,ctx.sender());assert_adapter_types<A,R,T>(version.execution.borrow());
 origin::request<SoulProducer,Product<C>,A,R,T>(SoulProducer{},p,a,r,v,hash,name,attempt,object::id(cfg),economics::revision(cfg),economics::commitment(cfg),expiry,0,ctx)
}
public fun request_native_origin<C,A:drop,R:drop,T:key>(p:&Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,name:String,attempt:vector<u8>,expiry:u64,a:A,r:R,clock:&Clock,ctx:&TxContext):OriginRequest{
 assert_current_writer(cfg);economics::assert_primary_live(cfg,economics::revision(cfg),expiry,clock);let version=published(p,v);assert!(p.maker.is_none() && p.protocol==object::id(cfg) && version.policy_hash==hash,EPolicy);assert_access(p,v,ctx.sender());assert_adapter_types<A,R,T>(version.execution.borrow());
 origin::request<SoulProducer,Product<C>,A,R,T>(SoulProducer{},p,a,r,v,hash,name,attempt,object::id(cfg),economics::revision(cfg),economics::commitment(cfg),expiry,0,ctx)
}
/// Only the certificate-owning release module creates this through package scope.
/// Snapshot/quotes remain passive; this one-use guard is consumed by funding.
public struct Availability {snapshot:Snapshot,target:ID,value:AvailabilitySnapshot}
public struct AvailabilitySnapshot has copy,drop {system:ID,epoch:u32,end_epoch:u32,catalog:ID,catalog_hash:vector<u8>,certificate:ID,certificate_hash:vector<u8>,blobs:vector<u8>}
public(package) fun availability<C,T:key>(p:&Product<C>,target:&T,cfg:&Config<C>,snapshot:Snapshot,system:ID,epoch:u32,end_epoch:u32,catalog:ID,catalog_hash:vector<u8>,certificate:ID,certificate_hash:vector<u8>,blobs:vector<u8>):Availability{assert!(origin::source(&snapshot)==object::id(p) && origin::config(&snapshot)==object::id(cfg) && origin::revision(&snapshot)==economics::revision(cfg) && origin::commitment(&snapshot)==economics::commitment(cfg) && origin::policy(&snapshot)==policy_hash(published(p,origin::version(&snapshot))) && end_epoch>epoch && catalog_hash.length()==32 && certificate_hash.length()==32 && blobs.length()==32,EPolicy);Availability{snapshot,target:object::id(target),value:AvailabilitySnapshot{system,epoch,end_epoch,catalog,catalog_hash,certificate,certificate_hash,blobs}}}
fun consume_availability(guard:Availability,snapshot:&Snapshot,target:ID):AvailabilitySnapshot{let Availability{snapshot:bound,target:id,value}=guard;assert!(bound==*snapshot && id==target,EPolicy);value}
fun assert_availability(s:&Session,system:&System){assert!(s.availability.is_some(),EPolicy);let a=s.availability.borrow();assert!(a.system==object::id(system) && a.epoch==walrus_system::epoch(system) && walrus_system::epoch(system)<a.end_epoch,EPolicy)}
public struct Session {availability:Option<AvailabilitySnapshot>,snapshot:Snapshot,target:ID,receipt:PrimaryReceipt,used:u64,action_taken:bool,native_route:bool,require_used:bool,completion:CompletionAuthorization}
public struct SelectionAction {snapshot:Snapshot,target:ID,definition:vector<u8>}
/// Exact paid/quota/replay authority, linear and confined to this transaction.
public(package) fun begin_session<C,A:drop,R:drop,T:key>(p:&mut Product<C>,target:&T,cfg:&mut Config<C>,snapshot:Snapshot,payment:Coin<C>,a:A,r:R,clock:&Clock,ctx:&mut TxContext,guard:Availability):Session{begin_session_value(p,target,cfg,snapshot,payment,a,r,clock,ctx,false,false,option::some(consume_availability(guard,&snapshot,object::id(target))))}
public(package) fun begin_native_session<C,A:drop,R:drop,T:key>(p:&mut Product<C>,target:&T,cfg:&mut Config<C>,snapshot:Snapshot,payment:Coin<C>,a:A,r:R,clock:&Clock,ctx:&mut TxContext,guard:Availability):Session{begin_session_value(p,target,cfg,snapshot,payment,a,r,clock,ctx,true,false,option::some(consume_availability(guard,&snapshot,object::id(target))))}
fun begin_session_value<C,A:drop,R:drop,T:key>(p:&mut Product<C>,target:&T,cfg:&mut Config<C>,snapshot:Snapshot,payment:Coin<C>,a:A,r:R,clock:&Clock,ctx:&mut TxContext,native_route:bool,pack_proof:bool,availability:Option<AvailabilitySnapshot>):Session{
 // Only private begin_pack_session_value sets pack_proof after the exact role/Config snapshot check.
 // Config is unchanged between that check and this continuation. Public session starts still validate writer independently.
 if(!pack_proof)assert_current_writer(cfg);assert!(origin::operation(&snapshot)<=1 && origin::producer(&snapshot)==type_name::with_defining_ids<SoulProducer>(),EPolicy);let fixed=origin::operation(&snapshot)==0;assert!(!fixed || p.maker.is_none(),EParent);let require_used=p.maker.is_some();let v=origin::version(&snapshot);let hash=origin::policy(&snapshot);let version=published(p,v);if(version.access_mode==2)assert!(pack_proof && origin::operation(&snapshot)==1,EAccess) else assert_access_published(p,v,version,ctx.sender());assert_adapter<A,R,T>(version,a,r);origin::assert_adapter<A,R,T>(&snapshot,target,ctx);
 assert!(origin::source(&snapshot)==object::id(p) && origin::source_type(&snapshot)==type_name::with_defining_ids<Product<C>>() && origin::config(&snapshot)==object::id(cfg) && origin::revision(&snapshot)==economics::revision(cfg) && origin::commitment(&snapshot)==economics::commitment(cfg) && p.protocol==object::id(cfg) && version.policy_hash==hash,EPolicy);
 if(native_route)economics::assert_primary_live(cfg,origin::revision(&snapshot),origin::expiry(&snapshot),clock) else economics::assert_manufacturing_live(cfg,origin::revision(&snapshot),origin::expiry(&snapshot),clock);
 assert_publication_economics(p,version);let price=authorize_complete(p,v,hash,origin::attempt(&snapshot),object::id(target),ctx);
 // Source/Config equality was checked above; authorize_complete changes only
 // attempts/counts. Route this actual Product and immediately deposit its net Coin.
 let version=published(p,v);let(receipt,net)=if(native_route)economics::quote_collect_primary<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{},&version.primary.destroy_some(),price,fixed,version.beneficiary,object::id(target),hash,ctx.sender(),origin::attempt(&snapshot),origin::expiry(&snapshot),object::id(p),payment,clock,ctx) else economics::quote_collect_manufacturing_primary<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{},&version.primary.destroy_some(),price,fixed,version.beneficiary,object::id(target),hash,ctx.sender(),origin::attempt(&snapshot),origin::expiry(&snapshot),object::id(p),payment,clock,ctx);
 revenue::deposit(&p.id,&mut p.income,net);let completion=origin::complete(SoulProducer{},p,target,snapshot,ctx);Session{availability,snapshot,target:object::id(target),receipt,used:0,action_taken:false,native_route,require_used,completion}
}
public fun session_receipt(s:&Session):PrimaryReceipt{s.receipt}
public fun session_snapshot(s:&Session):Snapshot{s.snapshot}
public fun take_action<C,T:key>(s:&mut Session,p:&Product<C>,target:&T,ctx:&TxContext):PaidAction{assert_session(s,p,target,ctx);assert!(!s.action_taken,EPolicy);s.action_taken=true;origin::authorize_action(ManufacturingProducer{},p,target,s.snapshot,policy::hash_bytes(bcs::to_bytes(&s.receipt)),ctx)}
fun assert_session<C,T:key>(s:&Session,p:&Product<C>,target:&T,ctx:&TxContext){assert!(s.target==object::id(target) && origin::source(&s.snapshot)==object::id(p) && origin::source_type(&s.snapshot)==type_name::with_defining_ids<Product<C>>() && origin::actor(&s.snapshot)==ctx.sender() && published(p,origin::version(&s.snapshot)).policy_hash==origin::policy(&s.snapshot),EPolicy)}
public fun select<C,T:key>(s:&mut Session,p:&mut Product<C>,target:&T,definition:vector<u8>,ctx:&TxContext):(soulidity_model::components::Permit,SelectionAction){assert_session(s,p,target,ctx);let permit=issue_internal(p,origin::version(&s.snapshot),definition,target);(permit,SelectionAction{snapshot:s.snapshot,target:s.target,definition})}
public fun selected<A:drop,R:drop,T:key>(s:&mut Session,selection:SelectionAction,target:&T,_a:A,_r:R,ctx:&TxContext){let SelectionAction{snapshot,target:id,definition:_}=selection;assert!(snapshot==s.snapshot && id==s.target && id==object::id(target),EPolicy);origin::assert_adapter<A,R,T>(&snapshot,target,ctx);s.used=s.used+1}
/// Adapter attests final target behavior; this token requests Standard delivery,
/// and never claims that a transfer has already happened.
public fun finish_session<C,A:drop,R:drop,T:key>(s:Session,target:&T,cfg:&Config<C>,_a:A,_r:R,system:&System,clock:&Clock,ctx:&TxContext):CompletionAuthorization{assert_current_writer(cfg);assert_availability(&s,system);if(s.native_route)economics::assert_primary_live(cfg,origin::revision(&s.snapshot),origin::expiry(&s.snapshot),clock) else economics::assert_manufacturing_live(cfg,origin::revision(&s.snapshot),origin::expiry(&s.snapshot),clock);assert!(origin::config(&s.snapshot)==object::id(cfg) && origin::commitment(&s.snapshot)==economics::commitment(cfg),EPolicy);finish_session_value<A,R,T>(s,target,ctx)}
fun finish_session_value<A,R,T:key>(s:Session,target:&T,ctx:&TxContext):CompletionAuthorization{assert!(s.target==object::id(target) && origin::actor(&s.snapshot)==ctx.sender(),EPolicy);origin::assert_adapter<A,R,T>(&s.snapshot,target,ctx);assert!(!s.require_used || s.used>0,EPolicy);let Session{availability:_,snapshot:_,target:_,receipt:_,used:_,action_taken:_,native_route:_,require_used:_,completion}=s;completion}
#[test_only]
public fun finish_session_for_testing<A:drop,R:drop,T:key>(s:Session,target:&T,_a:A,_r:R,ctx:&TxContext):CompletionAuthorization{assert!(s.target==object::id(target) && origin::actor(&s.snapshot)==ctx.sender(),EPolicy);origin::assert_adapter<A,R,T>(&s.snapshot,target,ctx);let Session{availability:_,snapshot:_,target:_,receipt:_,used:_,action_taken:_,native_route:_,require_used:_,completion}=s;completion}

#[test_only]
public fun issue_for_testing<C,T:key>(p:&mut Product<C>,v:u64,hash:vector<u8>,target:&T):soulidity_model::components::Permit{issue_internal(p,v,hash,target)}

public fun request_native_contribution<C,A:drop,R:drop,T:key>(p:&Product<C>,target:&T,cfg:&Config<C>,v:u64,hash:vector<u8>,name:String,attempt:vector<u8>,expiry:u64,a:A,r:R,clock:&Clock,ctx:&TxContext):Snapshot{economics::assert_role_primary_live<C,CreatorAuthority1,CreatorRevision3>(cfg,2,economics::revision(cfg),expiry,clock);let version=published(p,v);assert!(p.protocol==object::id(cfg) && version.policy_hash==hash,EPolicy);assert_adapter_types<A,R,T>(version.execution.borrow());let request=origin::request<SoulProducer,Product<C>,A,R,T>(SoulProducer{},p,a,r,v,hash,name,attempt,object::id(cfg),economics::revision(cfg),economics::commitment(cfg),expiry,1,ctx);let snapshot=origin::consume_request<T>(request,ctx);origin::assert_adapter<A,R,T>(&snapshot,target,ctx);snapshot}
public(package) fun request_contribution<C,A:drop,R:drop,T:key>(p:&Product<C>,target:&T,cfg:&Config<C>,v:u64,hash:vector<u8>,name:String,attempt:vector<u8>,expiry:u64,a:A,r:R,clock:&Clock,ctx:&TxContext):Snapshot{assert_current_writer(cfg);economics::assert_manufacturing_live(cfg,economics::revision(cfg),expiry,clock);let version=published(p,v);assert!(p.protocol==object::id(cfg) && version.policy_hash==hash,EPolicy);assert_adapter_types<A,R,T>(version.execution.borrow());let request=origin::request<SoulProducer,Product<C>,A,R,T>(SoulProducer{},p,a,r,v,hash,name,attempt,object::id(cfg),economics::revision(cfg),economics::commitment(cfg),expiry,1,ctx);let snapshot=origin::consume_request<T>(request,ctx);origin::assert_adapter<A,R,T>(&snapshot,target,ctx);snapshot}

public fun access_quote_native<C>(p:&Product<C>,cfg:&Config<C>,version:u64,actor:address,attempt:vector<u8>,expiry:u64):PrimaryReceipt {let v=published(p,version);assert!(v.access_mode==1,EPolicy);economics::route_primary(economics::primary_quote(&v.primary.destroy_some(),cfg,v.access_price,false,v.beneficiary,object::id(p),v.policy_hash,actor,attempt,expiry),object::id(p))}

public fun assert_execution<A:drop,R:drop,T:key>(v:&Version,a:A,r:R){assert_adapter<A,R,T>(v,a,r)}

public fun with_physical_route<W:drop,R:drop>(mut v:Version,_w:W,_r:R):Version{assert_unpublished(&v);assert_physical_names<W,R>();v.physical_execution=option::some(PhysicalExecution{producer:type_name::with_defining_ids<W>(),revision:type_name::with_defining_ids<R>()});v.policy_hash=vector[];v.policy_hash=policy::hash_bytes(bcs::to_bytes(&v));v}
fun assert_physical_names<W,R>(){let w=type_name::with_original_ids<W>();let r=type_name::with_original_ids<R>();assert!(!w.is_primitive() && !r.is_primitive() && w.address_string()==r.address_string() && w.module_string()==r.module_string() && *w.datatype_string().as_bytes()==b"PhysicalProducer",EPolicy)}
fun assert_physical_route<C,W,R,T:key>(p:&Product<C>,v:u64,registry:&T){assert_physical_names<W,R>();let w=type_name::with_original_ids<W>();let t=type_name::with_original_ids<T>();assert!(!t.is_primitive() && w.address_string()==t.address_string() && w.module_string()==t.module_string(),EPolicy);let route=published(p,v).physical_execution.borrow();assert!(route.producer==type_name::with_defining_ids<W>() && route.revision==type_name::with_defining_ids<R>(),EPolicy);let _=registry;}
public(package) fun bind_physical_registry<C,W:drop,R:drop,T:key>(p:&mut Product<C>,control:&mut Control,v:u64,registry:&T,cfg:&Config<C>,_w:W,_r:R){economics::assert_business<C,CreatorAuthority1,CreatorRevision3>(cfg,2,CreatorAuthority1{},CreatorRevision3{});bind_physical_registry_value<C,W,R,T>(p,control,v,registry,cfg)}
public(package) fun bind_manufacturing_physical_registry<C,W:drop,R:drop,T:key>(p:&mut Product<C>,control:&mut Control,v:u64,registry:&T,cfg:&Config<C>,_w:W,_r:R){economics::assert_manufacturing_business<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{});bind_physical_registry_value<C,W,R,T>(p,control,v,registry,cfg)}
fun bind_physical_registry_value<C,W,R,T:key>(p:&mut Product<C>,control:&mut Control,v:u64,registry:&T,cfg:&Config<C>){assert!(p.protocol==object::id(cfg),EPolicy);assert_control(p,control);assert_physical_route<C,W,R,T>(p,v,registry);assert!(p.maker.is_none() && !p.physical_registries.contains(v),EParent);p.physical_registries.add(v,object::id(registry))}
public struct PhysicalSettlement {product:ID,registry:ID,registry_type:TypeName,producer:TypeName,revision:TypeName,version:u64,actor:address,receipt:PrimaryReceipt}
/// Separate Rule-material supply remains in the actual private Physical producer.
/// Coin settlement uses this sole Product income implementation and no OC counter.
public(package) fun settle_physical<C,W:drop,R:drop,T:key>(p:&mut Product<C>,registry:&T,v:u64,cfg:&mut Config<C>,receipt:PrimaryReceipt,payment:Coin<C>,_w:W,_r:R,clock:&Clock,ctx:&mut TxContext):PhysicalSettlement{let _=_w;let _=_r;settle_physical_value<C,W,R,T>(p,registry,v,cfg,receipt,payment,clock,ctx,true)}
public(package) fun settle_manufacturing_physical<C,W:drop,R:drop,T:key>(p:&mut Product<C>,registry:&T,v:u64,cfg:&mut Config<C>,receipt:PrimaryReceipt,payment:Coin<C>,_w:W,_r:R,clock:&Clock,ctx:&mut TxContext):PhysicalSettlement{let _=_w;let _=_r;settle_physical_value<C,W,R,T>(p,registry,v,cfg,receipt,payment,clock,ctx,false)}
fun settle_physical_value<C,W,R,T:key>(p:&mut Product<C>,registry:&T,v:u64,cfg:&mut Config<C>,receipt:PrimaryReceipt,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext,native_route:bool):PhysicalSettlement{assert_current_writer(cfg);assert_physical_route<C,W,R,T>(p,v,registry);if(p.maker.is_none())assert!(physical_registry(p,v)==option::some(object::id(registry)),EParent);assert!(economics::primary_receipt_subject(&receipt)==object::id(registry) && economics::primary_receipt_actor(&receipt)==ctx.sender() && economics::primary_receipt_revenue(&receipt)==option::some(object::id(p)),EPolicy);let primary=published(p,v).primary.destroy_some();assert!(economics::primary_policy_hash(&primary)==economics::primary_policy_hash(&economics::primary_receipt_policy(&receipt)),EPolicy);collect_primary_value(p,cfg,receipt,payment,clock,ctx,native_route);PhysicalSettlement{product:object::id(p),registry:object::id(registry),registry_type:type_name::with_defining_ids<T>(),producer:type_name::with_defining_ids<W>(),revision:type_name::with_defining_ids<R>(),version:v,actor:ctx.sender(),receipt}}
public fun consume_physical_settlement<W:drop,R:drop,T:key>(settlement:PhysicalSettlement,registry:&T,_w:W,_r:R,product:ID,version:u64,ctx:&TxContext):PrimaryReceipt{assert_physical_names<W,R>();let w=type_name::with_original_ids<W>();let t=type_name::with_original_ids<T>();assert!(w.address_string()==t.address_string() && w.module_string()==t.module_string(),EPolicy);let PhysicalSettlement{product:bound,registry:id,registry_type,producer,revision,version:v,actor,receipt}=settlement;assert!(registry_type==type_name::with_defining_ids<T>() && producer==type_name::with_defining_ids<W>() && revision==type_name::with_defining_ids<R>() && bound==product && id==object::id(registry) && version==v && actor==ctx.sender(),EPolicy);receipt}

/// Synthetic initial role fixture only; production registration uses Publisher/Cap.
#[test_only]
public fun bootstrap_for_testing<C>(cfg:&mut Config<C>,admin:&mut economics::Admin){economics::pin_initial_role_for_testing(cfg,admin,2,CreatorAuthority1{},CreatorRevision3{})}

/// Included-with-Maker is checked against the actual frozen parent entitlement.
/// No copyable Source/Profile/quote substitutes for this synchronous input.
public(package) fun begin_pack_session<C,A:drop,R:drop,T:key>(p:&mut Product<C>,maker:&Product<C>,target:&T,cfg:&mut Config<C>,snapshot:Snapshot,payment:Coin<C>,a:A,r:R,clock:&Clock,ctx:&mut TxContext,guard:Availability):Session{begin_pack_session_value(p,maker,target,cfg,snapshot,payment,a,r,clock,ctx,false,option::some(consume_availability(guard,&snapshot,object::id(target))))}
public(package) fun begin_native_pack_session<C,A:drop,R:drop,T:key>(p:&mut Product<C>,maker:&Product<C>,target:&T,cfg:&mut Config<C>,snapshot:Snapshot,payment:Coin<C>,a:A,r:R,clock:&Clock,ctx:&mut TxContext,guard:Availability):Session{begin_pack_session_value(p,maker,target,cfg,snapshot,payment,a,r,clock,ctx,true,option::some(consume_availability(guard,&snapshot,object::id(target))))}
fun begin_pack_session_value<C,A:drop,R:drop,T:key>(p:&mut Product<C>,maker:&Product<C>,target:&T,cfg:&mut Config<C>,snapshot:Snapshot,payment:Coin<C>,a:A,r:R,clock:&Clock,ctx:&mut TxContext,native_route:bool,availability:Option<AvailabilitySnapshot>):Session{let v=origin::version(&snapshot);let version=published(p,v);assert_runtime_pack_published_value(p,maker,p.parent_version,v,version,cfg,version.policy_hash,version.manifest,origin::revision(&snapshot),origin::commitment(&snapshot),clock,ctx,native_route);begin_session_value(p,target,cfg,snapshot,payment,a,r,clock,ctx,native_route,true,availability)}

/// Same immutable publication borrowed before entering this runtime check.
fun assert_runtime_pack_published_value<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,v:&Version,cfg:&Config<C>,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext,native_route:bool){
    if(native_route)economics::assert_role_primary_snapshot<C,CreatorAuthority1,CreatorRevision3>(cfg,2,p.protocol,expected_config_revision,expected_config_commitment)
    else {assert_current_writer(cfg);economics::assert_manufacturing_snapshot(cfg,p.protocol,expected_config_revision,expected_config_commitment)};
    assert_runtime_pack_published(p,maker,maker_version,version,v,expected_policy,expected_manifest,clock,ctx)
}

/// Historical raw regression fixtures only. No certificate/System authority.
#[test_only]
public fun begin_native_session_for_testing<C,A:drop,R:drop,T:key>(p:&mut Product<C>,target:&T,cfg:&mut Config<C>,snapshot:Snapshot,payment:Coin<C>,a:A,r:R,clock:&Clock,ctx:&mut TxContext):Session{begin_session_value(p,target,cfg,snapshot,payment,a,r,clock,ctx,true,false,option::none())}
#[test_only]
public fun begin_native_pack_session_for_testing<C,A:drop,R:drop,T:key>(p:&mut Product<C>,maker:&Product<C>,target:&T,cfg:&mut Config<C>,snapshot:Snapshot,payment:Coin<C>,a:A,r:R,clock:&Clock,ctx:&mut TxContext):Session{begin_pack_session_value(p,maker,target,cfg,snapshot,payment,a,r,clock,ctx,true,option::none())}

#[test_only]
public fun buy_access_native_for_testing<C,A:drop,R:drop,T:key>(p:&mut Product<C>,cfg:&mut Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext,a:A,r:R) { assert_current_writer(cfg);assert_adapter<A,R,T>(published(p,v),a,r);buy_access_value(p,cfg,v,hash,fee_revision,expiry,attempt,payment,clock,ctx,true) }
#[test_only]
public fun claim_access_native_for_testing<C,A:drop,R:drop,T:key>(p:&mut Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext,a:A,r:R){ assert_current_writer(cfg);assert_adapter<A,R,T>(published(p,v),a,r);claim_access_value(p,cfg,v,hash,fee_revision,expiry,attempt,clock,ctx,true) }
#[test_only]
public fun ensure_access_native_for_testing<C,A:drop,R:drop,T:key>(p:&mut Product<C>,cfg:&Config<C>,v:u64,attempt:vector<u8>,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&mut TxContext,a:A,r:R){ assert_current_writer(cfg);assert_adapter<A,R,T>(published(p,v),a,r);ensure_access_value(p,cfg,v,attempt,fee_revision,expiry,clock,ctx,true) }
#[test_only]
public fun create_pack_native_for_testing<C,A:drop,R:drop,T:key>(maker:&Product<C>,parent_version:u64,control:&mut Control,cfg:&Config<C>,control_royalty_bps:u16,ctx:&mut TxContext,a:A,r:R):ID { assert_current_writer(cfg);assert_adapter<A,R,T>(published(maker,parent_version),a,r);create_pack_value(maker,parent_version,control,cfg,control_royalty_bps,ctx,true) }
#[test_only]
public fun collect_primary_native_for_testing<C,A:drop,R:drop,T:key>(p:&mut Product<C>,cfg:&mut Config<C>,r:PrimaryReceipt,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext,a:A,revision:R){ assert_current_writer(cfg);assert_adapter_types<A,R,T>(&published(p,1).execution.destroy_some());let _=a;let _=revision;collect_primary_value(p,cfg,r,payment,clock,ctx,true) }

public(package) fun collect_primary_value_for_factory<C>(p:&mut Product<C>,cfg:&mut Config<C>,receipt:PrimaryReceipt,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext){assert_current_writer(cfg);collect_primary_value(p,cfg,receipt,payment,clock,ctx,true)}

/// Historical raw Physical fixtures; production uses actual System-aware Factory.
#[test_only]
public fun bind_physical_registry_for_testing<C,W:drop,R:drop,T:key>(p:&mut Product<C>,control:&mut Control,v:u64,registry:&T,cfg:&Config<C>,w:W,r:R){bind_physical_registry(p,control,v,registry,cfg,w,r)}
#[test_only]
public fun settle_physical_for_testing<C,W:drop,R:drop,T:key>(p:&mut Product<C>,registry:&T,v:u64,cfg:&mut Config<C>,receipt:PrimaryReceipt,payment:Coin<C>,w:W,r:R,clock:&Clock,ctx:&mut TxContext):PhysicalSettlement{settle_physical(p,registry,v,cfg,receipt,payment,w,r,clock,ctx)}

/// Unit adapter for native Config receipt settlement; uses the real private
/// creator witness and original economics payment, actor, fee and primary gates.
#[test_only]
public fun settle_native_quote_for_testing<C>(cfg:&mut Config<C>,receipt:PrimaryReceipt,payment:sui::coin::Coin<C>,clock:&Clock,ctx:&mut TxContext):sui::coin::Coin<C>{economics::collect_primary<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{},receipt,payment,clock,ctx)}

/// Candidate-only designated witness transport. Actual version execution A/R/T
/// and private adapter values are checked by the original request path.
public(package) fun request_origin_with_witness<C,A:drop,R:drop,T:key>(p:&Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,name:String,attempt:vector<u8>,expiry:u64,a:A,r:R,clock:&Clock,ctx:&TxContext):(OriginRequest,SoulProducer){
 let request=request_origin<C,A,R,T>(p,cfg,v,hash,name,attempt,expiry,a,r,clock,ctx);(request,SoulProducer{})
}

/// Candidate generic Native execution witness transport, with original private
/// source and execution guards. No Kernel import or raw target return.
public fun request_native_origin_with_witness<C,A:drop,R:drop,T:key>(p:&Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,name:String,attempt:vector<u8>,expiry:u64,a:A,r:R,clock:&Clock,ctx:&TxContext):(OriginRequest,SoulProducer){let request=request_native_origin<C,A,R,T>(p,cfg,v,hash,name,attempt,expiry,a,r,clock,ctx);(request,SoulProducer{})}

/// Optional generic managed-authority domain. Existing Control remains freely
/// transferable outside enrollment. No Channel or application dependency.
/// The enrolled adapter must seal actual Control and keep witnesses private.
public struct ManagedAuthorityKey has copy,drop,store {}
public struct ManagedAuthority has drop,store {
 generation:u64,active:bool,control:ID,authority:ID,authority_type:std::type_name::TypeName,
 adapter:std::type_name::TypeName,revision:std::type_name::TypeName,principal:address,
}
const EManagedGeneration:u64=11;
fun managed_names<A,R,T>() {
 let a=type_name::with_original_ids<A>();let r=type_name::with_original_ids<R>();let t=type_name::with_original_ids<T>();
 assert!(!a.is_primitive() && !r.is_primitive() && a!=r && a.address_string()==r.address_string() && a.module_string()==r.module_string()
  && a.address_string()==t.address_string() && a.module_string()==t.module_string(),EControl)
}
public fun enroll_managed_authority<C,A:drop,R:drop,T:key>(p:&mut Product<C>,control:&Control,target:&T,_a:A,_r:R,ctx:&TxContext):u64 {
 assert_control(p,control);managed_names<A,R,T>();
 let generation=if(sui::dynamic_field::exists_(&p.id,ManagedAuthorityKey{})){
  let old:soulidity_maker_manufacturing::maker_catalog::ManagedAuthority=sui::dynamic_field::remove(&mut p.id,ManagedAuthorityKey{});
  assert!(!old.active,EControl);old.generation+1
 }else 1;
 sui::dynamic_field::add(&mut p.id,ManagedAuthorityKey{},ManagedAuthority{generation,active:true,control:object::id(control),authority:object::id(target),authority_type:type_name::with_defining_ids<T>(),adapter:type_name::with_defining_ids<A>(),revision:type_name::with_defining_ids<R>(),principal:ctx.sender()});generation
}
fun managed<C,A,R,T:key>(p:&Product<C>,control:&Control,target:&T):&ManagedAuthority {
 assert_control(p,control);let state:&ManagedAuthority=sui::dynamic_field::borrow(&p.id,ManagedAuthorityKey{});
 assert!(state.active && state.control==object::id(control) && state.authority==object::id(target) && state.authority_type==type_name::with_defining_ids<T>()
  && state.adapter==type_name::with_defining_ids<A>() && state.revision==type_name::with_defining_ids<R>(),EControl);state
}
public fun assert_managed_authority<C,A:drop,R:drop,T:key>(p:&Product<C>,control:&Control,target:&T,version:u64,generation:u64,principal:address,_a:A,_r:R) {
 let state=managed<C,A,R,T>(p,control,target);assert!(state.generation==generation,EManagedGeneration);
 assert!(state.principal==principal,EControl);assert!(p.version==version,EVersion);assert_active(p)
}
public fun managed_generation<C>(p:&Product<C>):u64 {let state:&ManagedAuthority=sui::dynamic_field::borrow(&p.id,ManagedAuthorityKey{});state.generation}
public fun managed_principal<C>(p:&Product<C>):address {let state:&ManagedAuthority=sui::dynamic_field::borrow(&p.id,ManagedAuthorityKey{});state.principal}
public fun rotate_managed_authority<C,A:drop,R:drop,T:key>(p:&mut Product<C>,control:&Control,target:&T,expected:u64,next:address,_a:A,_r:R,ctx:&TxContext):u64 {
 let state=managed<C,A,R,T>(p,control,target);assert!(state.generation==expected,EManagedGeneration);assert!(state.principal==ctx.sender() && next!=ctx.sender(),EControl);
 let state:&mut ManagedAuthority=sui::dynamic_field::borrow_mut(&mut p.id,ManagedAuthorityKey{});state.generation=state.generation+1;state.principal=next;state.generation
}
/// Domain exit never needs active publication, Config or service enablement.
public fun release_managed_authority<C,A:drop,R:drop,T:key>(p:&mut Product<C>,control:&Control,target:&T,expected:u64,_a:A,_r:R,ctx:&TxContext) {
 let state=managed<C,A,R,T>(p,control,target);assert!(state.generation==expected,EManagedGeneration);assert!(state.principal==ctx.sender(),EControl);
 let state:&mut ManagedAuthority=sui::dynamic_field::borrow_mut(&mut p.id,ManagedAuthorityKey{});state.active=false;state.generation=state.generation+1
}
