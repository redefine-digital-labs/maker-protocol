module foreign_leaf::refusal;
use soulidity_maker_admission::maker_issuance::Binding;
public fun duplicate(v:&Binding):(Binding,Binding){(*v,*v)}
