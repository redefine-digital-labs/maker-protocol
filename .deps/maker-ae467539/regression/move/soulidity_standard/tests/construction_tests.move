#[test_only]
module soulidity_standard::construction_tests;
use std::type_name;
use sui::test_scenario;
use soulidity_standard::soul::{Self, Soul, Construction};
use soulidity_origin_protocol::producer_origin;
use private_source::producer::{Self, Source};
public struct Witness has drop {}
public struct WrongAdapter has drop {}
public struct WrongRevision has drop {}
public struct Value has key, store { id: UID, score: u64 }
fun fresh(p: &Source, ctx: &mut TxContext): Construction { soul::new(producer::request<Soul>(p, 0, ctx), ctx) }
fun deliver(p: &Source, c: Construction, recipient: address, ctx: &TxContext): ID {
    let auth = producer::complete(p, soul::construction_ref(&c), soul::construction_snapshot(&c), ctx);
    soul::deliver(c, auth, recipient, ctx)
}
fun nest(p: &Source, parent: &mut Construction, child: Construction, ctx: &TxContext) {
    let auth = producer::complete(p, soul::construction_ref(&child), soul::construction_snapshot(&child), ctx);
    let revision = soul::revision(soul::construction_ref(parent));
    soul::nest_construction(parent, child, auth, revision, ctx)
}
fun install(c: &mut Construction, ctx: &mut TxContext): ID {
    let v = Value { id: object::new(ctx), score: 7 }; let id = object::id(&v);
    let s = soul::construction_mut(c); let r = soul::revision(s);
    soul::install(s, Witness {}, b"value", v, 1, true, vector::tabulate!(32, |_| 5), r); id
}
#[test]
fun genuine_source_fresh_private_delivery_and_third_party_gift_readback() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let source_id = object::id(&p);
    let mut c = fresh(&p, sc.ctx()); let root = soul::construction_id(&c); let value_id = install(&mut c, sc.ctx());
    let snapshot = soul::construction_snapshot(&c); let origin = soul::origin(soul::construction_ref(&c));
    assert!(soul::source(&origin) == source_id && soul::producer(&origin) == type_name::with_defining_ids<producer::SoulProducer>()
        && soul::source_type(&origin) == type_name::with_defining_ids<Source>() && producer_origin::actor(&snapshot) == @0xa, 0);
    assert!(deliver(&p, c, @0xb, sc.ctx()) == root, 1); transfer::public_transfer(p, @0xa);
    sc.next_tx(@0xb); let mut s: Soul = sc.take_from_sender(); assert!(object::id(&s) == root && soul::origin(&s) == origin, 2);
    let (mut v, edit) = soul::begin_update<Witness, Value>(&mut s, Witness {}, b"value", 1);
    v.score = 19; soul::commit_update(&mut s, edit, Witness {}, v, 1, vector::tabulate!(32, |_| 5));
    let v = soul::uninstall<Witness, Value>(&mut s, b"value", 2); assert!(object::id(&v) == value_id && v.score == 19, 3);
    transfer::public_transfer(v, @0xb); transfer::public_transfer(s, @0xc);
    sc.next_tx(@0xc); let s: Soul = sc.take_from_sender(); assert!(object::id(&s) == root, 4); sc.return_to_sender(s); sc.end();
}
#[test]
fun three_fresh_roots_same_ptb_distinct_sources_gift_then_owned_unnest_and_edit() {
    let mut sc = test_scenario::begin(@0xa);
    let p = producer::create(sc.ctx()); let q = producer::create(sc.ctx()); let r = producer::create(sc.ctx());
    let mut root = fresh(&p, sc.ctx()); let mut child = fresh(&q, sc.ctx()); let grand = fresh(&r, sc.ctx());
    let root_id = soul::construction_id(&root); let child_id = soul::construction_id(&child); let grand_id = soul::construction_id(&grand);
    let origins = vector[soul::origin(soul::construction_ref(&root)), soul::origin(soul::construction_ref(&child)), soul::origin(soul::construction_ref(&grand))];
    nest(&r, &mut child, grand, sc.ctx()); nest(&q, &mut root, child, sc.ctx()); deliver(&p, root, @0xb, sc.ctx());
    transfer::public_transfer(p, @0xa); transfer::public_transfer(q, @0xa); transfer::public_transfer(r, @0xa);
    sc.next_tx(@0xb); let mut root: Soul = sc.take_from_sender();
    assert!(object::id(&root) == root_id && soul::origin(&root) == origins[0]
        && soul::origin(soul::nested(&root, child_id)) == origins[1]
        && soul::origin(soul::nested(soul::nested(&root, child_id), grand_id)) == origins[2], 0);
    let (child, edit) = soul::begin_nested_update(&mut root, child_id, 1); soul::commit_nested_update(&mut root, edit, child);
    let mut child = soul::unnest(&mut root, child_id, 2); let grand = soul::unnest(&mut child, grand_id, 1);
    assert!(object::id(&child) == child_id && object::id(&grand) == grand_id, 1);
    transfer::public_transfer(child, @0xb); transfer::public_transfer(grand, @0xb); sc.return_to_sender(root); sc.end();
}
#[test]
fun fresh_child_existing_parent_closes_by_value_and_delivers_parent_to_recipient() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx());
    let c = fresh(&p, sc.ctx()); let parent_id = deliver(&p, c, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa);
    sc.next_tx(@0xa); let parent: Soul = sc.take_from_sender(); let q = producer::create(sc.ctx()); let child = fresh(&q, sc.ctx());
    let child_id = soul::construction_id(&child); let auth = producer::complete(&q, soul::construction_ref(&child), soul::construction_snapshot(&child), sc.ctx());
    let parent = soul::nest_into_parent(parent, child, auth, 0, sc.ctx()); assert!(soul::parent_id(&parent) == parent_id, 0);
    soul::deliver_parent(parent, @0xb, sc.ctx()); transfer::public_transfer(q, @0xa);
    sc.next_tx(@0xb); let mut parent: Soul = sc.take_from_sender(); let child = soul::unnest(&mut parent, child_id, 1);
    assert!(object::id(&parent) == parent_id && object::id(&child) == child_id, 1); transfer::public_transfer(child, @0xb); sc.return_to_sender(parent); sc.end();
}
#[test]
fun existing_parent_delivery_merges_into_fresh_outer_closure() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx());
    let existing_id = deliver(&p, c, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa);
    sc.next_tx(@0xa); let existing: Soul = sc.take_from_sender(); let p = producer::create(sc.ctx());
    let mut outer = fresh(&p, sc.ctx()); let child = fresh(&p, sc.ctx()); let child_id = soul::construction_id(&child);
    let auth = producer::complete(&p, soul::construction_ref(&child), soul::construction_snapshot(&child), sc.ctx());
    let parent = soul::nest_into_parent(existing, child, auth, 0, sc.ctx()); soul::nest_parent_delivery(&mut outer, parent, 0, sc.ctx());
    let outer_id = deliver(&p, outer, @0xb, sc.ctx()); transfer::public_transfer(p, @0xa);
    sc.next_tx(@0xb); let s: Soul = sc.take_from_sender();
    assert!(object::id(&s) == outer_id && object::id(soul::nested(&s, existing_id)) == existing_id
        && object::id(soul::nested(soul::nested(&s, existing_id), child_id)) == child_id, 0); sc.return_to_sender(s); sc.end();
}
#[test]
fun same_ptb_fresh_native_rearrangement_retains_all_obligations() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let mut outer = fresh(&p, sc.ctx());
    let mut child = fresh(&p, sc.ctx()); let grand = fresh(&p, sc.ctx()); let grand_id = soul::construction_id(&grand);
    nest(&p, &mut child, grand, sc.ctx()); let child_id = soul::construction_id(&child); nest(&p, &mut outer, child, sc.ctx());
    let root = soul::construction_mut(&mut outer); let (mut child, edit) = soul::begin_nested_update(root, child_id, 1);
    let grand = soul::unnest(&mut child, grand_id, 1); soul::commit_nested_update(root, edit, child); soul::nest(root, grand, 2);
    deliver(&p, outer, @0xb, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test]
