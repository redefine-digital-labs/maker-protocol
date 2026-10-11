/// Copyable physical provenance and commitment formats. These values carry no
/// custody, entitlement, issuance, materialization or payment authority. The
/// native application constructs them only after checking actual objects.
module soulidity_maker_terms::maker_physical_metadata;
use std::bcs;
use soulidity_model::policy::{Self,Source};
use soulidity_model::material_policy::Terms;
use soulidity_foundation::economics::{Self,MarketPolicy};
use soulidity_maker_terms::maker_resale::{Self as resale,Rates};
public struct Authorization has copy,drop,store {domain:vector<u8>,registry:ID,rule:vector<u8>,actor:address,subject:ID,commitment:vector<u8>}
public struct Quote has copy,drop,store {domain:vector<u8>,registry:ID,revision:u64,rule:vector<u8>,issued:u64,protocol:ID,fee_revision:u64,actor:address,expiry:u64}
public struct Proof has copy,drop,store {schema:u16,soul:ID,generation:u64,revision:u64,artifact:ID,intent:vector<u8>,output_policy:vector<u8>,recipe:vector<u8>,render:vector<u8>,receipt:vector<u8>,output_commitment:vector<u8>,soul_commitment:vector<u8>,key:vector<u8>,source:vector<u8>}
public struct Provenance has copy,drop,store {domain:vector<u8>,registry:ID,rule:vector<u8>,serial:u64,original_holder:address,authorization:vector<u8>,proof:Option<Proof>,visual:vector<u8>}
/// Audit facts, never a capability. The transaction identifies the exact input
/// control versions/owners in the ledger; epoch is a Sui epoch, not a transfer hook.
public struct Registration has copy,drop,store {actor:address,maker_control:ID,source_control:ID,transaction:vector<u8>,epoch:u64,registry_revision:u64}
public fun registration(maker_control:ID,source_control:ID,registry_revision:u64,ctx:&TxContext):Registration{Registration{actor:ctx.sender(),maker_control,source_control,transaction:*ctx.digest(),epoch:ctx.epoch(),registry_revision}}
public fun registered_actor(r:&Registration):address{r.actor}
public fun maker_control(r:&Registration):ID{r.maker_control}
public fun source_control(r:&Registration):ID{r.source_control}
public fun registration_transaction(r:&Registration):vector<u8>{r.transaction}
public fun registration_epoch(r:&Registration):u64{r.epoch}
public fun registration_revision(r:&Registration):u64{r.registry_revision}

public fun proof(soul:ID,generation:u64,revision:u64,artifact:ID,intent:vector<u8>,output_policy:vector<u8>,recipe:vector<u8>,render:vector<u8>,receipt:vector<u8>,output_commitment:vector<u8>,soul_commitment:vector<u8>,key:vector<u8>,source:vector<u8>):Proof{Proof{schema:2,soul,generation,revision,artifact,intent,output_policy,recipe,render,receipt,output_commitment,soul_commitment,key,source}}
public fun provenance_hash(registry:ID,rule:vector<u8>,serial:u64,original_holder:address,authorization:vector<u8>,proof:Option<Proof>,visual:vector<u8>):vector<u8>{policy::hash_bytes(bcs::to_bytes(&Provenance{domain:b"soulidity-physical-asset-v3",registry,rule,serial,original_holder,authorization,proof,visual}))}
public fun authorization_hash(registry:ID,rule:vector<u8>,mode:u8,actor:address,subject:ID,commitment:vector<u8>):vector<u8>{let domain=if(mode==0)b"soulidity-physical-free-v1" else if(mode==1)b"soulidity-physical-paid-v1" else b"soulidity-physical-proof-v1";policy::hash_bytes(bcs::to_bytes(&Authorization{domain,registry,rule,actor,subject,commitment}))}
public fun quote_hash(registry:ID,revision:u64,rule:vector<u8>,issued:u64,protocol:ID,fee_revision:u64,actor:address,expiry:u64):vector<u8>{policy::hash_bytes(bcs::to_bytes(&Quote{domain:b"soulidity-physical-quote-v1",registry,revision,rule,issued,protocol,fee_revision,actor,expiry}))}
public fun proof_soul(p:&Proof):ID{p.soul}
public fun proof_schema(p:&Proof):u16{p.schema}
public fun proof_output_commitment(p:&Proof):vector<u8>{p.output_commitment}
public fun proof_soul_commitment(p:&Proof):vector<u8>{p.soul_commitment}
public fun proof_generation(p:&Proof):u64{p.generation}
public fun proof_revision(p:&Proof):u64{p.revision}
public fun proof_artifact(p:&Proof):ID{p.artifact}
public fun proof_intent(p:&Proof):vector<u8>{p.intent}
public fun proof_output_policy(p:&Proof):vector<u8>{p.output_policy}
public fun proof_recipe(p:&Proof):vector<u8>{p.recipe}
public fun proof_render(p:&Proof):vector<u8>{p.render}
public fun proof_receipt(p:&Proof):vector<u8>{p.receipt}
public fun proof_key(p:&Proof):vector<u8>{p.key}
public fun proof_source(p:&Proof):vector<u8>{p.source}
public fun proof_hash(p:&Proof):vector<u8>{policy::hash_bytes(bcs::to_bytes(p))}

