/// Creator's immutable physical-product terms, distinct from OC component rights.
module soulidity_model::material_policy;
use soulidity_model::policy;
const EPolicy:u64=1;
public struct Terms has copy,drop,store {definition:vector<u8>,material:vector<u8>,mode:u8,proof:u8,price:u64,supply:u64,transferable:bool}
public fun terms(definition:vector<u8>,material:vector<u8>,mode:u8,proof:u8,price:u64,supply:u64,transferable:bool):Terms {
    policy::assert_hash(&definition);policy::assert_hash(&material);
    assert!(definition.any!(|b| *b!=0) && material.any!(|b| *b!=0),EPolicy);
    assert!(supply>0 && supply<=1000000000,EPolicy);
    assert!((mode==0 && proof==0 && price==0)||(mode==1 && proof==0 && price>0)||(mode==2 && proof==2 && price==0),EPolicy);
    Terms{definition,material,mode,proof,price,supply,transferable}
}
public fun definition(t:&Terms):vector<u8>{t.definition}
public fun material(t:&Terms):vector<u8>{t.material}
public fun mode(t:&Terms):u8{t.mode}
public fun proof_kind(t:&Terms):u8{t.proof}
public fun price(t:&Terms):u64{t.price}
public fun supply(t:&Terms):u64{t.supply}
public fun transferable(t:&Terms):bool{t.transferable}
public fun hash(t:&Terms):vector<u8>{policy::hash_bytes(std::bcs::to_bytes(t))}
