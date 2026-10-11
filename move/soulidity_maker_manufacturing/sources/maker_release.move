/// Actual publication transport authority for the unified package.
/// Blob certification proves availability; authors declare SHA-256/Seal content.
module soulidity_maker_manufacturing::maker_release;
public struct MAKER_RELEASE has drop {}
fun init(w:MAKER_RELEASE,ctx:&mut TxContext){sui::package::claim_and_keep(w,ctx)}
use std::bcs;
use std::hash;
use std::type_name;
use sui::dynamic_object_field as dof;
use sui::clock::Clock;
use walrus::blob::Blob;
use walrus::system::{Self,System};
use soulidity_foundation::economics::{Self,Config,Admin};

use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,Product,Control,Version};
use soulidity_transport::storage_transport::{Self as storage,Reference};
use soulidity_transport::blob_transport as blob_custody;
use soulidity_visual::visual;
use soulidity_maker_publication::publication_validation as publication_rules;
use soulidity_maker_publication::publication_validation::Expected;
use soulidity_model::policy;
use soulidity_transport::paged_transport::{Self as paged_store,Store};
const MISSING_ROW:u64=500;
const EIdentity:u64=1;const EActor:u64=2;const ERevision:u64=3;const EAsset:u64=4;const EComplete:u64=5;const EBounds:u64=6;const EScope:u64=7;
/// Private constructor; production install consumes this role into a linear permit.
public struct ReleaseInstaller1 has drop {}
/// Retained for compatible type origins; current business uses Revision3.
public struct ReleaseRevision1 has drop {}
public struct ReleaseRevision2 has drop {}
public struct ReleaseRevision3 has drop {}
public struct Author has copy,drop,store {name:vector<u8>,description:vector<u8>,website:vector<u8>,license:vector<u8>,defaults:vector<u8>}
public struct CatalogBody has copy,drop,store {domain:vector<u8>,config:ID,generation:u64,original:ID,callable:ID,system:ID,source:vector<u8>,abi:vector<u8>}
public struct Catalog<phantom C> has key,store {id:UID,body:CatalogBody,commitment:vector<u8>}
public struct CatalogCommitment has drop {id:ID,body:CatalogBody}
public struct Asset has copy,drop,store {asset:vector<u8>,plain_bytes:u64,protected:bool,scope:vector<u8>,reference:Reference}
public struct Header has copy,drop,store {domain:vector<u8>,config:ID,config_revision:u64,config_commitment:vector<u8>,catalog:ID,catalog_commitment:vector<u8>,catalog_generation:u64,product:ID,version:u64,actor:address,author:Author,system:ID,living:Reference,manifest:Reference}
/// Persistable/chunked, but not public-transferable; tied to original author.
public struct MetadataKey has copy,drop,store {}
public struct DraftVersion has key,store {id:UID,version:Version}
/// Expected is immutable and sorted. index maps each required digest to its
/// insertion-order metadata row; 500 is the only uninstalled sentinel. Every
/// install is private, unique, and below 500. No per-asset index object exists.
public struct Draft has key {id:UID,header:Header,expected:vector<Expected>,rows:Store<Asset>,index:vector<u64>,revision:u64,canceling:bool,returned:u64}
/// Fresh certificate UID; completed Draft custody UID and all child IDs remain intact.
public struct Custody has store {id:UID}
/// Carries the same sorted directory and row mapping moved from the Draft.
/// Neither can be replaced by a foreign package. Commitment format is unchanged.
public struct Certificate has key,store {id:UID,custody:Custody,header:Header,policy:vector<u8>,rows:Store<Asset>,expected:vector<Expected>,index:vector<u64>,commitment:vector<u8>}
public struct CertificateCommitment has drop {domain:vector<u8>,id:ID,header:Header,policy:vector<u8>,assets:vector<Asset>}
public struct Scope has drop {domain:vector<u8>,config:ID,product:ID,version:u64,asset:vector<u8>}
public fun author(name:vector<u8>,description:vector<u8>,website:vector<u8>,license:vector<u8>,defaults:vector<u8>):Author{
    assert!(!name.is_empty() && name.length()<=128 && description.length()<=4096 && website.length()<=512 && !license.is_empty() && license.length()<=2048,EBounds);policy::assert_hash(&defaults);Author{name,description,website,license,defaults}
}
public fun author_name(a:&Author):vector<u8>{a.name}
public fun author_defaults(a:&Author):vector<u8>{a.defaults}
fun computed<C>(c:&Catalog<C>):vector<u8>{hash::sha2_256(bcs::to_bytes(&CatalogCommitment{id:object::id(c),body:c.body}))}
/// Source/ABI hashes are build declarations, not independently attested code.
public fun install<C>(cfg:&mut Config<C>,a:&mut Admin,system:&System,source:vector<u8>,abi:vector<u8>,expected:u64,expected_hash:vector<u8>,ctx:&mut TxContext):ID{
    economics::assert_install_admin(cfg,a,expected,expected_hash);assert!(economics::is_nonzero_hash(&source) && economics::is_nonzero_hash(&abi),EIdentity);
    let old=economics::release_snapshot(cfg);let generation=if(old.is_none())0 else economics::release_generation(old.borrow())+1;
    let mut c=Catalog<C>{id:object::new(ctx),body:CatalogBody{domain:b"soulidity/manufacturing-catalog/v1",config:object::id(cfg),generation,original:object::id_from_address(type_name::original_id<ReleaseInstaller1>()),callable:object::id_from_address(type_name::defining_id<ReleaseRevision3>()),system:object::id(system),source,abi},commitment:vector[]};c.commitment=computed(&c);let id=object::id(&c);let h=c.commitment;
    let permit=economics::authorize_installation<C,ReleaseInstaller1,ReleaseRevision3,Catalog<C>>(cfg,a,expected,expected_hash,1,ReleaseInstaller1{},ReleaseRevision3{},&c,generation,h);economics::install_manufacturing_release(cfg,a,permit,c,generation,h);id
}
public fun current<C>(cfg:&Config<C>):&Catalog<C>{economics::release_object(cfg)}
public fun historical<C>(cfg:&Config<C>,generation:u64):&Catalog<C>{economics::release_history(cfg,generation)}
public fun catalog_hash<C>(c:&Catalog<C>):vector<u8>{c.commitment}
public fun catalog_system<C>(c:&Catalog<C>):ID{c.body.system}
public fun catalog_generation<C>(c:&Catalog<C>):u64{c.body.generation}
public fun assert_catalog<C>(cfg:&Config<C>,system:&System){
    economics::assert_manufacturing_enabled(cfg);catalog::assert_current_writer(cfg);economics::assert_role_types<C,ReleaseInstaller1,ReleaseRevision3>(cfg,1);let c=current(cfg);let s=economics::release_snapshot(cfg).destroy_some();
    assert!(c.body.config==object::id(cfg) && c.body.original==object::id_from_address(type_name::original_id<ReleaseInstaller1>()) && c.body.callable==object::id_from_address(type_name::defining_id<ReleaseRevision3>()) && c.body.system==object::id(system) && c.commitment==computed(c) && economics::release_catalog(&s)==object::id(c) && economics::release_generation(&s)==c.body.generation && economics::release_commitment(&s)==c.commitment,EIdentity)
}
fun expected(v:&Version):vector<Expected>{
    let(rows,invalid)=publication_rules::expected_assets(catalog::definitions_ref(v));assert!(invalid==0,invalid);rows
}
public fun begin<C>(p:&Product<C>,control:&mut Control,cfg:&Config<C>,expected_version:u64,v:Version,author:Author,living:Blob,manifest:Blob,system:&System,ctx:&mut TxContext):Draft{
    catalog::assert_control(p,control);economics::assert_manufacturing_primary(cfg);assert_catalog(cfg,system);assert!(catalog::protocol(p)==object::id(cfg),EIdentity);assert!(catalog::current_version(p)==expected_version,ERevision);
    catalog::assert_publication_economics(p,&v);
    let l=storage::certified(&living,system,catalog::configuration(&v));let m=storage::certified(&manifest,system,catalog::manifest(&v));let c=current(cfg);
    let header=Header{domain:b"soulidity/publication/v1",config:object::id(cfg),config_revision:economics::revision(cfg),config_commitment:economics::commitment(cfg),catalog:object::id(c),catalog_commitment:c.commitment,catalog_generation:c.body.generation,product:object::id(p),version:expected_version+1,actor:ctx.sender(),author,system:object::id(system),living:l,manifest:m};
    let required=expected(&v);assert!(bcs::to_bytes(&v).length()<=196608,EBounds);let lookup=required;let index=vector::tabulate!(lookup.length(),|_|MISSING_ROW);let metadata=DraftVersion{id:object::new(ctx),version:v};let mut d=Draft{id:object::new(ctx),header,expected:lookup,rows:paged_store::new(ctx),index,revision:0,canceling:false,returned:0};assert!(bcs::to_bytes(&d).length()<=245760,EBounds);
    dof::add(&mut d.id,MetadataKey{},metadata);blob_custody::add_document(&mut d.id,0,living);blob_custody::add_document(&mut d.id,1,manifest);d
}
public fun deliver(d:Draft,ctx:&TxContext){assert!(d.header.actor==ctx.sender(),EActor);transfer::transfer(d,ctx.sender())}
public fun revision(d:&Draft):u64{d.revision}
public fun asset_count(d:&Draft):u64{paged_store::length(&d.rows)}
public fun expected_count(d:&Draft):u64{d.expected.length()}
public fun draft_version(d:&Draft):&Version{let m:&DraftVersion=dof::borrow(&d.id,MetadataKey{});&m.version}
public fun expected_asset(d:&Draft,index:u64):vector<u8>{publication_rules::expected_digest(&d.expected[index])}
fun expected_position(d:&Draft,asset:vector<u8>):u64{let position=publication_rules::expected_index(&d.expected,asset);assert!(position.is_some(),EAsset);position.destroy_some()}
public fun expected_bytes(d:&Draft,asset:vector<u8>):u64{publication_rules::expected_size(&d.expected[expected_position(d,asset)])}
public fun seal_scope(config:ID,product:ID,version:u64,asset:vector<u8>):vector<u8>{policy::assert_hash(&asset);bcs::to_bytes(&Scope{domain:b"soulidity/publication/asset/v1",config,product,version,asset})}
fun check<C>(d:&Draft,p:&Product<C>,control:&mut Control,cfg:&Config<C>,system:&System,revision:u64,ctx:&TxContext){
    assert!(d.header.actor==ctx.sender(),EActor);assert!(!d.canceling && d.returned==0,EComplete);catalog::assert_control(p,control);economics::assert_manufacturing_primary(cfg);assert_catalog(cfg,system);
    assert!(d.revision==revision && catalog::current_version(p)+1==d.header.version,ERevision);
    assert!(d.header.product==object::id(p) && d.header.config==object::id(cfg) && d.header.config_revision==economics::revision(cfg) && d.header.config_commitment==economics::commitment(cfg) && d.header.catalog==object::id(current(cfg)) && d.header.catalog_commitment==current(cfg).commitment && d.header.system==object::id(system),EIdentity)
}
public fun append<C>(d:&mut Draft,p:&Product<C>,control:&mut Control,cfg:&Config<C>,asset:vector<u8>,protected:bool,transport_hash:vector<u8>,blob:Blob,system:&System,expected_revision:u64,ctx:&mut TxContext){
    check(d,p,control,cfg,system,expected_revision,ctx);append_asset(d,asset,protected,transport_hash,blob,system,ctx)
}
/// One authority/CAS check per bounded transaction; every Blob is still validated.
public fun append_batch<C>(d:&mut Draft,p:&Product<C>,control:&mut Control,cfg:&Config<C>,assets:vector<vector<u8>>,protected:vector<bool>,transport_hashes:vector<vector<u8>>,blobs:vector<Blob>,system:&System,expected_revision:u64,ctx:&mut TxContext){
    check(d,p,control,cfg,system,expected_revision,ctx);let n=assets.length();assert!(n>0 && n<=32 && n==protected.length() && n==transport_hashes.length() && n==blobs.length(),EBounds);let mut references=storage::certified_batch(&blobs,system,&transport_hashes);let mut assets=assets;let mut protected=protected;let mut blobs=blobs;assets.reverse();protected.reverse();references.reverse();blobs.reverse();while(!assets.is_empty()){let asset=assets.pop_back();let position=expected_position(d,asset);let bytes=publication_rules::expected_size(&d.expected[position]);assert!(d.index[position]==MISSING_ROW,EAsset);record_asset(d,position,asset,bytes,protected.pop_back(),references.pop_back(),blobs.pop_back(),ctx)};blobs.destroy_empty()
}
fun append_asset(d:&mut Draft,asset:vector<u8>,protected:bool,transport_hash:vector<u8>,blob:Blob,system:&System,ctx:&mut TxContext){
    let position=expected_position(d,asset);let bytes=publication_rules::expected_size(&d.expected[position]);
    assert!(d.index[position]==MISSING_ROW,EAsset);
    let reference=storage::certified(&blob,system,transport_hash);record_asset(d,position,asset,bytes,protected,reference,blob,ctx)
}
/// Private: both callers obtain this Reference from the actual Blob/System in
/// the same synchronous invocation. No externally supplied cached proof enters.
fun record_asset(d:&mut Draft,position:u64,asset:vector<u8>,bytes:u64,protected:bool,reference:Reference,blob:Blob,ctx:&mut TxContext){
    if(!protected)assert!(storage::hash(&reference)==asset && storage::bytes(&reference)==bytes,EAsset);
    let scope=if(protected)seal_scope(d.header.config,d.header.product,d.header.version,asset) else vector[];
    let index=paged_store::append(&mut d.rows,Asset{asset,plain_bytes:bytes,protected,scope,reference});*d.index.borrow_mut(position)=index;blob_custody::append(&mut d.id,index,blob,ctx);d.revision=d.revision+1
    // Pinned Blob layout is at most131 BCS bytes (including Storage/UID).
    // UID32 + vector prefix1 +32*131 =4225, below245760. Dynamic fields
    // are separate objects. Bound page length instead of serializing the page
    // after every append; certification and original custody checks remain.
    // Immutable Version lives in its private metadata DOF; the compact head has
    // a <=500 digest directory (41 bytes/row), row mapping (8 bytes/row),
    // and page locations (16 bytes/row); these remain below the object limit. Never reserialize immutable Version.
}
fun references(rows:&Store<Asset>):vector<Reference>{
    paged_store::values(rows).map!(|a|{let Asset{asset:_,plain_bytes:_,protected:_,scope:_,reference}=a;reference})
}
fun snapshots(d:&Draft,system:&System){
    assert!(d.header.system==object::id(system),EIdentity);
    blob_custody::assert_current(&d.id,&d.header.living,&d.header.manifest,&references(&d.rows),system)
}
fun available(c:&Certificate,system:&System){
    assert!(c.header.system==object::id(system),EIdentity);
    blob_custody::assert_current(&c.custody.id,&c.header.living,&c.header.manifest,&references(&c.rows),system)
}
public fun finish<C>(d:Draft,p:&mut Product<C>,control:&mut Control,cfg:&Config<C>,system:&System,expected_revision:u64,ctx:&mut TxContext):ID{
    check(&d,p,control,cfg,system,expected_revision,ctx);assert!(paged_store::length(&d.rows)==d.expected.length(),EComplete);snapshots(&d,system);
    let Draft{mut id,header,expected,rows,index,revision:_,canceling:_,returned:_}=d;let DraftVersion{id:metadata_id,version}=dof::remove(&mut id,MetadataKey{});metadata_id.delete();let certificate_uid=object::new(ctx);let custody=Custody{id};let policy=catalog::publish(p,control,header.version-1,version);let certificate_id=object::uid_to_inner(&certificate_uid);
    let commitment=hash::sha2_256(bcs::to_bytes(&CertificateCommitment{domain:b"soulidity/publication-certificate/v1",id:certificate_id,header,policy,assets:paged_store::values(&rows)}));let cert=Certificate{id:certificate_uid,custody,header,policy,rows,expected,index,commitment};catalog::attach_certification(p,cert.header.version,cert);certificate_id
}

