/// Linear application admission proofs. Copyable quotes are data, never authority.
/// Native producers construct these only after actual primary settlement.
module soulidity_maker_admission::maker_issuance;
use soulidity_origin_protocol::producer_origin::{Self as origin,PaidAction};
use std::type_name::{Self,TypeName};
use soulidity_foundation::economics::{Self,Config,PrimaryReceipt};
use soulidity_standard::soul::{Self,Soul};
use soulidity_model::policy;
use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,Product,ManufacturingProducer,SoulProducer};
const EAuthority:u64=1;const EIdentity:u64=2;
/// The configured native binder authenticates the operation lineage at admission.
/// This does not attest current custody or provide an automatic transfer hook.
public struct Binding {config:ID,operator:TypeName}
public struct Genesis {config:ID,root:ID,source:ID,version:u64,policy:vector<u8>,actor:address,metadata:vector<u8>,operator:TypeName}
public struct Contribution {root:ID,product:ID,version:u64,policy:vector<u8>,actor:address,payment:PrimaryReceipt}
public fun bind<C,W:drop,R:drop,O:drop>(cfg:&Config<C>,_w:W,_r:R,_operator:O):Binding{
    economics::assert_role_types<C,W,R>(cfg,0);
    let o=type_name::with_original_ids<O>();let w=type_name::with_original_ids<W>();
    assert!(!o.is_primitive() && o.address_string()==w.address_string() && *o.module_string().as_bytes()==b"application_operator" && *o.datatype_string().as_bytes()==b"ApplicationOperator",EAuthority);
    Binding{config:object::id(cfg),operator:o}
}
fun producer<W,P>(){
    let w=type_name::with_original_ids<W>();let p=type_name::with_original_ids<P>();
    assert!(!w.is_primitive() && !p.is_primitive() && w.address_string()==p.address_string() && w.module_string()==p.module_string(),EAuthority)
}
#[test_only]
public fun authorize_genesis<C,W:drop,R:drop,P:key>(cfg:&Config<C>,w:W,r:R,p:&P,root:&Soul,binding:Binding,metadata:vector<u8>,ctx:&TxContext):Genesis{
    economics::assert_business<C,W,R>(cfg,2,w,r);producer<W,P>();policy::assert_hash(&metadata);
    let Binding{config,operator}=binding;let origin=soul::origin(root);
    assert!(config==object::id(cfg) && soul::source(&origin)==object::id(p) && soul::source_type(&origin)==type_name::with_defining_ids<P>() && soul::minted_by(&origin)==ctx.sender(),EIdentity);
    Genesis{config,root:object::id(root),source:object::id(p),version:soul::source_version(&origin),policy:soul::source_hash(&origin),actor:ctx.sender(),metadata,operator}
}
public fun consume_genesis(g:Genesis,root:&Soul,metadata:vector<u8>,ctx:&TxContext):(ID,TypeName){
    let Genesis{config,root:id,source,version,policy,actor,metadata:expected,operator}=g;let origin=soul::origin(root);
    assert!(id==object::id(root) && source==soul::source(&origin) && version==soul::source_version(&origin) && policy==soul::source_hash(&origin) && actor==ctx.sender() && expected==metadata,EIdentity);(config,operator)
}
#[test_only]
public fun authorize_contribution<C,W:drop,R:drop,P:key>(cfg:&Config<C>,w:W,r:R,p:&P,root:&Soul,version:u64,policy:vector<u8>,payment:PrimaryReceipt,ctx:&TxContext):Contribution{
    economics::assert_business<C,W,R>(cfg,2,w,r);producer<W,P>();policy::assert_hash(&policy);
    assert!(economics::primary_policy_config(&economics::primary_receipt_policy(&payment))==object::id(cfg) && economics::primary_receipt_subject(&payment)==object::id(root) && economics::primary_receipt_actor(&payment)==ctx.sender() && economics::primary_receipt_revenue(&payment)==option::some(object::id(p)) && economics::primary_receipt_commitment(&payment)==policy,EIdentity);
    Contribution{root:object::id(root),product:object::id(p),version,policy,actor:ctx.sender(),payment}
}
public fun consume_contribution(c:Contribution,root:&Soul,ctx:&TxContext):(ID,u64,vector<u8>,PrimaryReceipt){
    let Contribution{root:id,product,version,policy,actor,payment}=c;
    assert!(id==object::id(root) && actor==ctx.sender(),EIdentity);(product,version,policy,payment)
}

