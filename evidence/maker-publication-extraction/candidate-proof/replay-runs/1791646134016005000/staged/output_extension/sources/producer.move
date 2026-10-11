/// Free independent source; one actual seed can issue one standard root.
module independent_output::producer;
use soulidity_standard::soul::{Self,Soul};
public struct SoulProducer has drop {}
public struct Seed has key,store{id:UID,issued:bool}
public fun seed(ctx:&mut TxContext):Seed{Seed{id:object::new(ctx),issued:false}}
public fun mint(seed:&mut Seed,ctx:&mut TxContext):Soul{assert!(!seed.issued,1);seed.issued=true;soul::new(SoulProducer{},seed,1,vector::tabulate!(32,|_|1),b"Independent OC".to_string(),ctx)}
