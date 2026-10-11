/// Source is copyable metadata. Only a designated producer can authorize its
/// materialization, and only one exact target can consume the linear permit.
module soulidity_model::components;
use std::type_name;
use sui::event;
use soulidity_model::policy::{Self,Source};

const EAuthority:u64=1;
const ESource:u64=2;
const ETarget:u64=3;
const ERights:u64=4;
public struct Permit {source:Source,target:ID}
public struct Item has key,store {id:UID,source:Source}
public struct ItemIssued has copy,drop {id:ID,product:ID,style_hash:vector<u8>}

/// The producer must keep ComponentProducer construction private and attest
/// its own supply/payment/licence rules. Preview metadata is not this marker.
/// Native Catalog creates this only after its private supply reservation;
/// existing issuer still validates paid access/Complete before calling it.
public fun authorize<W:drop,P:key,T:key>(witness:W,product:&P,target:&T,source:Source):Permit{
    let w=type_name::with_original_ids<W>();let p=type_name::with_original_ids<P>();
    assert!(!w.is_primitive() && w.address_string()==p.address_string() && w.module_string()==p.module_string()
        && *w.datatype_string().as_bytes()==b"ComponentProducer",EAuthority);let _=witness;
    assert!(policy::source_product(&source)==object::id(product)
        && policy::source_type(&source)==type_name::with_defining_ids<P>(),ESource);
    let target=object::id(target);
    assert!(policy::rights(&source)<=policy::transferable(),ERights);
    Permit{source,target}
}
public fun preview(p:&Permit):&Source{&p.source}
public fun target(p:&Permit):ID{p.target}
/// No abilities permit cannot be copied, discarded, stored or carried to a
/// later transaction. Ref/Bound create no free object. The application consumes
/// this permit, so returning copyable metadata never grants a second install.
public fun materialize(p:Permit,target:ID,ctx:&mut TxContext):(Source,Option<Item>){
    assert!(p.target==target,ETarget);let Permit{source,target:_}=p;
    let item=if(policy::rights(&source)==policy::transferable())option::some(issue_item(source,ctx)) else option::none();
    (source,item)
}
fun issue_item(source:Source,ctx:&mut TxContext):Item{
    assert!(policy::rights(&source)==policy::transferable(),ERights);
    let item=Item{id:object::new(ctx),source};
    event::emit(ItemIssued{id:object::id(&item),product:policy::source_product(&source),style_hash:policy::source_hash(&source)});item
}
public fun source(item:&Item):&Source{&item.source}
