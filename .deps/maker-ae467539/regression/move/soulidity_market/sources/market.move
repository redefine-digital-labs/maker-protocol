/// Custody listings freeze the exact bundle. No asset/UID borrow escapes publicly.
module soulidity_market::market;
/// Private values are constructed and consumed only inside this producer.
public struct MarketAuthority1 has drop {}
/// Retained for compatible type origins; current business uses Revision3.
public struct MarketRevision1 has drop {}
public struct MarketRevision2 has drop {}
public struct MarketRevision3 has drop {}
public struct MARKET has drop {}
fun init(w:MARKET,ctx:&mut TxContext){sui::package::claim_and_keep(w,ctx)}

use std::bcs;
use std::type_name::{Self,TypeName};
use sui::dynamic_object_field as dof;
use sui::coin::Coin;
use sui::clock::{Self,Clock};
use sui::event;
use soulidity_application::character::{Self as soul,Manifest};
use soulidity_standard::soul::Soul;
use soulidity_model::components::{Self as item,Item};
use soulidity_model::policy;
use soulidity_maker_manufacturing::maker_catalog::{Control,Product};
use soulidity_maker_manufacturing::maker_catalog as catalog;
use soulidity_foundation::economics::{Self,Config,MarketPolicy,MarketReceipt};
use soulidity_collection::collection::{Self,Collection};
use soulidity_maker_terms::maker_resale::{Self as resale,Snapshot,Receipt};
const EState:u64=1;const EQuote:u64=2;const ESeller:u64=3;const EProtocol:u64=4;
public struct AssetKey has copy,drop,store {}
/// LIVE=0,SOLD=1,CANCELLED=2. Terminal receipts remain queryable until cleanup;
/// cleanup emits their exact settlement and manifest for historical discovery.
public struct Listing<phantom T:key+store,phantom C> has key {
    id:UID,asset:ID,protocol:ID,seller:address,price:u64,expiry:u64,state:u8,
    revision:u64,manifest_hash:vector<u8>,commerce:Option<MarketPolicy>,commerce_settlement:Option<MarketReceipt>,
    buyer:Option<address>,attempt:Option<vector<u8>>,
    collection:Option<CollectionFee>,rights:Option<Snapshot>,settlement:Option<Receipt>,
}
public struct CollectionFee has copy,drop,store {id:ID,extra:u16}
public struct Listed has copy,drop {listing:ID,asset:ID,seller:address,price:u64,expiry:u64,manifest_hash:vector<u8>}
public struct Sold has copy,drop {listing:ID,asset:ID,buyer:address,seller:address,price:u64,attempt:vector<u8>,manifest_hash:vector<u8>}
public struct Cancelled has copy,drop {listing:ID,asset:ID,seller:address}
public struct ListingDeleted has copy,drop {
    listing:ID,asset:ID,protocol:ID,seller:address,deleted_by:address,state:u8,
    asset_type:TypeName,payment_coin:TypeName,manifest_hash:vector<u8>,
    buyer:Option<address>,attempt:Option<vector<u8>>,
    commerce_settlement:Option<MarketReceipt>,settlement:Option<Receipt>,
}
public struct Repriced has copy,drop {listing:ID,asset:ID,seller:address,previous_revision:u64,revision:u64,previous_price:u64,price:u64,expiry:u64}
public struct ControlManifest has copy,drop,store {control:ID,product:ID,version:u64,policy_hash:vector<u8>,market:MarketPolicy,income:soulidity_foundation::revenue::Snapshot}

/// Preserve Collection's three membership conditions using public read-only APIs.
/// Abort 3 retains the original binding failure code; no new asset borrow escapes.
fun assert_collection_member(c:&Collection,s:&Soul){
    assert!(soul::protocol(s)==collection::protocol(c)
        && soul::collection_id(s)==option::some(object::id(c))
        && collection::contains(c,object::id(s)),3)
}