/// Bounded recovery is available even after Config changes or Blob expiry.
public fun cancel_chunk(d:&mut Draft,limit:u64,expected:u64,ctx:&TxContext):vector<Blob>{
    assert!(d.header.actor==ctx.sender(),EActor);assert!(d.revision==expected,ERevision);assert!(limit>0 && limit<=32 && d.returned < paged_store::length(&d.rows),EBounds);d.canceling=true;let mut blobs=vector[];let mut n=0;while(n < limit && d.returned < paged_store::length(&d.rows)){blobs.push_back(blob_custody::take(&mut d.id,d.returned));d.returned=d.returned+1;n=n+1};d.revision=d.revision+1;blobs
}
public fun cancel(d:Draft,ctx:&TxContext):vector<Blob>{
    assert!(d.header.actor==ctx.sender(),EActor);assert!(paged_store::length(&d.rows)-d.returned<=30,EBounds);let Draft{mut id,header:_,expected:_,rows,index:_,revision:_,canceling:_,returned}=d;let DraftVersion{id:metadata_id,version}=dof::remove(&mut id,MetadataKey{});metadata_id.delete();let mut blobs=vector[blob_custody::take_document(&mut id,0),blob_custody::take_document(&mut id,1)];let mut i=returned;while(i < paged_store::length(&rows)){blobs.push_back(blob_custody::take(&mut id,i));i=i+1};paged_store::destroy(rows);id.delete();blobs
}
public fun certificate<C>(p:&Product<C>,version:u64):&Certificate{catalog::certification(p,version)}
public fun certificate_hash(c:&Certificate):vector<u8>{c.commitment}
public fun certificate_author(c:&Certificate):&Author{&c.header.author}
public fun certificate_rows(c:&Certificate):u64{paged_store::length(&c.rows)}
public fun certificate_asset(c:&Certificate,index:u64):&Asset{paged_store::get(&c.rows,index)}
public fun certificate_asset_by_hash(c:&Certificate,asset:vector<u8>):&Asset{assert!(asset.length()==32,EAsset);let at=publication_rules::expected_index(&c.expected,asset);assert!(at.is_some(),EAsset);paged_store::get(&c.rows,c.index[at.destroy_some()])}
public fun asset_reference(a:&Asset):&Reference{&a.reference}
public fun asset_scope(a:&Asset):vector<u8>{a.scope}
public fun asset_protected(a:&Asset):bool{a.protected}
public fun asset_hash(a:&Asset):vector<u8>{a.asset}
public fun asset_plain_bytes(a:&Asset):u64{a.plain_bytes}
/// Renewal preserves the certified Blob ID and all semantic commitments.
/// The pinned Walrus dependency only extends a still-live certified Blob.
/// Its end epoch is exclusive; expired Blobs cannot be revived in place.
/// A new upload/publication is a separate workflow, not same-object renewal.
public fun extend_blob<C>(p:&mut Product<C>,control:&mut Control,cfg:&Config<C>,version:u64,kind:u8,index:u64,extension:walrus::storage_resource::Storage,system:&System){
    catalog::assert_control(p,control);assert_catalog(cfg,system);assert!(catalog::protocol(p)==object::id(cfg),EIdentity);let c:&mut Certificate=catalog::certification_mut(p,version);assert!(c.header.system==object::id(system) && ((kind < 2 && index==0)||(kind==2 && index < paged_store::length(&c.rows))),EAsset);let blob=blob_custody::borrow_mut(&mut c.custody.id,kind,index);system::extend_blob_with_resource(system,blob,extension);storage::assert_current(if(kind==0)&c.header.living else if(kind==1)&c.header.manifest else &paged_store::get(&c.rows,index).reference,blob,system)
}
public fun pause<C>(p:&mut Product<C>,control:&mut Control,version:u64){catalog::lifecycle(p,control,version,2)}
public fun archive<C>(p:&mut Product<C>,control:&mut Control,version:u64){catalog::lifecycle(p,control,version,3)}
public fun resume<C>(p:&mut Product<C>,control:&mut Control,cfg:&Config<C>,version:u64,system:&System){assert_current(p,cfg,version,system);catalog::lifecycle(p,control,version,1)}
public fun assert_current<C>(p:&Product<C>,cfg:&Config<C>,version:u64,system:&System){
    assert_catalog(cfg,system);let c=certificate(p,version);let old=if(c.header.catalog_generation==current(cfg).body.generation)current(cfg) else historical(cfg,c.header.catalog_generation);assert!(object::id(old)==c.header.catalog && old.commitment==c.header.catalog_commitment && old.body.config==object::id(cfg) && old.body.system==object::id(system),EIdentity);let v=catalog::published(p,version);catalog::assert_publication_economics(p,v);assert!(c.header.config==object::id(cfg) && c.header.product==object::id(p) && c.header.version==version && c.policy==catalog::policy_hash(v) && storage::hash(&c.header.manifest)==catalog::manifest(v) && storage::hash(&c.header.living)==catalog::configuration(v),EIdentity);available(c,system)
}
fun approve(c:&Certificate,id:vector<u8>){let mut i=0;while(i < paged_store::length(&c.rows)){let r=paged_store::get(&c.rows,i);if(r.protected && r.scope==id)return;i=i+1};abort EScope}
/// Seal-compatible approval: exact product/version/asset ID and current actor.
public fun seal_approve<C>(id:vector<u8>,p:&Product<C>,cfg:&Config<C>,version:u64,system:&System,clock:&Clock,ctx:&TxContext){
    assert_current(p,cfg,version,system);let v=catalog::published(p,version);catalog::assert_runtime_access(p,cfg,version,catalog::policy_hash(v),catalog::manifest(v),economics::revision(cfg),economics::commitment(cfg),clock,ctx);approve(certificate(p,version),id)
}
public fun seal_approve_pack<C>(id:vector<u8>,p:&Product<C>,maker:&Product<C>,cfg:&Config<C>,version:u64,system:&System,clock:&Clock,ctx:&TxContext){
    assert_current(p,cfg,version,system);let v=catalog::published(p,version);let parent_version=catalog::publication_parent_version(&catalog::publication(v).destroy_some());assert_current(maker,cfg,parent_version,system);catalog::assert_runtime_pack(p,maker,parent_version,version,cfg,catalog::policy_hash(v),catalog::manifest(v),economics::revision(cfg),economics::commitment(cfg),clock,ctx);approve(certificate(p,version),id)
}