fun cancel_only_own_untouched_empty_allocation() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx());
    soul::cancel_empty(c, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test]
fun genuine_paid_action_and_nonfresh_completion_bind_actual_target_route_operation() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx());
    let snapshot = soul::construction_snapshot(&c); let action = producer::action(&p, soul::construction_ref(&c), snapshot, sc.ctx());
    assert!(producer_origin::action_producer(&action) == type_name::with_defining_ids<producer::ManufacturingProducer>(), 1);
    let (attested, receipt) = producer::consume_action(action, soul::construction_ref(&c), 0, sc.ctx());
    assert!(attested == snapshot && receipt == vector::tabulate!(32, |_| 5), 0);
    let auth = producer::complete(&p, soul::construction_ref(&c), snapshot, sc.ctx());
    producer::consume_completion(auth, soul::construction_ref(&c), &snapshot, sc.ctx());
    deliver(&p, c, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=9, location=soulidity_standard::soul)]
fun mutable_swap_cannot_deliver_replacement_root() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let mut a = fresh(&p, sc.ctx()); let mut b = fresh(&p, sc.ctx());
    let auth = producer::complete(&p, soul::construction_ref(&a), soul::construction_snapshot(&a), sc.ctx());
    let (a, b) = soul::swap_roots_for_testing(a, b); soul::deliver(a, auth, @0xa, sc.ctx());
    soul::cancel_empty(b, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=9, location=soulidity_standard::soul)]
