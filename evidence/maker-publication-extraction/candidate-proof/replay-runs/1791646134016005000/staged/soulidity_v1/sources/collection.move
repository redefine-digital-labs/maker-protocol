/// Permanent membership, immutable collection policy, and a locked native Kiosk Right.
module soulidity_v1::collection;
/// Private values are constructed and consumed only inside this producer.
public struct CollectionAuthority1 has drop {}
/// Retained for compatible type origins; current business uses Revision3.
public struct CollectionRevision1 has drop {}
public struct CollectionRevision2 has drop {}
public struct CollectionRevision3 has drop {}

use std::string::String;
use std::bcs;
use sui::table::{Self,Table};
use sui::package::{Self,Publisher};
use sui::display;
use sui::kiosk::{Self,Kiosk,PurchaseCap};
use sui::transfer_policy::{Self,TransferPolicy,TransferPolicyCap};
use sui::dynamic_object_field as dof;
use sui::coin::{Self,Coin};
use sui::clock::{Self,Clock};
use sui::event;
use soulidity_custody::account::{Self as custody,Account};
use soulidity_foundation::economics::{Self,Config};
use soulidity_model::policy;
use soulidity_application::character::{Self as soul};
use soulidity_standard::soul::Soul;
const EPolicy:u64=1;const EOwner:u64=2;const EBinding:u64=3;const ERevision:u64=4;
const ESupply:u64=5;const EMember:u64=6;const EState:u64=7;const EQuote:u64=8;
public struct COLLECTION has drop {}
public struct Factory has key {id:UID,publisher:Publisher,policy:ID,cap:TransferPolicyCap<Right>}
public struct Rule has drop {}
public struct RuleConfig has drop,store {}
public struct Collection has key {id:UID,schema_version:u16,protocol:ID,creator:address,right:ID,right_hash:vector<u8>,policy:ID,extra:u16,tradeable:bool,max_supply:Option<u64>,floor:Option<u128>,supply:u64,members:Table<ID,u64>,revision:u64,holder:address,kiosk:ID,epoch:u64}
public struct Right has key,store {id:UID,schema_version:u16,collection:ID,protocol:ID,creator:address,name:String,description:String,image_url:String}
public struct Snapshot has copy,drop,store {collection:ID,protocol:ID,creator:address,right:ID,right_hash:vector<u8>,policy:ID,extra:u16,tradeable:bool,max_supply:Option<u64>,floor:Option<u128>,holder:address,kiosk:ID,epoch:u64}
public struct RightKey has copy,drop,store {}
public struct Listing<phantom C> has key {id:UID,snapshot:Snapshot,ask:u64,expiry:u64,state:u8,revision:u64,buyer:Option<address>,attempt:Option<vector<u8>>}
public struct Quote has copy,drop,store {domain:vector<u8>,listing:ID,snapshot:Snapshot,ask:u64,total:u64,protocol:ID,fee_revision:u64,buyer:address,expiry:u64}
public struct Created has copy,drop {collection:ID,right:ID,creator:address,kiosk:ID}
public struct Added has copy,drop {collection:ID,soul:ID,supply:u64,revision:u64}
public struct Listed has copy,drop {listing:ID,collection:ID,seller:address,ask:u64,expiry:u64}
public struct Sold has copy,drop {listing:ID,collection:ID,right:ID,seller:address,buyer:address,epoch:u64,attempt:vector<u8>}
public struct Cancelled has copy,drop {listing:ID,collection:ID,seller:address}
public struct ListingDeleted has copy,drop {listing:ID,collection:ID,seller:address,state:u8,buyer:Option<address>,attempt:Option<vector<u8>>}
/// Keep the prior event ABI while making permissionless cleanup actor visible.
public struct ListingReclaimed has copy,drop {listing:ID,collection:ID,deleted_by:address}
fun init(otw:COLLECTION,ctx:&mut TxContext) {
    let publisher=package::claim(otw,ctx);let(mut policy,cap)=transfer_policy::new<Right>(&publisher,ctx);
    transfer_policy::add_rule(Rule{},&mut policy,&cap,RuleConfig{});
    let mut d=display::new<Right>(&publisher,ctx);d.add(b"name".to_string(),b"{name}".to_string());d.add(b"description".to_string(),b"{description}".to_string());d.add(b"image_url".to_string(),b"{image_url}".to_string());d.add(b"creator".to_string(),b"{creator}".to_string());d.update_version();transfer::public_transfer(d,ctx.sender());
    let id=object::id(&policy);transfer::public_share_object(policy);transfer::share_object(Factory{id:object::new(ctx),publisher,policy:id,cap})
}
#[test_only]
public fun init_for_testing(ctx:&mut TxContext){init(COLLECTION{},ctx)}
public fun factory_policy(f:&Factory):ID{f.policy}
fun assert_policy(f:&Factory,p:&TransferPolicy<Right>){assert!(object::id(p)==f.policy && transfer_policy::has_rule<Right,Rule>(p),EBinding)}
public fun create<C>(f:&Factory,p:&TransferPolicy<Right>,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,name:String,description:String,image_url:String,extra:u16,tradeable:bool,max_supply:Option<u64>,floor:Option<u128>,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&mut TxContext):ID {
    assert_policy(f,p);custody::assert_access(k,a,ctx);economics::assert_primary_live(cfg,fee_revision,expiry,clock);
    assert!(extra<=10000 && (extra as u64)+(economics::secondary_bps(cfg) as u64)<=10000 && (max_supply.is_none() || *max_supply.borrow()>0),EPolicy);
    assert!(floor.is_none() || *floor.borrow()<=99999999999999999999,EPolicy);
    // Preserve the original metadata domain; chain transaction/object limits apply.
    let id=object::new(ctx);let collection=object::uid_to_inner(&id);let r=Right{id:object::new(ctx),schema_version:1,collection,protocol:object::id(cfg),creator:ctx.sender(),name,description,image_url};let right=object::id(&r);let right_hash=policy::hash_bytes(bcs::to_bytes(&r));
    custody::lock_right(cfg,CollectionAuthority1{},CollectionRevision3{},k,a,p,r,ctx);
    let c=Collection{id,schema_version:1,protocol:object::id(cfg),creator:ctx.sender(),right,right_hash,policy:object::id(p),extra,tradeable,max_supply,floor,supply:0,members:table::new(ctx),revision:0,holder:ctx.sender(),kiosk:object::id(k),epoch:0};
    event::emit(Created{collection,right,creator:ctx.sender(),kiosk:object::id(k)});transfer::share_object(c);collection
}
public fun add_soul(c:&mut Collection,s:&mut Soul,expected_collection:u64,expected_soul:u64,ctx:&TxContext) {
    assert!(c.revision==expected_collection,ERevision);assert!(c.creator==ctx.sender() && soul::creator(s)==c.creator,EOwner);assert!(soul::protocol(s)==c.protocol,EBinding);
    let id=object::id(s);assert!(!c.members.contains(id) && soul::collection_id(s).is_none(),EMember);assert!(c.max_supply.is_none() || c.supply < *c.max_supply.borrow(),ESupply);
    soul::bind_collection(soulidity_v1::application_operator::operator(),s,object::id(c),expected_soul);c.supply=c.supply+1;c.members.add(id,c.supply);c.revision=c.revision+1;event::emit(Added{collection:object::id(c),soul:id,supply:c.supply,revision:c.revision})
}
public fun add_kiosk_soul<C>(c:&mut Collection,cfg:&Config<C>,k:&mut Kiosk,a:&mut Account,id:ID,expected_collection:u64,expected_soul:u64,ctx:&TxContext) {
    custody::assert_access(k,a,ctx);assert!(c.protocol==object::id(cfg),EBinding);add_soul(c,custody::borrow_soul_for_collection(cfg,CollectionAuthority1{},CollectionRevision3{},k,a,id,ctx),expected_collection,expected_soul,ctx)
}
public fun snapshot(c:&Collection):Snapshot{Snapshot{collection:object::id(c),protocol:c.protocol,creator:c.creator,right:c.right,right_hash:c.right_hash,policy:c.policy,extra:c.extra,tradeable:c.tradeable,max_supply:c.max_supply,floor:c.floor,holder:c.holder,kiosk:c.kiosk,epoch:c.epoch}}
public fun snapshot_hash(c:&Collection):vector<u8>{policy::hash_bytes(bcs::to_bytes(&snapshot(c)))}
public fun creator(c:&Collection):address{c.creator}
public fun protocol_version():u16{1}
public fun version(c:&Collection):u16{c.schema_version}
public fun right_version(r:&Right):u16{r.schema_version}
public fun protocol(c:&Collection):ID{c.protocol}
public fun current_holder(c:&Collection):address{c.holder}
public fun current_kiosk(c:&Collection):ID{c.kiosk}
public fun ownership_epoch(c:&Collection):u64{c.epoch}
public fun revision(c:&Collection):u64{c.revision}
public fun right_id(c:&Collection):ID{c.right}
public fun extra_royalty(c:&Collection):u16{c.extra}
public fun tradeable(c:&Collection):bool{c.tradeable}
public fun max_supply(c:&Collection):Option<u64>{c.max_supply}
public fun supply(c:&Collection):u64{c.supply}
public fun floor_price(c:&Collection):Option<u128>{c.floor}
public fun contains(c:&Collection,id:ID):bool{c.members.contains(id)}
public fun right_collection(r:&Right):ID{r.collection}
public fun right_name(r:&Right):String{r.name}
public fun right_description(r:&Right):String{r.description}
public fun right_image(r:&Right):String{r.image_url}
public(package) fun assert_member(c:&Collection,s:&Soul){assert!(soul::protocol(s)==c.protocol && soul::collection_id(s)==option::some(object::id(c)) && c.members.contains(object::id(s)),EBinding)}
public fun list<C>(c:&Collection,k:&mut Kiosk,a:&mut Account,cfg:&Config<C>,ask:u64,expiry:u64,expected_epoch:u64,fee_revision:u64,clock:&Clock,ctx:&mut TxContext):ID {
    custody::assert_access(k,a,ctx);assert!(c.holder==ctx.sender() && c.kiosk==object::id(k),EOwner);assert!(c.epoch==expected_epoch,ERevision);assert!(c.protocol==object::id(cfg),EBinding);assert!(c.tradeable && ask>0 && expiry>clock::timestamp_ms(clock),EPolicy);economics::assert_secondary_live(cfg,fee_revision,expiry,clock);
    let r=custody::borrow_right<C,CollectionAuthority1,CollectionRevision3,Right>(cfg,CollectionAuthority1{},CollectionRevision3{},k,a,c.right,ctx);assert!(policy::hash_bytes(bcs::to_bytes(r))==c.right_hash && kiosk::is_locked(k,c.right),EBinding);economics::right_total(cfg,ask);
    let cap=custody::list_right<C,CollectionAuthority1,CollectionRevision3,Right>(cfg,CollectionAuthority1{},CollectionRevision3{},k,a,c.right,ctx);let mut l=Listing<C>{id:object::new(ctx),snapshot:snapshot(c),ask,expiry,state:0,revision:0,buyer:option::none(),attempt:option::none()};let id=object::id(&l);dof::add(&mut l.id,RightKey{},cap);event::emit(Listed{listing:id,collection:object::id(c),seller:c.holder,ask,expiry});transfer::share_object(l);id
}
public fun quote<C>(l:&Listing<C>,cfg:&Config<C>,buyer:address):vector<u8>{economics::assert_secondary(cfg);policy::hash_bytes(bcs::to_bytes(&Quote{domain:b"soulidity-collection-right-quote-v1",listing:object::id(l),snapshot:l.snapshot,ask:l.ask,total:economics::right_total(cfg,l.ask),protocol:object::id(cfg),fee_revision:economics::revision(cfg),buyer,expiry:l.expiry}))}
public fun cancel<C>(l:&mut Listing<C>,k:&mut Kiosk,a:&mut Account,expected:u64,ctx:&TxContext) {
    assert!(l.state==0 && l.revision==expected,EState);custody::assert_access(k,a,ctx);assert!(l.snapshot.holder==ctx.sender() && l.snapshot.kiosk==object::id(k),EOwner);
    let cap:PurchaseCap<Right> = dof::remove(&mut l.id,RightKey{});kiosk::return_purchase_cap(k,cap);l.state=2;l.revision=l.revision+1;event::emit(Cancelled{listing:object::id(l),collection:l.snapshot.collection,seller:ctx.sender()})
}
public fun buy<C>(l:&mut Listing<C>,c:&mut Collection,f:&Factory,p:&TransferPolicy<Right>,seller:&mut Kiosk,buyer:&mut Kiosk,a:&mut Account,cfg:&mut Config<C>,expected_listing:u64,expected_epoch:u64,fee_revision:u64,expected_quote:vector<u8>,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    assert!(l.state==0 && l.revision==expected_listing,EState);assert!(c.epoch==expected_epoch,ERevision);assert!(snapshot(c)==l.snapshot && c.protocol==object::id(cfg) && c.kiosk==object::id(seller),EBinding);assert!(c.tradeable && ctx.sender()!=c.holder,EPolicy);assert_policy(f,p);assert!(object::id(p)==c.policy,EBinding);custody::assert_access(buyer,a,ctx);economics::assert_secondary_live(cfg,fee_revision,l.expiry,clock);assert!(expected_quote==quote(l,cfg,ctx.sender()),EQuote);policy::assert_hash(&attempt);
    let cap:PurchaseCap<Right> = dof::remove(&mut l.id,RightKey{});let(r,mut request)=kiosk::purchase_with_cap<Right>(seller,cap,coin::zero(ctx));assert!(object::id(&r)==c.right && policy::hash_bytes(bcs::to_bytes(&r))==c.right_hash && transfer_policy::item(&request)==c.right && transfer_policy::from(&request)==c.kiosk && transfer_policy::paid(&request)==0,EBinding);
    economics::right_sale<C,CollectionAuthority1,CollectionRevision3>(cfg,CollectionAuthority1{},CollectionRevision3{},payment,l.ask,c.holder,c.right,attempt,ctx);let previous=c.holder;c.holder=ctx.sender();c.kiosk=object::id(buyer);c.epoch=c.epoch+1;c.revision=c.revision+1;custody::lock_right(cfg,CollectionAuthority1{},CollectionRevision3{},buyer,a,p,r,ctx);assert!(kiosk::is_locked(buyer,c.right) && kiosk::has_item_with_type<Right>(buyer,c.right),EBinding);
    transfer_policy::add_receipt(Rule{},&mut request);transfer_policy::confirm_request(p,request);l.state=1;l.revision=l.revision+1;l.buyer=option::some(ctx.sender());l.attempt=option::some(attempt);event::emit(Sold{listing:object::id(l),collection:object::id(c),right:c.right,seller:previous,buyer:c.holder,epoch:c.epoch,attempt})
}
public fun listing_state<C>(l:&Listing<C>):u8{l.state}
public fun listing_receipt<C>(l:&Listing<C>):Option<vector<u8>>{l.attempt}
public fun listing_ask<C>(l:&Listing<C>):u64{l.ask}
/// Any wallet may reclaim a terminal listing after the actual PurchaseCap exits.
/// Asset custody and Collection ownership cannot change through this cleanup.
public fun delete_listing<C>(l:Listing<C>,ctx:&TxContext) {
    assert!(l.state==1 || l.state==2,EState);
    assert!(!dof::exists(&l.id,RightKey{}),EState);
    event::emit(ListingDeleted{listing:object::id(&l),collection:l.snapshot.collection,seller:l.snapshot.holder,state:l.state,buyer:l.buyer,attempt:l.attempt});
    event::emit(ListingReclaimed{listing:object::id(&l),collection:l.snapshot.collection,deleted_by:ctx.sender()});
    let Listing{id,snapshot:_,ask:_,expiry:_,state:_,revision:_,buyer:_,attempt:_}=l;object::delete(id)
}

