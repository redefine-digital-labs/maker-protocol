/// Owned address delivery groundwork. Account/market/access/terminal sink
/// migration remains separate; arbitrary key+store public transfers have no hook.
module soulidity_application::custody_handover;
use soulidity_standard::soul::{Self as standard,Soul};
use soulidity_application::{character,vault};
public fun handover(s:Soul,recipient:address):ID {
    let mut h=standard::begin_handover(s);
    character::acknowledge_handover(&mut h);
    vault::acknowledge_handover(&mut h);
    standard::finish_handover(h,recipient)
}

public fun handover_construction(c:standard::Construction,
    completion:soulidity_origin_protocol::producer_origin::CompletionAuthorization,
    recipient:address,ctx:&TxContext,
):ID {
    let mut h=standard::begin_construction_handover(c,completion,ctx);
    character::acknowledge_handover(&mut h);vault::acknowledge_handover(&mut h);
    standard::finish_handover(h,recipient)
}
public fun handover_parent(p:standard::ParentDelivery,recipient:address,ctx:&TxContext):ID {
    let mut h=standard::begin_parent_handover(p,ctx);
    character::acknowledge_handover(&mut h);vault::acknowledge_handover(&mut h);
    standard::finish_handover(h,recipient)
}
