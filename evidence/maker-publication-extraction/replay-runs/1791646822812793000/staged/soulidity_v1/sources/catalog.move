/// Immutable published product policies, separate tradable control and address-bound use.
module soulidity_v1::catalog;
/// Private values are constructed and consumed only inside this producer.
public struct CreatorAuthority1 has drop {}
/// Retained for compatible type origins; current business uses Revision3.
public struct CreatorRevision1 has drop {}
public struct CreatorRevision2 has drop {}
public struct CreatorRevision3 has drop {}
public struct CATALOG has drop {}
fun init(w:CATALOG,ctx:&mut TxContext){sui::package::claim_and_keep(w,ctx)}


use std::bcs;
use soulidity_application::publication_rules;
use sui::table::{Self,Table};
use sui::coin::Coin;
use sui::clock::Clock;
use sui::event;
use sui::dynamic_object_field as dof;
use soulidity_model::policy::{Self,Definition,Source,Adapter};
use soulidity_foundation::economics::{Self,Config,MarketPolicy,PrimaryPolicy,PrimaryReceipt};
use soulidity_application::output::{Self};
use soulidity_maker_publication::output_data::{Policy};
use soulidity_maker_terms::maker_resale::{Self as resale,Rates};
use soulidity_model::material_policy::{Self,Terms};
use soulidity_foundation::revenue::{Self,Ledger};
use soulidity_visual::visual::{Self,Scene};
use soulidity_model::assembly::{Self,Profile,Scope};
use std::string::String;
use soulidity_standard::soul::{Self as standard,Soul};
/// Source attestation can only be constructed by the actual Product module.
public struct SoulProducer has drop {}
/// Source previews require the real Product and this module's private value.
public struct PolicyProducer has drop {}
public struct ComponentProducer has drop {}

