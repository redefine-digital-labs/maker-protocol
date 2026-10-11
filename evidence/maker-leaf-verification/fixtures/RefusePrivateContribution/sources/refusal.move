module foreign_leaf::refusal;
use soulidity_maker_admission::maker_issuance::Contribution;
public fun root(v:&Contribution):ID{v.root}
