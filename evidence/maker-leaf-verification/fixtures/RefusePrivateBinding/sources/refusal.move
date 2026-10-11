module foreign_leaf::refusal;
use soulidity_maker_admission::maker_issuance::Binding;
public fun root(v:&Binding):ID{v.config}
