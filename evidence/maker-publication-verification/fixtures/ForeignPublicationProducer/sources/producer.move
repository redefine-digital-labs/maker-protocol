/// Independent producer of canonical publication formats and exact-target components.
/// It attests its own component supply. It does not claim native Maker manufacture.
module foreign_publication_producer::producer;
use soulidity_model::policy::{Self,Definition,Source};
use soulidity_model::components::{Self,Permit};
use soulidity_foundation::economics::{Self,Config,MarketPolicy,PrimaryPolicy};
use soulidity_content_kinds::content_kind_registry::KindRegistry;
use soulidity_content_kinds::document_policy;
use soulidity_maker_publication::output_data::{Self,Policy};
public struct Product has key,store {id:UID,protocol:ID,definition:Definition,market:MarketPolicy,primary:PrimaryPolicy,creator:address,issued:u64}
public struct Target has key,store {id:UID}
public struct PolicyProducer has drop {}
public struct ComponentProducer has drop {}
public fun create<C>(cfg:&Config<C>,definition:Definition,ctx:&mut TxContext):Product{
    Product{id:object::new(ctx),protocol:object::id(cfg),definition,market:economics::market_policy(cfg,0,ctx),primary:economics::primary_policy(cfg),creator:ctx.sender(),issued:0}
}
public fun new_target(ctx:&mut TxContext):Target{Target{id:object::new(ctx)}}
public fun preview(p:&Product):Source{policy::source(PolicyProducer{},p,object::id(p),1,1,p.protocol,0,p.creator,p.market,p.primary,p.definition)}
public fun authorize(p:&mut Product,target:&Target):Permit{
    assert!(p.issued < policy::supply(&p.definition),1);p.issued=p.issued+1;let source=preview(p);
    components::authorize(ComponentProducer{},p,target,source)
}
public fun output_policy(registry:&KindRegistry,renderer:vector<u8>):Policy{
    output_data::policy(b"foreign",false,vector[],renderer,true,vector[],vector[
        output_data::initial_rule(registry,0,document_policy::soul_doc_name(),3,0),
        output_data::initial_rule(registry,1,document_policy::memory_name(),3,0)])
}
public fun issued(p:&Product):u64{p.issued}
#[test_only]
public fun authorize_source(p:&Product,target:&Target,source:Source):Permit{components::authorize(ComponentProducer{},p,target,source)}