fun mutable_swap_cannot_discard_replacement_via_cancel() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let mut a = fresh(&p, sc.ctx()); let mut b = fresh(&p, sc.ctx());
    let (a, b) = soul::swap_roots_for_testing(a, b); soul::cancel_empty(a, sc.ctx()); soul::cancel_empty(b, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=11, location=soulidity_standard::soul)]
fun fresh_child_unnest_share_cannot_drop_delivery_obligation() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let mut root = fresh(&p, sc.ctx()); let child = fresh(&p, sc.ctx()); let child_id = soul::construction_id(&child);
    nest(&p, &mut root, child, sc.ctx()); let child = soul::unnest(soul::construction_mut(&mut root), child_id, 1); transfer::public_share_object(child);
    deliver(&p, root, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=11, location=soulidity_standard::soul)]
fun fresh_grandchild_unnest_cannot_hide_behind_retained_child() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let mut root = fresh(&p, sc.ctx()); let mut child = fresh(&p, sc.ctx()); let grand = fresh(&p, sc.ctx());
    let grand_id = soul::construction_id(&grand); nest(&p, &mut child, grand, sc.ctx()); let child_id = soul::construction_id(&child); nest(&p, &mut root, child, sc.ctx());
    let s = soul::construction_mut(&mut root); let (mut child, edit) = soul::begin_nested_update(s, child_id, 1);
    let grand = soul::unnest(&mut child, grand_id, 1); transfer::public_transfer(grand, @0xa); soul::commit_nested_update(s, edit, child);
    deliver(&p, root, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=2, location=soulidity_standard::soul)]
fun begin_nested_update_keeps_root_unready_until_exact_child_return() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let mut root = fresh(&p, sc.ctx()); let child = fresh(&p, sc.ctx()); let child_id = soul::construction_id(&child);
    nest(&p, &mut root, child, sc.ctx()); let (child, edit) = soul::begin_nested_update(soul::construction_mut(&mut root), child_id, 1);
    let auth = producer::complete(&p, soul::construction_ref(&root), soul::construction_snapshot(&root), sc.ctx()); soul::deliver(root, auth, @0xa, sc.ctx());
    let mut other = fresh(&p, sc.ctx()); soul::commit_nested_update(soul::construction_mut(&mut other), edit, child); deliver(&p, other, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=11, location=soulidity_standard::soul)]
fun existing_parent_child_cannot_be_unnested_before_parent_delivery() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let raw = soul::raw_from_request_for_testing(producer::request<Soul>(&p, 0, sc.ctx()), sc.ctx());
    let child = fresh(&p, sc.ctx()); let child_id = soul::construction_id(&child); let auth = producer::complete(&p, soul::construction_ref(&child), soul::construction_snapshot(&child), sc.ctx());
    let mut parent = soul::nest_into_parent(raw, child, auth, 0, sc.ctx()); let child = soul::unnest(soul::parent_mut(&mut parent), child_id, 1); transfer::public_share_object(child);
    soul::deliver_parent(parent, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=11, location=soulidity_standard::soul)]
fun contribution_operation_cannot_allocate_fresh_soul() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = soul::new(producer::request<Soul>(&p, 1, sc.ctx()), sc.ctx());
    deliver(&p, c, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=2, location=soulidity_origin_protocol::producer_origin)]
fun completion_for_other_allocated_target_cannot_deliver_original() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let a = fresh(&p, sc.ctx()); let b = fresh(&p, sc.ctx());
    let auth = producer::complete(&p, soul::construction_ref(&b), soul::construction_snapshot(&a), sc.ctx()); soul::deliver(a, auth, @0xa, sc.ctx());
    soul::cancel_empty(b, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=1, location=private_source::producer)]
