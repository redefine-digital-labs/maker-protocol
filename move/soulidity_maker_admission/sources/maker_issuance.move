/// Linear application admission proofs. Copyable quotes are data, never authority.
/// Native producers construct these only after actual primary settlement.
module soulidity_maker_admission::maker_issuance;
use std::type_name::{Self,TypeName};
use soulidity_foundation::economics::{Self,Config,PrimaryReceipt};
use soulidity_standard::soul::{Self,Soul};
use soulidity_model::policy;
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
public fun authorize_contribution<C,W:drop,R:drop,P:key>(cfg:&Config<C>,w:W,r:R,p:&P,root:&Soul,version:u64,policy:vector<u8>,payment:PrimaryReceipt,ctx:&TxContext):Contribution{
    economics::assert_business<C,W,R>(cfg,2,w,r);producer<W,P>();policy::assert_hash(&policy);
    assert!(economics::primary_policy_config(&economics::primary_receipt_policy(&payment))==object::id(cfg) && economics::primary_receipt_subject(&payment)==object::id(root) && economics::primary_receipt_actor(&payment)==ctx.sender() && economics::primary_receipt_revenue(&payment)==option::some(object::id(p)) && economics::primary_receipt_commitment(&payment)==policy,EIdentity);
    Contribution{root:object::id(root),product:object::id(p),version,policy,actor:ctx.sender(),payment}
}
public fun consume_contribution(c:Contribution,root:&Soul,ctx:&TxContext):(ID,u64,vector<u8>,PrimaryReceipt){
    let Contribution{root:id,product,version,policy,actor,payment}=c;
    assert!(id==object::id(root) && actor==ctx.sender(),EIdentity);(product,version,policy,payment)
}
