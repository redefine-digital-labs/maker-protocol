module refuse::refusal;
use soulidity_model::policy::Source;
public fun bad(source:Source,ctx:&mut TxContext){let(_,item)=soulidity_model::components::materialize(source,object::id_from_address(@0x1),ctx);item.do!(|i|transfer::public_transfer(i,@0xa));}