fun copied_snapshot_cannot_authorize_another_real_source() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let q = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx());
    let auth = producer::complete(&q, soul::construction_ref(&c), soul::construction_snapshot(&c), sc.ctx()); soul::deliver(c, auth, @0xa, sc.ctx());
    transfer::public_transfer(p, @0xa); transfer::public_transfer(q, @0xa); sc.end();
}
#[test, expected_failure(abort_code=4, location=soulidity_origin_protocol::producer_origin)]
fun paid_action_wrong_adapter_route_rejected() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx());
    let action = producer::action(&p, soul::construction_ref(&c), soul::construction_snapshot(&c), sc.ctx());
    let (_, _) = producer_origin::consume_action(action, WrongAdapter {}, WrongRevision {}, soul::construction_ref(&c), 0, sc.ctx());
    deliver(&p, c, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=4, location=soulidity_origin_protocol::producer_origin)]
fun paid_action_wrong_operation_rejected() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx());
    let action = producer::action(&p, soul::construction_ref(&c), soul::construction_snapshot(&c), sc.ctx());
    let (_, _) = producer::consume_action(action, soul::construction_ref(&c), 1, sc.ctx()); deliver(&p, c, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}

public struct WrapperWitness has drop {}
public struct Wrapper has key, store { id: UID, child: Soul }
#[test, expected_failure(abort_code=11, location=soulidity_standard::soul)]
fun custom_wrapper_cannot_hide_native_fresh_child_obligation() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let mut root = fresh(&p, sc.ctx()); let child = fresh(&p, sc.ctx()); let child_id = soul::construction_id(&child);
    nest(&p, &mut root, child, sc.ctx()); let child = soul::unnest(soul::construction_mut(&mut root), child_id, 1);
    let wrapper = Wrapper { id: object::new(sc.ctx()), child };
    soul::install(soul::construction_mut(&mut root), WrapperWitness {}, b"wrapper", wrapper, 1, true, vector::tabulate!(32, |_| 4), 2);
    deliver(&p, root, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=11, location=soulidity_standard::soul)]
fun fresh_child_party_transfer_cannot_drop_parent_obligation() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let mut root = fresh(&p, sc.ctx()); let child = fresh(&p, sc.ctx()); let child_id = soul::construction_id(&child);
    nest(&p, &mut root, child, sc.ctx()); let child = soul::unnest(soul::construction_mut(&mut root), child_id, 1);
    transfer::public_party_transfer(child, sui::party::single_owner(@0xb));
    deliver(&p, root, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=4, location=soulidity_origin_protocol::producer_origin)]
fun completion_wrong_revision_only_rejected() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx()); let snapshot = soul::construction_snapshot(&c);
    let auth = producer::complete(&p, soul::construction_ref(&c), snapshot, sc.ctx());
    producer_origin::consume_completion<producer::Adapter, WrongRevision, Soul>(auth, soul::construction_ref(&c), &snapshot, sc.ctx());
    deliver(&p, c, @0xa, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}
#[test, expected_failure(abort_code=11, location=soulidity_standard::soul)]
fun different_actor_cannot_deliver_bound_request() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx());
    let auth = producer::complete(&p, soul::construction_ref(&c), soul::construction_snapshot(&c), sc.ctx());
    transfer::public_transfer(p, @0xa); sc.next_tx(@0xb); soul::deliver(c, auth, @0xb, sc.ctx()); sc.end();
}
#[test]
fun actor_approved_original_zero_address_recipient_domain_is_preserved() {
    let mut sc = test_scenario::begin(@0xa); let p = producer::create(sc.ctx()); let c = fresh(&p, sc.ctx());
    deliver(&p, c, @0x0, sc.ctx()); transfer::public_transfer(p, @0xa); sc.end();
}

/// Preserve the original constructor's actor domain; producer policy remains
/// with the genuine source rather than a new zero-address kernel restriction.
#[test]
fun original_zero_actor_domain_has_genuine_source_and_private_delivery() {
    let mut sc = test_scenario::begin(@0x0); let p = producer::create(sc.ctx());
    let c = fresh(&p, sc.ctx()); let root = soul::construction_id(&c);
    let origin = soul::origin(soul::construction_ref(&c));
    assert!(soul::minted_by(&origin) == @0x0 && soul::source(&origin) == object::id(&p), 0);
    deliver(&p, c, @0xb, sc.ctx()); transfer::public_transfer(p, @0x0);
    sc.next_tx(@0xb); let s: Soul = sc.take_from_sender();
    assert!(object::id(&s) == root && soul::origin(&s) == origin, 1);
    sc.return_to_sender(s); sc.end();
}