/// Sealed actual-funded Maker action and separate actual Native Binding.
public fun authorize_genesis_action<C,A:drop,R:drop,P:key>(cfg:&Config<C>,p:&P,root:&Soul,binding:Binding,action:PaidAction,payment:PrimaryReceipt,metadata:vector<u8>,a:A,r:R,ctx:&TxContext):Genesis{
 economics::assert_primary(cfg);let(snapshot,receipt)=origin::consume_action(action,a,r,root,0,ctx);economics::assert_primary_snapshot(cfg,origin::config(&snapshot),origin::revision(&snapshot),origin::commitment(&snapshot));policy::assert_hash(&metadata);
 assert!(receipt==policy::hash_bytes(std::bcs::to_bytes(&payment)) && origin::source(&snapshot)==object::id(p) && origin::source_type(&snapshot)==type_name::with_defining_ids<P>() && economics::primary_receipt_subject(&payment)==object::id(root) && economics::primary_receipt_actor(&payment)==ctx.sender() && economics::primary_receipt_revenue(&payment)==option::some(object::id(p)),EIdentity);
 let Binding{config,operator}=binding;let actual=soul::origin(root);assert!(config==object::id(cfg) && operator==type_name::with_original_ids<A>() && soul::source(&actual)==object::id(p) && soul::source_type(&actual)==origin::source_type(&snapshot) && soul::source_version(&actual)==origin::version(&snapshot) && soul::source_hash(&actual)==origin::policy(&snapshot) && soul::minted_by(&actual)==ctx.sender(),EIdentity);
 Genesis{config,root:object::id(root),source:object::id(p),version:origin::version(&snapshot),policy:origin::policy(&snapshot),actor:ctx.sender(),metadata,operator}
}
public fun authorize_contribution_action<C,A:drop,R:drop,P:key>(cfg:&Config<C>,p:&P,root:&Soul,action:PaidAction,payment:PrimaryReceipt,a:A,r:R,ctx:&TxContext):Contribution{
 // Snapshot validation below already includes full Primary validation of this immutable Config.
 let(snapshot,receipt)=origin::consume_action(action,a,r,root,1,ctx);economics::assert_primary_snapshot(cfg,origin::config(&snapshot),origin::revision(&snapshot),origin::commitment(&snapshot));
 assert!(receipt==policy::hash_bytes(std::bcs::to_bytes(&payment)) && origin::source(&snapshot)==object::id(p) && origin::source_type(&snapshot)==type_name::with_defining_ids<P>() && economics::primary_receipt_subject(&payment)==object::id(root) && economics::primary_receipt_actor(&payment)==ctx.sender() && economics::primary_receipt_revenue(&payment)==option::some(object::id(p)) && economics::primary_receipt_commitment(&payment)==origin::policy(&snapshot),EIdentity);
 Contribution{root:object::id(root),product:object::id(p),version:origin::version(&snapshot),policy:origin::policy(&snapshot),actor:ctx.sender(),payment}
}

/// Only the canonical, actual funded manufacturing producer can enter this path.
/// Receipt and snapshot copies alone cannot create either linear admission proof.
fun consume_manufacturing_action<C,A:drop,R:drop>(cfg:&Config<C>,p:&Product<C>,root:&Soul,action:PaidAction,payment:&PrimaryReceipt,a:A,r:R,operation:u8,ctx:&TxContext):origin::Snapshot{
    economics::assert_manufacturing_primary(cfg);catalog::assert_current_writer(cfg);
    assert!(origin::action_producer(&action)==type_name::with_defining_ids<ManufacturingProducer>(),EAuthority);
    let(snapshot,receipt)=origin::consume_action(action,a,r,root,operation,ctx);
    economics::assert_manufacturing_snapshot(cfg,origin::config(&snapshot),origin::revision(&snapshot),origin::commitment(&snapshot));
    let v=catalog::published(p,origin::version(&snapshot));let primary=catalog::version_primary(v);
    assert!(origin::producer(&snapshot)==type_name::with_defining_ids<SoulProducer>() && origin::source(&snapshot)==object::id(p) && origin::source_type(&snapshot)==type_name::with_defining_ids<Product<C>>() && catalog::protocol(p)==object::id(cfg) && catalog::policy_hash(v)==origin::policy(&snapshot),EIdentity);
    assert!(receipt==policy::hash_bytes(std::bcs::to_bytes(payment)) && economics::primary_policy_hash(&economics::primary_receipt_policy(payment))==economics::primary_policy_hash(&primary) && economics::primary_policy_config(&primary)==object::id(cfg) && economics::primary_receipt_subject(payment)==object::id(root) && economics::primary_receipt_actor(payment)==ctx.sender() && economics::primary_receipt_revenue(payment)==option::some(object::id(p)) && economics::primary_receipt_commitment(payment)==origin::policy(&snapshot) && economics::primary_receipt_revision(payment)==origin::revision(&snapshot) && economics::primary_receipt_attempt(payment)==origin::attempt(&snapshot) && economics::primary_receipt_beneficiary(payment)==catalog::beneficiary(v),EIdentity);
    snapshot
}
/// Genuine paid action -> Genesis. Existing Native Binding APIs retain their path.
public fun authorize_manufacturing_genesis_action<C,A:drop,R:drop>(cfg:&Config<C>,p:&Product<C>,root:&Soul,action:PaidAction,payment:PrimaryReceipt,metadata:vector<u8>,a:A,r:R,ctx:&TxContext):Genesis{
    let snapshot=consume_manufacturing_action(cfg,p,root,action,&payment,a,r,0,ctx);policy::assert_hash(&metadata);assert!(catalog::parent(p).is_none(),EIdentity);
    let actual=soul::origin(root);assert!(soul::producer(&actual)==origin::producer(&snapshot) && soul::source(&actual)==object::id(p) && soul::source_type(&actual)==origin::source_type(&snapshot) && soul::source_version(&actual)==origin::version(&snapshot) && soul::source_hash(&actual)==origin::policy(&snapshot) && soul::minted_by(&actual)==ctx.sender(),EIdentity);
    Genesis{config:object::id(cfg),root:object::id(root),source:object::id(p),version:origin::version(&snapshot),policy:origin::policy(&snapshot),actor:ctx.sender(),metadata,operator:type_name::with_original_ids<A>()}
}
/// Genuine contribution settlement retains the authentic receipt for Character.
public fun authorize_manufacturing_contribution_action<C,A:drop,R:drop>(cfg:&Config<C>,p:&Product<C>,root:&Soul,action:PaidAction,payment:PrimaryReceipt,a:A,r:R,ctx:&TxContext):Contribution{
    let snapshot=consume_manufacturing_action(cfg,p,root,action,&payment,a,r,1,ctx);
    Contribution{root:object::id(root),product:object::id(p),version:origin::version(&snapshot),policy:origin::policy(&snapshot),actor:ctx.sender(),payment}
}