public fun register<C>(c:&mut Config<C>,a:&mut Admin,expected:u64,hash:vector<u8>,p:&sui::package::Publisher,cap:&sui::package::UpgradeCap){
    economics::register_role<C,ReleaseInstaller1,ReleaseRevision3>(c,a,expected,hash,1,ReleaseInstaller1{},ReleaseRevision3{},p,cap)
}
public(package) fun attest_role(p:&sui::package::Publisher,cap:&sui::package::UpgradeCap,ctx:&mut TxContext):ID{soulidity_foundation::package_roles::attest_role(1,ReleaseInstaller1{},ReleaseRevision3{},p,cap,ctx)}
#[test_only]
public fun publisher_for_testing(ctx:&mut TxContext):sui::package::Publisher{sui::package::test_claim(MAKER_RELEASE{},ctx)}
public fun register_from_certificate<C>(cfg:&mut Config<C>,admin:&mut Admin,expected:u64,hash:vector<u8>,certificate:&soulidity_foundation::package_roles::RoleCertificate<ReleaseInstaller1,ReleaseRevision3>){economics::register_role_from_certificate(cfg,admin,expected,hash,1,ReleaseInstaller1{},ReleaseRevision3{},certificate)}
/// Private release and creator values never leave their defining modules.
public(package) fun new_service<C>(release:&soulidity_foundation::package_roles::RoleCertificate<ReleaseInstaller1,ReleaseRevision3>,creator:&soulidity_foundation::package_roles::RoleCertificate<catalog::CreatorAuthority1,catalog::CreatorRevision3>,primary:u16,secondary:u16,fixed:u64,recipient:address,system:&System,source:vector<u8>,abi:vector<u8>,ctx:&mut TxContext):(Config<C>,Admin){
    let(mut cfg,mut admin)=catalog::new_service(release,creator,ReleaseInstaller1{},ReleaseRevision3{},primary,secondary,fixed,recipient,ctx);
    let revision=economics::revision(&cfg);let hash=economics::commitment(&cfg);install(&mut cfg,&mut admin,system,source,abi,revision,hash,ctx);(cfg,admin)
}

