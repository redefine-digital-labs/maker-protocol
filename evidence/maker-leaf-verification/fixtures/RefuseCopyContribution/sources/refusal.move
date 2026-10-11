module foreign_leaf::refusal;
use soulidity_maker_admission::maker_issuance::Contribution;
public fun duplicate(v:&Contribution):(Contribution,Contribution){(*v,*v)}
