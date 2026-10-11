/// Immutable OC/Maker royalty provenance and exact Soul settlement.
module soulidity_maker_terms::maker_resale;
use std::bcs;
use sui::coin::{Self,Coin};
use sui::event;
use soulidity_model::policy;
use soulidity_foundation::economics::{Self,Config};
const ERights:u64=1;const EProtocol:u64=2;const EPayment:u64=3;
const NATIVE_PLATFORM_BPS:u16=250;
public struct Rates has copy,drop,store {oc:u16,maker:u16}
public struct Snapshot has copy,drop,store {schema:u16,protocol:ID,maker:ID,version:u64,policy_hash:vector<u8>,oc_creator:address,maker_creator:address,rates:Rates}
public struct Receipt has copy,drop,store {
    basis:u8,price:u64,total:u64,seller_amount:u64,platform_amount:u64,oc_amount:u64,maker_amount:u64,collection_amount:u64,
    config:ID,fee_revision:u64,platform_bps:u16,seller:address,platform:address,oc_creator:address,maker_creator:address,
    collection:Option<ID>,collection_holder:Option<address>,extra_bps:u16,
}
public struct Settled has copy,drop {subject:ID,attempt:vector<u8>,payer:address,rights_hash:vector<u8>,receipt:Receipt}
public fun rates(oc:u16,maker:u16):Rates {assert!(oc<=1000 && maker<=1000 && (oc as u64)+(maker as u64)<=1000,ERights);Rates{oc,maker}}
public fun oc_bps(r:&Rates):u16{r.oc}
public fun maker_bps(r:&Rates):u16{r.maker}
/// Caller-owned royalty metadata; this does not attest a native Soul or authorize settlement.
public fun snapshot(protocol:ID,maker:ID,version:u64,policy_hash:vector<u8>,maker_creator:address,rates:Rates,ctx:&TxContext):Snapshot {
    policy::assert_hash(&policy_hash);assert!(version>0 && maker_creator!=@0x0 && ctx.sender()!=@0x0,ERights);
    Snapshot{schema:1,protocol,maker,version,policy_hash,oc_creator:ctx.sender(),maker_creator,rates}
}
public fun schema(s:&Snapshot):u16{s.schema}
public fun hash(s:&Snapshot):vector<u8>{policy::hash_bytes(bcs::to_bytes(s))}
public fun protocol(s:&Snapshot):ID{s.protocol}
public fun maker(s:&Snapshot):ID{s.maker}
public fun version(s:&Snapshot):u64{s.version}
public fun policy_hash(s:&Snapshot):vector<u8>{s.policy_hash}
public fun oc_creator(s:&Snapshot):address{s.oc_creator}
public fun maker_creator(s:&Snapshot):address{s.maker_creator}
public fun snapshot_rates(s:&Snapshot):Rates{s.rates}
/// Original native V8 uses a gross price and exactly 250bps protocol fee.
public fun quote_gross<C>(s:&Snapshot,cfg:&Config<C>,price:u64,seller:address):Receipt {
    assert!(economics::secondary_bps(cfg)==NATIVE_PLATFORM_BPS,EProtocol);
    quote(s,cfg,price,seller,0,option::none(),option::none(),0)
}
/// Collection asks remain net to seller, with independently rounded additions.
public fun quote_collection<C>(s:&Snapshot,cfg:&Config<C>,ask:u64,seller:address,collection:ID,holder:address,extra:u16):Receipt {
    assert!(holder!=@0x0,ERights);quote(s,cfg,ask,seller,1,option::some(collection),option::some(holder),extra)
}
fun quote<C>(s:&Snapshot,cfg:&Config<C>,price:u64,seller:address,basis:u8,collection:Option<ID>,holder:Option<address>,extra:u16):Receipt {
    assert!(s.protocol==object::id(cfg),EProtocol);assert!(price>0 && seller!=@0x0,ERights);
    let platform_bps=economics::secondary_bps(cfg);
    assert!((platform_bps as u64)+(s.rates.oc as u64)+(s.rates.maker as u64)+(extra as u64)<=10000,ERights);
    let platform_amount=component_fee(price,platform_bps,basis);let oc_amount=component_fee(price,s.rates.oc,basis);let maker_amount=component_fee(price,s.rates.maker,basis);let collection_amount=component_fee(price,extra,basis);
    let fees=(platform_amount as u128)+(oc_amount as u128)+(maker_amount as u128)+(collection_amount as u128);
    let total=if(basis==0)price as u128 else (price as u128)+fees;assert!(total<=18446744073709551615,ERights);
    let seller_amount=if(basis==0)price-(fees as u64) else price;
    Receipt{basis,price,total:total as u64,seller_amount,platform_amount,oc_amount,maker_amount,collection_amount,config:object::id(cfg),fee_revision:economics::revision(cfg),platform_bps,seller,platform:economics::recipient(cfg),oc_creator:s.oc_creator,maker_creator:s.maker_creator,collection,collection_holder:holder,extra_bps:extra}
}
/// Gross V8 floors each share; additive Collection asks ceil each share separately.
/// Do not aggregate rates before rounding, even when recipients coincide.
fun component_fee(amount:u64,bps:u16,basis:u8):u64{if(basis==0)economics::fee(amount,bps) else {let n=(amount as u128)*(bps as u128);(((n+9999)/10000) as u64)}}
public fun settle<C,W:drop,R:drop>(_w:W,_revision:R,cfg:&mut Config<C>,s:&Snapshot,r:Receipt,payment:Coin<C>,subject:ID,attempt:vector<u8>,ctx:&mut TxContext) {
    economics::assert_business<C,W,R>(cfg,3,_w,_revision);
    // Receipts are copyable data. Recompute every recipient and amount against
    // this actual configuration and rights snapshot before routing real Coin.
    let current=if(r.basis==0)quote_gross(s,cfg,r.price,r.seller) else {assert!(r.basis==1,ERights);quote_collection(s,cfg,r.price,r.seller,r.collection.destroy_some(),r.collection_holder.destroy_some(),r.extra_bps)};
    assert!(r==current,ERights);
    assert!(r.config==object::id(cfg) && r.fee_revision==economics::revision(cfg),EProtocol);economics::assert_secondary(cfg);assert!(coin::value(&payment)==r.total,EPayment);let mut payment=payment;
    if(r.platform_amount>0)economics::deposit_income(cfg,coin::split(&mut payment,r.platform_amount,ctx));pay(&mut payment,r.oc_amount,r.oc_creator,ctx);pay(&mut payment,r.maker_amount,r.maker_creator,ctx);
    if(r.collection_amount>0)pay(&mut payment,r.collection_amount,r.collection_holder.destroy_some(),ctx);
    assert!(coin::value(&payment)==r.seller_amount,EPayment);
    if(r.seller_amount==0)coin::destroy_zero(payment) else transfer::public_transfer(payment,r.seller);
    event::emit(Settled{subject,attempt,payer:ctx.sender(),rights_hash:hash(s),receipt:r})
}
fun pay<C>(payment:&mut Coin<C>,amount:u64,to:address,ctx:&mut TxContext){if(amount>0)transfer::public_transfer(coin::split(payment,amount,ctx),to)}
public fun basis(r:&Receipt):u8{r.basis}
public fun price(r:&Receipt):u64{r.price}
public fun total(r:&Receipt):u64{r.total}
public fun seller_amount(r:&Receipt):u64{r.seller_amount}
public fun platform_amount(r:&Receipt):u64{r.platform_amount}
public fun oc_amount(r:&Receipt):u64{r.oc_amount}
public fun maker_amount(r:&Receipt):u64{r.maker_amount}
public fun collection_amount(r:&Receipt):u64{r.collection_amount}
public fun seller(r:&Receipt):address{r.seller}
public fun platform(r:&Receipt):address{r.platform}
public fun oc_recipient(r:&Receipt):address{r.oc_creator}
public fun maker_recipient(r:&Receipt):address{r.maker_creator}
public fun config(r:&Receipt):ID{r.config}
public fun collection_holder(r:&Receipt):Option<address>{r.collection_holder}
public fun fee_revision(r:&Receipt):u64{r.fee_revision}
