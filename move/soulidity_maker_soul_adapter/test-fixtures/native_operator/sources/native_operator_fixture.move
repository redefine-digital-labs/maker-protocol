#[test_only]
/// Original application_operator source is retained exactly; fixture defining IDs
/// are unpublished 0x0. This verifies nominal stored-operator refusal, not chain lineage.
module soulidity_v1::native_operator_fixture;
use soulidity_custody::lifecycle;
use soulidity_v1::application_operator::{Self as operator,ApplicationOperator,ApplicationRevision1};
use soulidity_foundation::economics::{Self,Config};
use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,Product,Version,Session};
use soulidity_maker_manufacturing::maker_factory as factory;
use soulidity_standard::soul::{Self as standard,Soul};
use soulidity_custody::lifecycle::{Construction};
use soulidity_origin_protocol::producer_origin as origin;
use soulidity_maker_admission::maker_issuance as admission;
use soulidity_application::character::{Self,Draft};
use sui::coin::Coin;
use sui::clock::Clock;
use walrus::system::System;
public struct NativeFixture {construction:Construction,session:Session,draft:Draft}
public fun with_execution(v:Version):Version{catalog::with_execution<ApplicationOperator,ApplicationRevision1,Soul>(v,operator::operator(),operator::revision())}
public fun begin<C>(maker:&mut Product<C>,cfg:&mut Config<C>,attempt:vector<u8>,expiry:u64,payment:Coin<C>,clock:&Clock,system:&System,ctx:&mut TxContext):NativeFixture{
 let v=*catalog::published(maker,1);let hash=catalog::policy_hash(&v);
 let(request,witness)=factory::request_with_witness<C,ApplicationOperator,ApplicationRevision1,Soul>(maker,cfg,1,hash,std::string::utf8(b"Native-operator-fixture"),attempt,expiry,operator::operator(),operator::revision(),system,clock,ctx);let snapshot=origin::snapshot(&request);let mut construction=lifecycle::new(witness,maker,request,ctx);
 let mut session=factory::begin(maker,lifecycle::construction_ref(&construction),cfg,snapshot,payment,operator::operator(),operator::revision(),system,clock,ctx);let paid=catalog::session_receipt(&session);let action=catalog::take_action(&mut session,maker,lifecycle::construction_ref(&construction),ctx);
 let resale=soulidity_maker_terms::maker_resale::snapshot(object::id(cfg),object::id(maker),1,hash,catalog::creator(maker),catalog::soul_rates(&v),ctx);let profile=catalog::assembly_profile(maker,1);let metadata=character::genesis_hash(object::id(cfg),object::id(maker),1,catalog::manifest(&v),catalog::configuration(&v),profile,catalog::required_parts(&v),catalog::adapters(&v),*catalog::scene(&v),resale,catalog::beneficiary(&v),ctx);
 let genesis=admission::authorize_manufacturing_genesis_action(cfg,maker,lifecycle::construction_ref(&construction),action,paid,metadata,operator::operator(),operator::revision(),ctx);let draft=character::initialize_creation(genesis,lifecycle::construction_mut(&mut construction),object::id(cfg),object::id(maker),1,catalog::manifest(&v),catalog::configuration(&v),profile,catalog::required_parts(&v),catalog::adapters(&v),*catalog::scene(&v),resale,catalog::beneficiary(&v),ctx);NativeFixture{construction,session,draft}
}
public fun root_mut(f:&mut NativeFixture):&mut soulidity_standard::soul::Creation{lifecycle::construction_mut(&mut f.construction)}
/// Only for typing the unreachable tail of expected-abort operator probes. It
/// retains Character completion checks and cannot complete an empty fixture.
public fun finish<C>(f:NativeFixture,cfg:&Config<C>,clock:&Clock,system:&System,ctx:&TxContext):ID{
 let NativeFixture{mut construction,session,draft}=f;character::finalize_creation(draft,lifecycle::construction_mut(&mut construction),ctx.sender(),ctx);let completion=factory::finish(session,lifecycle::construction_ref(&construction),cfg,operator::operator(),operator::revision(),system,clock,ctx);lifecycle::deliver(construction,completion,ctx.sender(),ctx)
}