public fun list_soul<C>(s:Soul,cfg:&Config<C>,price:u64,expiry:u64,expected:u64,manifest_hash:vector<u8>,fee_revision:u64,clock:&Clock,ctx:&mut TxContext):ID {
    assert!(soul::protocol(&s)==object::id(cfg),EProtocol);soul::assert_revision(&s,expected);
    assert!(soul::collection_id(&s).is_none(),EProtocol);
    assert!(soul::manifest_hash(&s)==manifest_hash,EQuote);
    let rights=*soul::resale(&s);resale::quote_gross(&rights,cfg,price,ctx.sender());
    create(s,cfg,price,expiry,manifest_hash,option::none(),option::none(),option::some(rights),fee_revision,clock,ctx)
}
public fun list_soul_with_collection<C>(s:Soul,c:&Collection,cfg:&Config<C>,price:u64,expiry:u64,expected:u64,manifest_hash:vector<u8>,fee_revision:u64,clock:&Clock,ctx:&mut TxContext):ID {
    assert_collection_member(c,&s);assert!(soul::protocol(&s)==object::id(cfg),EProtocol);soul::assert_revision(&s,expected);assert!(soul::manifest_hash(&s)==manifest_hash,EQuote);
    let rights=*soul::resale(&s);resale::quote_collection(&rights,cfg,price,ctx.sender(),object::id(c),collection::current_holder(c),collection::extra_royalty(c));
    create(s,cfg,price,expiry,manifest_hash,option::none(),option::some(CollectionFee{id:object::id(c),extra:collection::extra_royalty(c)}),option::some(rights),fee_revision,clock,ctx)
}
public fun list_item<C>(it:Item,cfg:&Config<C>,price:u64,expiry:u64,fee_revision:u64,clock:&Clock,ctx:&mut TxContext):ID {
    let source=item::source(&it);assert!(policy::source_protocol(source)==object::id(cfg),EProtocol);
    let hash=policy::source_hash(source);let market=policy::source_market(source);economics::market_quote(&market,cfg,1,price,ctx.sender());
    create(it,cfg,price,expiry,hash,option::some(market),option::none(),option::none(),fee_revision,clock,ctx)
}
public fun list_control<C>(c:Control,p:&Product<C>,cfg:&Config<C>,price:u64,expiry:u64,expected_version:u64,fee_revision:u64,clock:&Clock,ctx:&mut TxContext):ID {
    catalog::assert_paused(p);
    catalog::assert_control(p,&c);assert!(catalog::protocol(p)==object::id(cfg) && catalog::current_version(p)==expected_version,EProtocol);
    let market=catalog::market_policy(p);economics::market_quote(&market,cfg,0,price,ctx.sender());let hash=control_hash(&c,p);
    create(c,cfg,price,expiry,hash,option::some(market),option::none(),option::none(),fee_revision,clock,ctx)
}
fun control_hash<C>(c:&Control,p:&Product<C>):vector<u8>{let version=catalog::current_version(p);policy::hash_bytes(bcs::to_bytes(&ControlManifest{control:object::id(c),product:object::id(p),version,policy_hash:catalog::policy_hash(catalog::published(p,version)),market:catalog::market_policy(p),income:soulidity_foundation::revenue::snapshot(catalog::income(p))}))}
fun create<T:key+store,C>(asset:T,cfg:&Config<C>,price:u64,expiry:u64,manifest_hash:vector<u8>,commerce:Option<MarketPolicy>,collection:Option<CollectionFee>,rights:Option<Snapshot>,fee_revision:u64,clock:&Clock,ctx:&mut TxContext):ID {
    economics::assert_secondary_live(cfg,fee_revision,expiry,clock);assert!(price>0 && expiry>clock::timestamp_ms(clock),EQuote);
    let mut l=Listing<T,C>{id:object::new(ctx),asset:object::id(&asset),protocol:object::id(cfg),seller:ctx.sender(),price,expiry,state:0,revision:0,manifest_hash,commerce,commerce_settlement:option::none(),collection,rights,settlement:option::none(),buyer:option::none(),attempt:option::none()};
    let id=object::id(&l);dof::add(&mut l.id,AssetKey{},asset);
    event::emit(Listed{listing:id,asset:l.asset,seller:l.seller,price,expiry,manifest_hash});transfer::share_object(l);id
}
public fun bundle<C>(l:&Listing<Soul,C>):Manifest {assert!(l.state==0,EState);soul::manifest(dof::borrow(&l.id,AssetKey{}))}
/// Optional Soul-attached tool inventory, from actual listing custody.
public fun bundle_vault<C>(l:&Listing<Soul,C>):Option<soulidity_application::vault::Snapshot>{assert!(l.state==0,EState);let s:&Soul=dof::borrow(&l.id,AssetKey{});if(soulidity_application::vault::installed(s))option::some(soulidity_application::vault::snapshot(s)) else option::none()}
public fun bundle_standard<C>(l:&Listing<Soul,C>):soulidity_standard::soul::Manifest {assert!(l.state==0,EState);soul::standard_manifest(dof::borrow(&l.id,AssetKey{}))}
public fun bundle_bound_source<C>(l:&Listing<Soul,C>,index:u64):soulidity_model::policy::Source{assert!(l.state==0,EState);*soul::bound_source(dof::borrow(&l.id,AssetKey{}),index)}
public fun bundle_reference_source<C>(l:&Listing<Soul,C>,index:u64):soulidity_model::policy::Source{assert!(l.state==0,EState);*soul::reference_source(dof::borrow(&l.id,AssetKey{}),index)}
public fun price<T:key+store,C>(l:&Listing<T,C>):u64{l.price}
public fun status<T:key+store,C>(l:&Listing<T,C>):u8{l.state}
public fun revision<T:key+store,C>(l:&Listing<T,C>):u64{l.revision}
public fun manifest_hash<T:key+store,C>(l:&Listing<T,C>):vector<u8>{l.manifest_hash}
public fun buyer<T:key+store,C>(l:&Listing<T,C>):Option<address>{l.buyer}
public fun receipt<T:key+store,C>(l:&Listing<T,C>):Option<vector<u8>>{l.attempt}
public fun rights<C>(l:&Listing<Soul,C>):Snapshot{l.rights.destroy_some()}
public fun settlement<T:key+store,C>(l:&Listing<T,C>):Option<Receipt>{l.settlement}
public fun asset_settlement<T:key+store,C>(l:&Listing<T,C>):Option<MarketReceipt>{l.commerce_settlement}
public fun item_quote<C>(l:&Listing<Item,C>,cfg:&Config<C>):MarketReceipt{asset_quote(l,cfg,1)}
public fun control_quote<C>(l:&Listing<Control,C>,cfg:&Config<C>):MarketReceipt{asset_quote(l,cfg,0)}
fun asset_quote<T:key+store,C>(l:&Listing<T,C>,cfg:&Config<C>,lane:u8):MarketReceipt{assert!(l.protocol==object::id(cfg),EProtocol);economics::market_quote(l.commerce.borrow(),cfg,lane,l.price,l.seller)}
public struct AssetQuote has copy,drop,store {domain:vector<u8>,listing:ID,asset:ID,revision:u64,manifest:vector<u8>,receipt:MarketReceipt,buyer:address,expiry:u64}
fun asset_quote_hash<T:key+store,C>(l:&Listing<T,C>,receipt:MarketReceipt,buyer:address):vector<u8>{policy::hash_bytes(bcs::to_bytes(&AssetQuote{domain:b"soulidity-product-equipment-resale-v1",listing:object::id(l),asset:l.asset,revision:l.revision,manifest:l.manifest_hash,receipt,buyer,expiry:l.expiry}))}
public fun item_quote_hash<C>(l:&Listing<Item,C>,cfg:&Config<C>,buyer:address):vector<u8>{asset_quote_hash(l,item_quote(l,cfg),buyer)}
public fun control_quote_hash<C>(l:&Listing<Control,C>,cfg:&Config<C>,buyer:address):vector<u8>{asset_quote_hash(l,control_quote(l,cfg),buyer)}
/// The original equipment market allows seller repricing under revision CAS.
/// This preserves custody and the immutable Source/fee policy.
public fun reprice_item<C>(l:&mut Listing<Item,C>,cfg:&Config<C>,expected:u64,manifest_hash:vector<u8>,price:u64,expiry:u64,fee_revision:u64,clock:&Clock,ctx:&TxContext) {
    assert!(l.state==0 && l.revision==expected,EState);assert!(ctx.sender()==l.seller,ESeller);
    assert!(l.protocol==object::id(cfg),EProtocol);assert!(l.manifest_hash==manifest_hash && expiry>clock::timestamp_ms(clock),EQuote);
    economics::assert_secondary_live(cfg,fee_revision,expiry,clock);economics::market_quote(l.commerce.borrow(),cfg,1,price,l.seller);
    let previous_price=l.price;l.price=price;l.expiry=expiry;l.revision=l.revision+1;
    event::emit(Repriced{listing:object::id(l),asset:l.asset,seller:l.seller,previous_revision:expected,revision:l.revision,previous_price,price,expiry})
}
public fun soul_quote<C>(l:&Listing<Soul,C>,cfg:&Config<C>):Receipt {
    economics::assert_secondary(cfg);assert!(l.collection.is_none() && l.protocol==object::id(cfg),EProtocol);resale::quote_gross(l.rights.borrow(),cfg,l.price,l.seller)
}
public fun collection_quote<C>(l:&Listing<Soul,C>,c:&Collection,cfg:&Config<C>):Receipt {
    economics::assert_secondary(cfg);
    assert!(l.protocol==object::id(cfg) && collection::protocol(c)==l.protocol && l.collection==option::some(CollectionFee{id:object::id(c),extra:collection::extra_royalty(c)}),EProtocol);
    resale::quote_collection(l.rights.borrow(),cfg,l.price,l.seller,object::id(c),collection::current_holder(c),collection::extra_royalty(c))
}
public fun collection_total<C>(l:&Listing<Soul,C>,c:&Collection,cfg:&Config<C>):u64{resale::total(&collection_quote(l,c,cfg))}
public struct SoulQuote has copy,drop,store {domain:vector<u8>,listing:ID,asset:ID,revision:u64,manifest:vector<u8>,rights_hash:vector<u8>,receipt:Receipt,buyer:address,expiry:u64,collection_snapshot:Option<vector<u8>>}
fun quote_hash<C>(l:&Listing<Soul,C>,r:Receipt,buyer:address,collection_snapshot:Option<vector<u8>>):vector<u8>{
    policy::hash_bytes(bcs::to_bytes(&SoulQuote{domain:b"soulidity-soul-resale-v1",listing:object::id(l),asset:l.asset,revision:l.revision,manifest:l.manifest_hash,rights_hash:resale::hash(l.rights.borrow()),receipt:r,buyer,expiry:l.expiry,collection_snapshot}))
}
public fun soul_quote_hash<C>(l:&Listing<Soul,C>,cfg:&Config<C>,buyer:address):vector<u8>{quote_hash(l,soul_quote(l,cfg),buyer,option::none())}
public fun collection_quote_hash<C>(l:&Listing<Soul,C>,c:&Collection,cfg:&Config<C>,buyer:address):vector<u8>{quote_hash(l,collection_quote(l,c,cfg),buyer,option::some(collection::snapshot_hash(c)))}
public fun cancel<T:key+store,C>(l:&mut Listing<T,C>,expected:u64,ctx:&TxContext) {
    let asset=cancel_value(l,expected,ctx);transfer::public_transfer(asset,l.seller);
}
/// Internal owned escrow exit. No asset, UID, or producer authority escapes publicly.
fun cancel_value<T:key+store,C>(l:&mut Listing<T,C>,expected:u64,ctx:&TxContext):T {
    assert!(l.state==0 && l.revision==expected,EState);assert!(ctx.sender()==l.seller,ESeller);
    let asset:T=dof::remove(&mut l.id,AssetKey{});l.state=2;l.revision=l.revision+1;
    event::emit(Cancelled{listing:object::id(l),asset:l.asset,seller:l.seller});asset
}
/// Close the old receipt and relist the same owned Soul under normal admission.
/// Cancelled precedes Listed; both operations occur in this one Move call.
public fun relist_soul<C>(l:&mut Listing<Soul,C>,cfg:&Config<C>,expected_listing:u64,price:u64,expiry:u64,expected_soul:u64,manifest_hash:vector<u8>,fee_revision:u64,clock:&Clock,ctx:&mut TxContext):ID {
    let s=cancel_value(l,expected_listing,ctx);
    list_soul(s,cfg,price,expiry,expected_soul,manifest_hash,fee_revision,clock,ctx)
}
/// Relist an actual Collection member, preserving the existing binding/fee checks.
public fun relist_soul_with_collection<C>(l:&mut Listing<Soul,C>,c:&Collection,cfg:&Config<C>,expected_listing:u64,price:u64,expiry:u64,expected_soul:u64,manifest_hash:vector<u8>,fee_revision:u64,clock:&Clock,ctx:&mut TxContext):ID {
    let s=cancel_value(l,expected_listing,ctx);
    list_soul_with_collection(s,c,cfg,price,expiry,expected_soul,manifest_hash,fee_revision,clock,ctx)
}
/// Restore the original permissionless storage cleanup. No active asset can be
/// deleted: both terminal state and absence of actual escrow are required.
/// This exit deliberately does not depend on Config enable, pause or pricing.
public fun delete_listing<T:key+store,C>(l:Listing<T,C>,ctx:&TxContext){
    assert!(l.state==1 || l.state==2,EState);assert!(!dof::exists(&l.id,AssetKey{}),EState);
    event::emit(ListingDeleted{listing:object::id(&l),asset:l.asset,protocol:l.protocol,seller:l.seller,deleted_by:ctx.sender(),state:l.state,
        asset_type:type_name::with_original_ids<T>(),payment_coin:type_name::with_original_ids<C>(),manifest_hash:l.manifest_hash,
        buyer:l.buyer,attempt:l.attempt,commerce_settlement:l.commerce_settlement,settlement:l.settlement});
    let Listing{id,asset:_,protocol:_,seller:_,price:_,expiry:_,state:_,revision:_,manifest_hash:_,commerce:_,commerce_settlement:_,buyer:_,attempt:_,collection:_,rights:_,settlement:_}=l;
    object::delete(id)
}
public fun buy_soul<C>(l:&mut Listing<Soul,C>,cfg:&mut Config<C>,expected:u64,manifest_hash:vector<u8>,expected_quote:vector<u8>,fee_revision:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    assert!(l.collection.is_none(),EProtocol);
    quote(l,cfg,expected,manifest_hash,fee_revision,&attempt,clock,ctx);
    assert!(expected_quote==soul_quote_hash(l,cfg,ctx.sender()),EQuote);let receipt=soul_quote(l,cfg);
    let mut s:Soul=dof::remove(&mut l.id,AssetKey{});assert!(soul::manifest_hash(&s)==l.manifest_hash && *soul::resale(&s)==rights(l),EQuote);
    // The sale snapshot remains in the receipt; clear every old delegation before handover.
    soul::clear_authorizations(&mut s);soulidity_application::vault::prepare_handover(&mut s);
    resale::settle(MarketAuthority1{},MarketRevision3{},cfg,l.rights.borrow(),receipt,payment,l.asset,attempt,ctx);l.settlement=option::some(receipt);mark_sale(l,attempt,ctx);transfer::public_transfer(s,ctx.sender());
}
/// Mutable Collection ownership is re-quoted at purchase; no stale recipient cache.
public fun buy_soul_with_collection<C>(l:&mut Listing<Soul,C>,c:&Collection,cfg:&mut Config<C>,expected:u64,manifest_hash:vector<u8>,expected_collection:vector<u8>,expected_quote:vector<u8>,fee_revision:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    assert!(l.collection==option::some(CollectionFee{id:object::id(c),extra:collection::extra_royalty(c)}) && expected_collection==collection::snapshot_hash(c),EQuote);quote(l,cfg,expected,manifest_hash,fee_revision,&attempt,clock,ctx);
    assert!(expected_quote==collection_quote_hash(l,c,cfg,ctx.sender()),EQuote);let receipt=collection_quote(l,c,cfg);
    let mut s:Soul=dof::remove(&mut l.id,AssetKey{});assert_collection_member(c,&s);assert!(soul::manifest_hash(&s)==l.manifest_hash && *soul::resale(&s)==rights(l),EQuote);soul::clear_authorizations(&mut s);soulidity_application::vault::prepare_handover(&mut s);
    resale::settle(MarketAuthority1{},MarketRevision3{},cfg,l.rights.borrow(),receipt,payment,l.asset,attempt,ctx);l.settlement=option::some(receipt);mark_sale(l,attempt,ctx);transfer::public_transfer(s,ctx.sender())
}
public fun buy_item<C>(l:&mut Listing<Item,C>,cfg:&mut Config<C>,expected:u64,manifest_hash:vector<u8>,expected_quote:vector<u8>,fee_revision:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    quote(l,cfg,expected,manifest_hash,fee_revision,&attempt,clock,ctx);
    assert!(expected_quote==item_quote_hash(l,cfg,ctx.sender()),EQuote);let r=item_quote(l,cfg);
    let it:Item=dof::remove(&mut l.id,AssetKey{});assert!(policy::source_hash(item::source(&it))==l.manifest_hash && policy::source_market(item::source(&it))==l.commerce.destroy_some(),EQuote);
    economics::market_settle<C,MarketAuthority1,MarketRevision3>(cfg,MarketAuthority1{},MarketRevision3{},r,payment,l.asset,attempt,ctx);l.commerce_settlement=option::some(r);mark_sale(l,attempt,ctx);transfer::public_transfer(it,ctx.sender());
}
public fun buy_control<C>(l:&mut Listing<Control,C>,p:&Product<C>,cfg:&mut Config<C>,expected:u64,manifest_hash:vector<u8>,expected_quote:vector<u8>,fee_revision:u64,attempt:vector<u8>,payment:Coin<C>,clock:&Clock,ctx:&mut TxContext) {
    catalog::assert_paused(p);
    quote(l,cfg,expected,manifest_hash,fee_revision,&attempt,clock,ctx);
    assert!(expected_quote==control_quote_hash(l,cfg,ctx.sender()),EQuote);let r=control_quote(l,cfg);
    let c:Control=dof::remove(&mut l.id,AssetKey{});catalog::assert_control(p,&c);
    assert!(control_hash(&c,p)==l.manifest_hash && catalog::market_policy(p)==l.commerce.destroy_some(),EQuote);
    economics::market_settle<C,MarketAuthority1,MarketRevision3>(cfg,MarketAuthority1{},MarketRevision3{},r,payment,l.asset,attempt,ctx);l.commerce_settlement=option::some(r);mark_sale(l,attempt,ctx);transfer::public_transfer(c,ctx.sender());
}
fun quote<T:key+store,C>(l:&Listing<T,C>,cfg:&Config<C>,expected:u64,hash:vector<u8>,fee_revision:u64,attempt:&vector<u8>,clock:&Clock,ctx:&TxContext) {
    assert!(l.state==0 && l.revision==expected,EState);assert!(l.protocol==object::id(cfg),EProtocol);
    assert!(hash==l.manifest_hash && ctx.sender()!=l.seller,EQuote);policy::assert_hash(attempt);
    economics::assert_secondary_live(cfg,fee_revision,l.expiry,clock);
}
fun mark_sale<T:key+store,C>(l:&mut Listing<T,C>,attempt:vector<u8>,ctx:&TxContext) {
    l.state=1;l.revision=l.revision+1;l.buyer=option::some(ctx.sender());l.attempt=option::some(attempt);
    event::emit(Sold{listing:object::id(l),asset:l.asset,buyer:ctx.sender(),seller:l.seller,price:l.price,attempt,manifest_hash:l.manifest_hash});
}

public fun register<C>(cfg:&mut soulidity_foundation::economics::Config<C>,admin:&mut soulidity_foundation::economics::Admin,expected:u64,hash:vector<u8>,publisher:&sui::package::Publisher,cap:&sui::package::UpgradeCap){
    economics::register_role<C,MarketAuthority1,MarketRevision3>(cfg,admin,expected,hash,3,MarketAuthority1{},MarketRevision3{},publisher,cap)
}

/// Exercise the actual private market role and production settlement in VM tests.
#[test_only]
public fun settle_for_testing<C>(cfg:&mut Config<C>,s:&Snapshot,r:Receipt,payment:Coin<C>,subject:ID,attempt:vector<u8>,ctx:&mut TxContext){
    resale::settle(MarketAuthority1{},MarketRevision3{},cfg,s,r,payment,subject,attempt,ctx)
}

/// VM-only binding of the leaf's private role before Config activation.
#[test_only]
public fun bootstrap_for_testing<C>(cfg:&mut Config<C>,admin:&mut economics::Admin){
    economics::bootstrap_role_for_testing<C,MarketAuthority1,MarketRevision3>(cfg,admin,3,MarketAuthority1{},MarketRevision3{})
}