public fun activate<C>(cfg:&mut Config<C>,admin:&mut Admin,system:&System,expected:u64,hash:vector<u8>){
    economics::assert_install_admin(cfg,admin,expected,hash);economics::assert_role_types<C,ReleaseInstaller1,ReleaseRevision3>(cfg,1);catalog::assert_current_writer(cfg);
    let c=current(cfg);let s=economics::release_snapshot(cfg).destroy_some();
    assert!(c.body.config==object::id(cfg) && c.body.system==object::id(system) && c.body.original==object::id_from_address(type_name::original_id<ReleaseInstaller1>()) && c.body.callable==object::id_from_address(type_name::defining_id<ReleaseRevision3>()) && c.commitment==computed(c) && economics::release_catalog(&s)==object::id(c) && economics::release_generation(&s)==c.body.generation && economics::release_commitment(&s)==c.commitment,EIdentity);
    let id=object::id(c);let authorization=catalog::authorize_activation(cfg,admin,expected,hash);economics::activate_manufacturing_identity<C,ReleaseInstaller1,ReleaseRevision3>(cfg,admin,expected,hash,ReleaseInstaller1{},ReleaseRevision3{},authorization,id)
}

/// Synthetic initial role fixture only; production registration uses Publisher/Cap.
#[test_only]
public fun bootstrap_for_testing<C>(cfg:&mut Config<C>,admin:&mut economics::Admin){economics::pin_initial_role_for_testing(cfg,admin,1,ReleaseInstaller1{},ReleaseRevision3{})}

