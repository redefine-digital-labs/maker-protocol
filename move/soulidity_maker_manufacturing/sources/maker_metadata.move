/// Bounded creator metadata ingress; no asset issuance or legacy public publisher.
module soulidity_maker_manufacturing::maker_metadata;
use std::bcs;
use std::hash;
use sui::dynamic_object_field as dof;
use sui::event;
use walrus::system::System;
use walrus::blob::Blob;
use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,Product,Control,Version};
use soulidity_foundation::economics::{Self,Config};
use soulidity_maker_manufacturing::maker_release::{Self as release,Author,Draft};
use soulidity_model::policy::{Definition,Adapter};
use soulidity_visual::visual::Fragment;
use soulidity_model::material_policy::Terms;
const EActor:u64=1;const EIdentity:u64=2;const ERevision:u64=3;const EBounds:u64=4;const EHash:u64=5;
// Transaction ingress bound, deliberately smaller than pure-input16KiB.
const CHUNK_BYTES:u64=8192;const CHUNK_ROWS:u64=32;const VERSION_BYTES:u64=196608;
public struct VersionKey has copy,drop,store {}
public struct Value has key,store {id:UID,version:Version}
/// Creator-owned only; production transport checks actual mutable Control as well.
public struct Metadata has key {id:UID,actor:address,product:ID,next_version:u64,config:ID,config_revision:u64,config_hash:vector<u8>,system:ID,revision:u64,byte_bound:u64,stream:vector<u8>}
public struct StreamStep has drop {domain:vector<u8>,metadata:ID,revision:u64,previous:vector<u8>,kind:u8,index:u64,payload:vector<u8>}
public struct Changed has copy,drop {metadata:ID,actor:address,product:ID,revision:u64,byte_bound:u64,stream:vector<u8>}
public struct Cancelled has copy,drop {metadata:ID,actor:address,product:ID}
public fun start<C>(p:&Product<C>,control:&mut Control,cfg:&Config<C>,expected_version:u64,seed:Version,system:&System,ctx:&mut TxContext):Metadata{
    catalog::assert_control(p,control);release::assert_catalog(cfg,system);assert!(catalog::protocol(p)==object::id(cfg),EIdentity);assert!(catalog::current_version(p)==expected_version,ERevision);catalog::assert_unpublished(&seed);
    let bytes=bcs::to_bytes(&seed).length();assert!(bytes<=CHUNK_BYTES,EBounds);let seed_hash=catalog::policy_hash(&seed);let value=Value{id:object::new(ctx),version:seed};let mut m=Metadata{id:object::new(ctx),actor:ctx.sender(),product:object::id(p),next_version:expected_version+1,config:object::id(cfg),config_revision:economics::revision(cfg),config_hash:economics::commitment(cfg),system:object::id(system),revision:0,byte_bound:bytes,stream:seed_hash};dof::add(&mut m.id,VersionKey{},value);m.stream=step(&m,0,0,bcs::to_bytes(&vector[m.product,m.config,m.system]));emit(&m);m
}
public fun deliver(m:Metadata,ctx:&TxContext){assert!(m.actor==ctx.sender(),EActor);transfer::transfer(m,ctx.sender())}
public fun revision(m:&Metadata):u64{m.revision}
/// Conservative serialized-size bound; includes chunk prefixes and initial hash.
public fun byte_bound(m:&Metadata):u64{m.byte_bound}
public fun stream_commitment(m:&Metadata):vector<u8>{m.stream}
public fun version(m:&Metadata):&Version{let v:&Value=dof::borrow(&m.id,VersionKey{});&v.version}
/// Canonical semantic hash, computed on demand, distinct from the stream commitment.
public fun policy_hash(m:&Metadata):vector<u8>{catalog::unpublished_hash(version(m))}
fun guard<C>(m:&Metadata,p:&Product<C>,control:&mut Control,cfg:&Config<C>,system:&System,expected:u64,ctx:&TxContext){
    assert!(m.actor==ctx.sender(),EActor);catalog::assert_control(p,control);release::assert_catalog(cfg,system);assert!(m.revision==expected && m.next_version==catalog::current_version(p)+1,ERevision);assert!(m.product==object::id(p) && m.config==object::id(cfg) && catalog::protocol(p)==m.config && m.config_revision==economics::revision(cfg) && m.config_hash==economics::commitment(cfg) && m.system==object::id(system),EIdentity)
}
fun chunk<T:copy+drop+store>(rows:&vector<T>):vector<u8>{let bytes=bcs::to_bytes(rows);assert!(!rows.is_empty() && rows.length()<=CHUNK_ROWS && bytes.length()<=CHUNK_BYTES,EBounds);bytes}
fun value_mut(m:&mut Metadata):&mut Version{let v:&mut Value=dof::borrow_mut(&mut m.id,VersionKey{});&mut v.version}
fun step(m:&Metadata,kind:u8,index:u64,payload:vector<u8>):vector<u8>{hash::sha2_256(bcs::to_bytes(&StreamStep{domain:b"soulidity/metadata-stream/v1",metadata:object::id(m),revision:m.revision,previous:m.stream,kind,index,payload:hash::sha2_256(payload)}))}
fun changed(m:&mut Metadata,kind:u8,index:u64,payload:vector<u8>){m.byte_bound=m.byte_bound+payload.length();assert!(m.byte_bound<=VERSION_BYTES,EBounds);m.revision=m.revision+1;m.stream=step(m,kind,index,payload);emit(m)}
fun emit(m:&Metadata){event::emit(Changed{metadata:object::id(m),actor:m.actor,product:m.product,revision:m.revision,byte_bound:m.byte_bound,stream:m.stream})}
public fun append_definitions<C>(m:&mut Metadata,p:&Product<C>,control:&mut Control,cfg:&Config<C>,definitions:vector<Definition>,system:&System,expected:u64,ctx:&TxContext){guard(m,p,control,cfg,system,expected,ctx);let payload=chunk(&definitions);catalog::append_definitions(value_mut(m),definitions);changed(m,1,0,payload)}
public fun extend_definition<C>(m:&mut Metadata,p:&Product<C>,control:&mut Control,cfg:&Config<C>,index:u64,fragments:vector<Fragment>,system:&System,expected:u64,ctx:&TxContext){guard(m,p,control,cfg,system,expected,ctx);let payload=chunk(&fragments);catalog::extend_definition(value_mut(m),index,fragments);changed(m,2,index,payload)}
public fun append_adapters<C>(m:&mut Metadata,p:&Product<C>,control:&mut Control,cfg:&Config<C>,adapters:vector<Adapter>,system:&System,expected:u64,ctx:&TxContext){guard(m,p,control,cfg,system,expected,ctx);let payload=chunk(&adapters);catalog::append_adapters(value_mut(m),adapters);changed(m,3,0,payload)}
public fun append_physical<C>(m:&mut Metadata,p:&Product<C>,control:&mut Control,cfg:&Config<C>,terms:vector<Terms>,system:&System,expected:u64,ctx:&TxContext){guard(m,p,control,cfg,system,expected,ctx);let payload=chunk(&terms);catalog::append_physical(value_mut(m),terms);changed(m,4,0,payload)}
/// Freeze exact rebuilt policy and enter the existing actual-Blob custody publisher.
public fun begin_publication<C>(m:Metadata,p:&Product<C>,control:&mut Control,cfg:&Config<C>,expected:u64,hash:vector<u8>,author:Author,living:Blob,manifest:Blob,system:&System,ctx:&mut TxContext):Draft{
    guard(&m,p,control,cfg,system,expected,ctx);let finalized=catalog::finalize_metadata(version(&m));assert!(bcs::to_bytes(&finalized).length()<=VERSION_BYTES,EBounds);assert!(hash==catalog::policy_hash(&finalized),EHash);let Metadata{mut id,actor:_,product:_,next_version,config:_,config_revision:_,config_hash:_,system:_,revision:_,byte_bound:_,stream:_}=m;let Value{id:value_id,version:_}=dof::remove(&mut id,VersionKey{});value_id.delete();id.delete();release::begin(p,control,cfg,next_version-1,finalized,author,living,manifest,system,ctx)
}
/// Metadata holds no paid entitlement/issued asset/Blob; author can always discard.
public fun cancel(m:Metadata,ctx:&TxContext){assert!(m.actor==ctx.sender(),EActor);event::emit(Cancelled{metadata:object::id(&m),actor:m.actor,product:m.product});let Metadata{mut id,actor:_,product:_,next_version:_,config:_,config_revision:_,config_hash:_,system:_,revision:_,byte_bound:_,stream:_}=m;let Value{id:value_id,version:_}=dof::remove(&mut id,VersionKey{});value_id.delete();id.delete()}