/// Untrusted copyable metadata; never accepted as a custody or settlement capability.
public struct SalePolicy has copy,drop,store {maker:ID,version:u64,policy_hash:vector<u8>,product:ID,product_version:u64,creator:address,source_recipient:address,rates:Rates,market:MarketPolicy}

/// Untrusted copyable metadata; never accepted as a custody or settlement capability.
public struct RuleCommitment has copy,drop,store {domain:vector<u8>,source:Source,terms:Terms,sale:SalePolicy,registration:Registration}

/// Untrusted copyable metadata; never accepted as a custody or settlement capability.
public struct Snapshot has copy,drop,store {asset:ID,registry:ID,source:Source,terms:Terms,sale:SalePolicy,registration:Registration,row_hash:vector<u8>,serial:u64,holder:address,epoch:u64,authorization:vector<u8>,proof:Option<Proof>,visual:vector<u8>,provenance:vector<u8>}

/// Untrusted copyable metadata; never accepted as a custody or settlement capability.
public struct SaleReceipt has copy,drop,store {domain:vector<u8>,listing:ID,asset:ID,revision:u64,snapshot:vector<u8>,policy:SalePolicy,config:ID,fee_revision:u64,seller:address,buyer:address,expiry:u64,gross:u64,platform:u64,creator:u64,source:u64,net:u64}
public fun sale_policy(maker:ID,version:u64,policy_hash:vector<u8>,product:ID,product_version:u64,creator:address,source_recipient:address,rates:Rates,market:MarketPolicy):SalePolicy{SalePolicy{maker,version,policy_hash,product,product_version,creator,source_recipient,rates,market}}
public fun sale_maker(v:&SalePolicy):ID{v.maker}
public fun sale_version(v:&SalePolicy):u64{v.version}
public fun sale_policy_hash(v:&SalePolicy):vector<u8>{v.policy_hash}
public fun sale_product(v:&SalePolicy):ID{v.product}
public fun sale_product_version(v:&SalePolicy):u64{v.product_version}
public fun sale_creator(v:&SalePolicy):address{v.creator}
public fun sale_source_recipient(v:&SalePolicy):address{v.source_recipient}
public fun sale_rates(v:&SalePolicy):Rates{v.rates}
public fun sale_market(v:&SalePolicy):MarketPolicy{v.market}
public fun sale_hash(v:&SalePolicy):vector<u8>{policy::hash_bytes(bcs::to_bytes(v))}
public fun snapshot(asset:ID,registry:ID,source:Source,terms:Terms,sale:SalePolicy,registration:Registration,row_hash:vector<u8>,serial:u64,holder:address,epoch:u64,authorization:vector<u8>,proof:Option<Proof>,visual:vector<u8>,provenance:vector<u8>):Snapshot{Snapshot{asset,registry,source,terms,sale,registration,row_hash,serial,holder,epoch,authorization,proof,visual,provenance}}
public fun snapshot_asset(v:&Snapshot):ID{v.asset}
public fun snapshot_registry(v:&Snapshot):ID{v.registry}
public fun snapshot_source(v:&Snapshot):Source{v.source}
public fun snapshot_terms(v:&Snapshot):Terms{v.terms}
public fun snapshot_sale(v:&Snapshot):SalePolicy{v.sale}
public fun snapshot_registration(v:&Snapshot):Registration{v.registration}
public fun snapshot_row_hash(v:&Snapshot):vector<u8>{v.row_hash}
public fun snapshot_serial(v:&Snapshot):u64{v.serial}
public fun snapshot_holder(v:&Snapshot):address{v.holder}
public fun snapshot_epoch(v:&Snapshot):u64{v.epoch}
public fun snapshot_authorization(v:&Snapshot):vector<u8>{v.authorization}
public fun snapshot_proof(v:&Snapshot):Option<Proof>{v.proof}
public fun snapshot_visual(v:&Snapshot):vector<u8>{v.visual}
public fun snapshot_provenance(v:&Snapshot):vector<u8>{v.provenance}
public fun snapshot_hash(v:&Snapshot):vector<u8>{policy::hash_bytes(bcs::to_bytes(v))}
public fun sale_receipt(listing:ID,asset:ID,revision:u64,snapshot:vector<u8>,policy:SalePolicy,config:ID,fee_revision:u64,seller:address,buyer:address,expiry:u64,gross:u64,platform:u64,creator:u64,source:u64,net:u64):SaleReceipt{SaleReceipt{domain:b"soulidity-physical-resale-v1",listing,asset,revision,snapshot,policy,config,fee_revision,seller,buyer,expiry,gross,platform,creator,source,net}}
public fun receipt_domain(v:&SaleReceipt):vector<u8>{v.domain}
public fun receipt_listing(v:&SaleReceipt):ID{v.listing}
public fun receipt_asset(v:&SaleReceipt):ID{v.asset}
public fun receipt_revision(v:&SaleReceipt):u64{v.revision}
public fun receipt_snapshot(v:&SaleReceipt):vector<u8>{v.snapshot}
public fun receipt_policy(v:&SaleReceipt):SalePolicy{v.policy}
public fun receipt_config(v:&SaleReceipt):ID{v.config}
public fun receipt_fee_revision(v:&SaleReceipt):u64{v.fee_revision}
public fun receipt_seller(v:&SaleReceipt):address{v.seller}
public fun receipt_buyer(v:&SaleReceipt):address{v.buyer}
public fun receipt_expiry(v:&SaleReceipt):u64{v.expiry}
public fun receipt_gross(v:&SaleReceipt):u64{v.gross}
public fun receipt_platform(v:&SaleReceipt):u64{v.platform}
public fun receipt_creator(v:&SaleReceipt):u64{v.creator}
public fun receipt_source(v:&SaleReceipt):u64{v.source}
public fun receipt_net(v:&SaleReceipt):u64{v.net}
public fun receipt_hash(v:&SaleReceipt):vector<u8>{policy::hash_bytes(bcs::to_bytes(v))}
public fun rule_hash(source:Source,terms:Terms,sale:SalePolicy,registration:Registration):vector<u8>{policy::hash_bytes(bcs::to_bytes(&RuleCommitment{domain:b"soulidity-physical-rule-v2",source,terms,sale,registration}))}
/// Pure quote arithmetic. A zero net is rejected by the native settlement guard;
/// no metadata value or calculation here can debit an account or receive an asset.
public fun sale_amounts(p:&SalePolicy,gross:u64):(u64,u64,u64,u64){
    let platform=economics::strict_share(gross,250);let creator=economics::strict_share(gross,resale::oc_bps(&p.rates));let source=economics::strict_share(gross,resale::maker_bps(&p.rates));
    let distributed=(platform as u128)+(creator as u128)+(source as u128);
    (platform,creator,source,if(distributed < (gross as u128))gross-(distributed as u64) else 0)
}
