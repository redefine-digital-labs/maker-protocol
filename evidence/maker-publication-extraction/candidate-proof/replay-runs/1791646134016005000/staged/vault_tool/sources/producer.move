module vault_tool_probe::producer;
use soulidity_standard::soul::{Self,Soul};
public struct SoulProducer has drop {}
public struct Source has key,store {id:UID}
public fun create(ctx:&mut TxContext):Soul{let p=Source{id:object::new(ctx)};let s=soul::new(SoulProducer{},&p,1,std::hash::sha3_256(b"independent-vault-tool"),std::string::utf8(b"OC"),ctx);transfer::public_transfer(p,ctx.sender());s}