/// Minting, quota/replay reservation and full primary settlement are atomic.
/// No producer witness, unpaid root or mutable Product UID is exposed externally.
public(package) fun mint_soul<C>(binding:soulidity_maker_admission::maker_issuance::Binding,p:&mut Product<C>,cfg:&mut Config<C>,v:u64,name:String,hash:vector<u8>,attempt:vector<u8>,fee_revision:u64,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):(Soul,soulidity_maker_admission::maker_issuance::Genesis,PrimaryReceipt){
    assert!(p.maker.is_none() && p.protocol==object::id(cfg),EParent);
    assert!(name.length()>0 && name.length()<=128,EPolicy);
    economics::assert_primary_live(cfg,fee_revision,expiry,clock);
    let version=*published(p,v);assert!(version.policy_hash==hash,EPolicy);
    assert_publication_economics(p,&version);
    assert_runtime_access(p,cfg,v,hash,version.manifest,fee_revision,economics::commitment(cfg),clock,ctx);
    let root=standard::new(SoulProducer{},p,v,hash,name,ctx);let id=object::id(&root);
    let price=authorize_complete(p,v,hash,attempt,id,ctx);
    let r=economics::route_primary(economics::primary_quote(&version.primary.destroy_some(),cfg,price,true,version.beneficiary,id,hash,ctx.sender(),attempt,expiry),object::id(p));
    assert!(sui::coin::value(&payment)==economics::primary_receipt_total(&r),EPolicy);
    collect_primary(p,cfg,r,payment,clock,ctx);
    let resale=resale::snapshot(object::id(cfg),object::id(p),v,hash,creator(p),version.soul_rates,ctx);
    let metadata=soulidity_application::character::genesis_hash(object::id(cfg),object::id(p),v,version.manifest,version.configuration,assembly_profile(p,v),version.required_parts,version.adapters,version.scene,resale,version.beneficiary,ctx);
    let genesis=soulidity_maker_admission::maker_issuance::authorize_genesis(cfg,CreatorAuthority1{},CreatorRevision3{},p,&root,binding,metadata,ctx);(root,genesis,r)
}

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
    manifest:vector<u8>, configuration:vector<u8>, policy_hash:vector<u8>,publication:Option<PublicationContext>,
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
    let invalid=soulidity_application::publication_rules::validate(&manifest,&configuration,access_mode,access_price,completion_mode,completion_price,quota,royalty_bps,beneficiary,&parts,&required_parts,&definitions,&adapters,&scene);
    assert!(invalid==0,invalid);
    assert_native_economics(access_price,completion_price,quota,cap,royalty_bps,&soul_rates);
    let mut v=Version {manifest,configuration,policy_hash:vector[],publication:option::none(),access_mode,access_price,completion_mode,completion_price,quota,cap,royalty_bps,beneficiary,soul_rates,market:option::none(),primary:option::none(),parts,required_parts,definitions,adapters,scene,outputs:vector[],pack_key:vector[],physical:vector[]};
    v.policy_hash=policy::hash_bytes(bcs::to_bytes(&v));v
}
public fun create_maker<C>(cfg:&Config<C>,control_royalty_bps:u16,ctx:&mut TxContext):ID { economics::assert_business<C,CreatorAuthority1,CreatorRevision3>(cfg,2,CreatorAuthority1{},CreatorRevision3{});create<C>(cfg,control_royalty_bps,economics::primary_policy(cfg),option::none(),0,option::none(),ctx) }
public(package) fun create_pack<C>(maker:&Product<C>,parent_version:u64,control:&mut Control,cfg:&Config<C>,control_royalty_bps:u16,ctx:&mut TxContext):ID {
    assert_control(maker,control);assert!(maker.maker.is_none(),EParent);let _=published(maker,parent_version);
    assert!(maker.protocol==object::id(cfg),EPolicy);economics::assert_primary(cfg);let v=published(maker,parent_version);let snapshot=ParentSnapshot{scope:assembly::scope(PolicyProducer{},maker,maker.protocol,parent_version,v.policy_hash),policy_hash:v.policy_hash,scene:v.scene,paths:v.definitions.map_ref!(|d|policy::definition_path(d))};assert!(bcs::to_bytes(&snapshot).length()<=196608,EBounds);create<C>(cfg,control_royalty_bps,maker.primary,option::some(object::id(maker)),parent_version,option::some(snapshot),ctx)
}
fun create<C>(cfg:&Config<C>,control_royalty_bps:u16,primary:PrimaryPolicy,maker:Option<ID>,parent_version:u64,parent_snapshot:Option<ParentSnapshot>,ctx:&mut TxContext):ID {
    assert_native_royalty(control_royalty_bps);
    let uid=object::new(ctx);let income=revenue::new<C>(&uid,ctx);
    let p=Product<C>{id:uid,protocol:object::id(cfg),creator:ctx.sender(),market:economics::market_policy(cfg,control_royalty_bps,ctx),primary,maker,parent_version,parent_snapshot,version:0,lifecycle:0,versions:table::new(ctx),access:table::new(ctx),income,issued:table::new(ctx),completes:table::new(ctx),attempts:table::new(ctx),payments:table::new(ctx),physical_registries:table::new(ctx)};
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
    n.outputs=v.outputs;n.pack_key=v.pack_key;with_physical(n,v.physical)
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
public fun assert_runtime_access<C>(p:&Product<C>,cfg:&Config<C>,v:u64,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext){
    economics::assert_primary_snapshot(cfg,p.protocol,expected_config_revision,expected_config_commitment);let version=published(p,v);
    assert!(version.policy_hash==expected_policy && version.manifest==expected_manifest,EPolicy);assert_access(p,v,ctx.sender());
    if(access_held(p,v,ctx.sender()))assert!(p.access.borrow(AccessKey{wallet:ctx.sender(),version:v}).issued_at_ms<=sui::clock::timestamp_ms(clock),EAccess)
}
/// Entering a free Maker records its exact zero-price entitlement in the same
/// transaction as Player creation or Complete. Paid access never auto-claims.
public(package) fun ensure_access<C>(p:&mut Product<C>,cfg:&Config<C>,v:u64,attempt:vector<u8>,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&mut TxContext){
    let version=*published(p,v);if(version.access_mode==0 && !access_held(p,v,ctx.sender()))claim_access(p,cfg,v,version.policy_hash,fee_revision,expiry,attempt,clock,ctx);
    assert_access(p,v,ctx.sender())
}
public fun assert_pack<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,wallet:address) {
    assert_active(p);assert_active(maker);assert!(maker.maker.is_none() && p.protocol==maker.protocol && p.maker==option::some(object::id(maker)) && p.parent_version==maker_version,EParent);
    assert!(parent_policy(p)==option::some(published(maker,maker_version).policy_hash),EParent);
    let v=published(p,version);
    if(v.access_mode==2)assert_access_entitlement(maker,maker_version,wallet) else assert_access(p,version,wallet);
}
public fun assert_runtime_pack<C>(p:&Product<C>,maker:&Product<C>,maker_version:u64,version:u64,cfg:&Config<C>,expected_policy:vector<u8>,expected_manifest:vector<u8>,expected_config_revision:u64,expected_config_commitment:vector<u8>,clock:&Clock,ctx:&TxContext){
    economics::assert_primary_snapshot(cfg,p.protocol,expected_config_revision,expected_config_commitment);let v=published(p,version);assert!(v.policy_hash==expected_policy && v.manifest==expected_manifest,EPolicy);
    assert_pack(p,maker,maker_version,version,ctx.sender());
    if(v.access_mode==2){let mv=published(maker,maker_version);assert_runtime_access(maker,cfg,maker_version,mv.policy_hash,mv.manifest,expected_config_revision,expected_config_commitment,clock,ctx)}
    else assert_runtime_access(p,cfg,version,expected_policy,expected_manifest,expected_config_revision,expected_config_commitment,clock,ctx)
}
public(package) fun buy_access<C>(p:&mut Product<C>,cfg:&mut Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    assert!(p.protocol==object::id(cfg),EPolicy);economics::assert_primary_live(cfg,fee_revision,expiry,clock);assert!(p.lifecycle==1,ELifecycle);
    let version=*published(p,v);assert!(version.policy_hash==hash && version.access_mode==1,EPolicy);
    assert!(!access_held(p,v,ctx.sender()),EAccess);let product_id=object::id(p);record_attempt(p,1,attempt,product_id,ctx);
    let r=access_quote(p,cfg,v,ctx.sender(),attempt,expiry);collect_primary(p,cfg,r,payment,clock,ctx);p.payments.add(RequestKey{actor:ctx.sender(),kind:1,attempt},r);
    issue_access(p,v,r,clock,ctx);event::emit(AccessPurchased{product:object::id(p),buyer:ctx.sender(),version:v,attempt});
}
public fun access_quote<C>(p:&Product<C>,cfg:&Config<C>,version:u64,actor:address,attempt:vector<u8>,expiry:u64):PrimaryReceipt {
    let v=published(p,version);assert!(v.access_mode==1,EPolicy);
    economics::route_primary(economics::primary_quote(&v.primary.destroy_some(),cfg,v.access_price,false,v.beneficiary,object::id(p),v.policy_hash,actor,attempt,expiry),object::id(p))
}
public(package) fun collect_primary<C>(p:&mut Product<C>,cfg:&mut Config<C>,r:PrimaryReceipt,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext){
    assert!(p.protocol==object::id(cfg) && economics::primary_receipt_revenue(&r)==option::some(object::id(p)),EPolicy);
    revenue::deposit(&p.id,&mut p.income,economics::collect_primary<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{},r,payment,clock,ctx))
}
fun issue_access<C>(p:&mut Product<C>,v:u64,r:PrimaryReceipt,clock:&Clock,ctx:&TxContext){
    let version=*published(p,v);let product=object::id(p);p.access.add(AccessKey{wallet:ctx.sender(),version:v},Access{product,version:v,policy_hash:version.policy_hash,manifest:version.manifest,holder:ctx.sender(),paid:economics::primary_receipt_gross(&r),issued_at_ms:sui::clock::timestamp_ms(clock)})
}
public(package) fun claim_access<C>(p:&mut Product<C>,cfg:&Config<C>,v:u64,hash:vector<u8>,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext){
    assert!(p.protocol==object::id(cfg),EPolicy);economics::assert_primary_live(cfg,fee_revision,expiry,clock);assert_active(p);
    let version=*published(p,v);assert!(version.access_mode==0 && version.policy_hash==hash,EPolicy);assert!(!access_held(p,v,ctx.sender()),EAccess);
    let id=object::id(p);record_attempt(p,1,attempt,id,ctx);
    let r=economics::route_primary(economics::primary_quote(&version.primary.destroy_some(),cfg,0,false,version.beneficiary,id,hash,ctx.sender(),attempt,expiry),id);
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
public fun deposit_income<C>(p:&mut Product<C>,cfg:&Config<C>,payment:Coin<C>){assert!(p.protocol==object::id(cfg),EPolicy);assert_active(p);economics::assert_enabled(cfg);assert!(sui::coin::value(&payment)>0,EPolicy);revenue::deposit(&p.id,&mut p.income,payment)}
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
    assert!(p.lifecycle==1,ELifecycle);let version=*published(p,v);assert!(version.policy_hash==hash,EPolicy);
    let price=completion_price(p,v,ctx.sender());let all=wallet_completes(p,v,@0x0);
    assert!(version.cap==0 || all < version.cap,ECap);
    record_attempt(p,2,attempt,soul,ctx);increment_count(p,CountKey{version:v,wallet:@0x0});
    // @0x0 is reserved for aggregate counts and cannot be a transaction sender.
    increment_count(p,CountKey{version:v,wallet:ctx.sender()});price
}
fun increment_count<C>(p:&mut Product<C>,key:CountKey) {
    if(p.completes.contains(key))*p.completes.borrow_mut(key)=*p.completes.borrow(key)+1 else p.completes.add(key,1)
}
public(package) fun issue<C>(p:&mut Product<C>,v:u64,definition_hash:vector<u8>,target:&soulidity_standard::soul::Soul):soulidity_model::components::Permit {
    let version=*published(p,v);let mut found=option::none();
    version.definitions.do_ref!(|d| {if(policy::definition_hash(d)==definition_hash)found=option::some(*d)});
    assert!(found.is_some(),EDefinition);let d=found.destroy_some();
    let supply_key=policy::hash_bytes(bcs::to_bytes(&SupplyKey{version:v,definition:definition_hash}));
    let issued=if(p.issued.contains(supply_key))*p.issued.borrow(supply_key) else 0;
    assert!(issued < policy::supply(&d),ECap);
    if(p.issued.contains(supply_key))*p.issued.borrow_mut(supply_key)=issued+1 else p.issued.add(supply_key,issued+1);
    let maker=if(p.maker.is_some())*p.maker.borrow() else object::id(p);
    let maker_version=if(p.maker.is_some())p.parent_version else v;
    let source=policy::source(PolicyProducer{},p,maker,maker_version,v,p.protocol,version.royalty_bps,version.beneficiary,version.market.destroy_some(),version.primary.destroy_some(),d);
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
/// Read-only provenance preview does not issue supply or an Item object.
public fun preview_source<C>(p:&Product<C>,v:u64,definition_hash:vector<u8>):Source {
    let version=published(p,v);let mut found=option::none();version.definitions.do_ref!(|d|{if(policy::definition_hash(d)==definition_hash)found=option::some(*d)});
    assert!(found.is_some(),EDefinition);let d=found.destroy_some();let maker=if(p.maker.is_some())*p.maker.borrow() else object::id(p);let maker_version=if(p.maker.is_some())p.parent_version else v;
    policy::source(PolicyProducer{},p,maker,maker_version,v,p.protocol,version.royalty_bps,version.beneficiary,version.market.destroy_some(),version.primary.destroy_some(),d)
}

public fun register<C>(cfg:&mut soulidity_foundation::economics::Config<C>,admin:&mut soulidity_foundation::economics::Admin,expected:u64,hash:vector<u8>,publisher:&sui::package::Publisher,cap:&sui::package::UpgradeCap){
    economics::register_role<C,CreatorAuthority1,CreatorRevision3>(cfg,admin,expected,hash,2,CreatorAuthority1{},CreatorRevision3{},publisher,cap)
}

#[test_only]
public fun settle_quote_for_testing<C>(cfg:&mut Config<C>,receipt:PrimaryReceipt,payment:sui::coin::Coin<C>,clock:&Clock,ctx:&mut TxContext):sui::coin::Coin<C>{economics::collect_primary<C,CreatorAuthority1,CreatorRevision3>(cfg,CreatorAuthority1{},CreatorRevision3{},receipt,payment,clock,ctx)}

/// Native admission proof is returned only after quota reservation and actual Coin
/// settlement; copyable PrimaryReceipt alone never grants an application action.
public(package) fun complete_contribution<C>(p:&mut Product<C>,root:&Soul,cfg:&mut Config<C>,version:u64,hash:vector<u8>,attempt:vector<u8>,expiry:u64,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext):soulidity_maker_admission::maker_issuance::Contribution{
    assert!(p.protocol==object::id(cfg),EPolicy);let v=*published(p,version);assert!(v.policy_hash==hash,EPolicy);
    let price=authorize_complete(p,version,hash,attempt,object::id(root),ctx);
    let receipt=economics::route_primary(economics::primary_quote(&v.primary.destroy_some(),cfg,price,false,v.beneficiary,object::id(root),hash,ctx.sender(),attempt,expiry),object::id(p));
    collect_primary(p,cfg,receipt,payment,clock,ctx);
    soulidity_maker_admission::maker_issuance::authorize_contribution(cfg,CreatorAuthority1{},CreatorRevision3{},p,root,version,hash,receipt,ctx)
}
