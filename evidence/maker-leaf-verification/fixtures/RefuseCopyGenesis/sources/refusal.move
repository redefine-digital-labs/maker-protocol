module foreign_leaf::refusal;
use soulidity_maker_admission::maker_issuance::Genesis;
public fun duplicate(v:&Genesis):(Genesis,Genesis){(*v,*v)}