/// Real current custody, not certification-time reference end epochs. A renewal
/// is re-read when a new Session guard is minted. Once funded, the same Walrus
/// epoch must reach finish; a mutation of System requires a new transaction.
public struct BlobAvailability has drop {object:ID,blob_id:u256,certified_epoch:u32,end_epoch:u32}
fun blob_availability(blob:&Blob):BlobAvailability{BlobAvailability{object:object::id(blob),blob_id:walrus::blob::blob_id(blob),certified_epoch:*walrus::blob::certified_epoch(blob).borrow(),end_epoch:walrus::blob::end_epoch(blob)}}
public(package) fun availability<C,T:key>(p:&Product<C>,target:&T,cfg:&Config<C>,snapshot:soulidity_origin_protocol::producer_origin::Snapshot,system:&System):catalog::Availability{
 let version=soulidity_origin_protocol::producer_origin::version(&snapshot);assert_current(p,cfg,version,system);let c=certificate(p,version);let mut blobs=vector[];let living=blob_custody::borrow(&c.custody.id,0,0);let manifest=blob_custody::borrow(&c.custody.id,1,0);let mut end_epoch=walrus::blob::end_epoch(living);end_epoch=end_epoch.min(walrus::blob::end_epoch(manifest));blobs.push_back(blob_availability(living));blobs.push_back(blob_availability(manifest));let mut i=0;while(i < paged_store::length(&c.rows)){let blob=blob_custody::borrow(&c.custody.id,2,i);end_epoch=end_epoch.min(walrus::blob::end_epoch(blob));blobs.push_back(blob_availability(blob));i=i+1};catalog::availability(p,target,cfg,snapshot,object::id(system),system::epoch(system),end_epoch,c.header.catalog,c.header.catalog_commitment,object::id(c),c.commitment,policy::hash_bytes(bcs::to_bytes(&blobs)))
}
