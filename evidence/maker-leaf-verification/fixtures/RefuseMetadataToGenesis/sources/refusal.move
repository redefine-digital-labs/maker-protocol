module foreign_leaf::refusal;
use soulidity_maker_admission::maker_issuance::Genesis;
use soulidity_maker_terms::maker_physical_metadata::Proof;
public fun use_proof(v:Proof):Genesis{v}