public fun register<C>(cfg:&mut soulidity_foundation::economics::Config<C>,admin:&mut soulidity_foundation::economics::Admin,expected:u64,hash:vector<u8>,factory:&Factory,cap:&sui::package::UpgradeCap){
    economics::register_role<C,CollectionAuthority1,CollectionRevision3>(cfg,admin,expected,hash,4,CollectionAuthority1{},CollectionRevision3{},&factory.publisher,cap)
}

#[test_only]
public fun right_for_testing<C>(cfg:&Config<C>,k:&mut Kiosk,a:&Account,id:ID,ctx:&TxContext):&Right {
    custody::borrow_right(cfg,CollectionAuthority1{},CollectionRevision3{},k,a,id,ctx)
}

#[test_only]
public fun bootstrap_for_testing<C>(cfg:&mut Config<C>,admin:&mut soulidity_foundation::economics::Admin){
    economics::bootstrap_role_for_testing(cfg,admin,4,CollectionAuthority1{},CollectionRevision3{})
}
#[test_only]
public fun wrong_right_type_for_testing<C,T:key+store>(cfg:&Config<C>,k:&mut Kiosk,a:&Account,id:ID,ctx:&TxContext):&T{
    custody::borrow_right(cfg,CollectionAuthority1{},CollectionRevision3{},k,a,id,ctx)
}
#[test_only]
public fun old_revision_right_for_testing<C>(cfg:&Config<C>,k:&mut Kiosk,a:&Account,id:ID,ctx:&TxContext):&Right{
    custody::borrow_right(cfg,CollectionAuthority1{},CollectionRevision2{},k,a,id,ctx)
}
