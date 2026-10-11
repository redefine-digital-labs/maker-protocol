module foreign_leaf::refusal;
use soulidity_maker_admission::maker_issuance::{Self,Binding};
use soulidity_maker_terms::maker_physical_metadata::Quote;
public fun use_quote(v:Quote):Binding{v}
