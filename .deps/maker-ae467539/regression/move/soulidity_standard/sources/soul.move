/// Application-independent asset root. No mutable UID or mutable-child escape.
module soulidity_standard::soul;

use std::bcs;
use std::hash;
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::dynamic_object_field as dof;
use sui::event;
use soulidity_origin_protocol::producer_origin::{Self, Snapshot, OriginRequest, CompletionAuthorization};

const ERevision: u64 = 1;
const EEditing: u64 = 2;
const EAuthority: u64 = 3;
const EType: u64 = 4;
const EInput: u64 = 5;
const EDuplicate: u64 = 6;
const ECapacity: u64 = 7;
const EPermanent: u64 = 8;
const EIdentity: u64 = 9;
const ESchema: u64 = 10;
const MAX_MODULES: u64 = 64;
const MAX_CHILD_BYTES: u64 = 245760;

/// Package ownership proof for standard Sui integrations such as a real
/// TransferPolicy<Soul>. The kernel does not install rules or depend on a market.
public struct SOUL has drop {}
fun init(w: SOUL, ctx: &mut TxContext) { sui::package::claim_and_keep(w, ctx) }
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(SOUL {}, ctx) }

public struct Soul has key, store {
    id: UID,
    schema: u16,
    name: String,
    revision: u64,
    nesting_revision: u64,
    origin: Origin,
    modules: vector<Descriptor>,
    editing: bool,
}

/// Source identity is an actual object input. Version/hash are its module's
/// attestation, not a kernel interpretation of a Maker or a storage service.
public struct Origin has copy, drop, store {
    producer: TypeName,
    source_type: TypeName,
    source: ID,
    source_version: u64,
    source_hash: vector<u8>,
    minted_by: address,
}

public struct Descriptor has copy, drop, store {
    namespace: TypeName,
    name: vector<u8>,
    value_type: TypeName,
    object: ID,
    schema: u16,
    removable: bool,
    handover_required: bool,
    revision: u64,
    body_hash: vector<u8>,
    semantic_hash: vector<u8>,
}

/// Private constructor and typed DOF keys isolate every application namespace.
public struct ModuleKey<phantom W> has copy, drop, store { name: vector<u8> }

/// Canonical native nesting namespace. A nested Soul remains a distinct asset,
/// never a new form of its parent. Constructor stays inside this module.
public struct NestedSoulWitness has drop {}

/// No abilities: successful transactions must restore this exact child into
/// this exact Soul. Permanent modules can be edited but cannot be withdrawn.
public struct Edit<phantom W, phantom T> {
    soul: ID,
    object: ID,
    name: vector<u8>,
    revision: u64,
}

public struct Changed has copy, drop {
    soul: ID, revision: u64, operation: u8,
    namespace: TypeName, name: vector<u8>, object: ID,
}

public struct Manifest has copy, drop, store {
    domain: vector<u8>, soul: ID, schema: u16, name: String,
    revision: u64, origin: Origin, modules: vector<Descriptor>,
}

fun same_module<W, T>() {
    let w = type_name::with_original_ids<W>();
    let t = type_name::with_original_ids<T>();
    assert!(!w.is_primitive() && !t.is_primitive(), EAuthority);
    assert!(w.address_string() == t.address_string()
        && w.module_string() == t.module_string(), EAuthority);
}

fun hash32(value: &vector<u8>) { assert!(value.length() == 32, EInput) }
fun check_name(value: &vector<u8>) {
    assert!(value.length() > 0 && value.length() <= 64, EInput)
}
fun ready(s: &Soul) { assert!(s.schema == 1 && !s.editing, EEditing) }
fun cas(s: &Soul, expected: u64) { assert!(s.revision == expected, ERevision) }
// Root contents use Sui's execution-level Move object size bound. Imposing a
// smaller name/root ceiling here changes the original native metadata domain.
fun child_hash<T>(value: &T): vector<u8> {
    let bytes = bcs::to_bytes(value);
    assert!(bytes.length() <= MAX_CHILD_BYTES, ECapacity);
    hash::sha3_256(bytes)
}

#[test_only]
public fun new_for_testing<W: drop, P: key>(
    witness: W, source: &P, source_version: u64,
    source_hash: vector<u8>, name: String, ctx: &mut TxContext,
): Soul {
    same_module<W, P>(); let _ = witness;
    // Same-module public metadata values also have drop. Only the producer's
    // designated marker may attest issuance; its constructor must remain private.
    assert!(*type_name::with_original_ids<W>().datatype_string().as_bytes()==b"SoulProducer",EAuthority);
    hash32(&source_hash);
    assert!(source_version > 0, EInput);
    let s = Soul {
        id: object::new(ctx), schema: 1, name, revision: 0, nesting_revision: 0, modules: vector[], editing: false,
        origin: Origin {
            producer: type_name::with_defining_ids<W>(),
            source_type: type_name::with_defining_ids<P>(), source: object::id(source),
            source_version, source_hash, minted_by: ctx.sender(),
        },
    };
    s
}

fun find<W>(s: &Soul, name: &vector<u8>): Option<u64> {
    let namespace = type_name::with_defining_ids<W>();
    let mut i = 0;
    while (i < s.modules.length()) {
        if (s.modules[i].namespace == namespace && s.modules[i].name == *name)
            return option::some(i);
        i = i + 1
    };
    option::none()
}

fun index<W, T>(s: &Soul, name: &vector<u8>): u64 {
    let found = find<W>(s, name);
    assert!(found.is_some(), EType);
    let i = found.destroy_some();
    assert!(s.modules[i].value_type == type_name::with_defining_ids<T>(), EType);
    i
}

fun changed(s: &mut Soul, operation: u8, d: &Descriptor) {
    s.revision = s.revision + 1;
    event::emit(Changed {
        soul: object::id(s), revision: s.revision, operation,
        namespace: d.namespace, name: d.name, object: d.object,
    })
}

public fun install<W: drop, T: key + store>(
    s: &mut Soul, witness: W, name: vector<u8>, value: T,
    schema: u16, removable: bool, semantic_hash: vector<u8>, expected: u64,
) {
    install_declared(s, witness, name, value, schema, removable, false, semantic_hash, expected)
}

/// A protected namespace is an installed duty, not an optional exit callback.
/// same_module checks nominal source identity. Protection also relies on the
/// audited source keeping its designated W constructor and acknowledgment private.
public fun install_protected<W: drop, T: key + store>(
    s: &mut Soul, witness: W, name: vector<u8>, value: T,
    schema: u16, removable: bool, semantic_hash: vector<u8>, expected: u64,
) {
    install_declared(s, witness, name, value, schema, removable, true, semantic_hash, expected)
}
fun native_namespace<W, T>(): bool {
    type_name::with_defining_ids<W>() == type_name::with_defining_ids<NestedSoulWitness>()
        && type_name::with_defining_ids<T>() == type_name::with_defining_ids<Soul>()
}
fun install_declared<W: drop, T: key + store>(
    s: &mut Soul, witness: W, name: vector<u8>, value: T,
    schema: u16, removable: bool, handover_required: bool,
    semantic_hash: vector<u8>, expected: u64,
) {
    ready(s); cas(s, expected); same_module<W, T>(); let _ = witness;
    // Public Standard metadata has drop and can satisfy nominal same_module.
    // Canonical Souls therefore enter only the genuine private native namespace;
    // an unrelated foreign Soul type retains the ordinary generic tool domain.
    if (type_name::with_defining_ids<T>() == type_name::with_defining_ids<Soul>())
        assert!(native_namespace<W, T>(), EAuthority);
    check_name(&name); hash32(&semantic_hash); assert!(schema > 0, ESchema);
    assert!(find<W>(s, &name).is_none(), EDuplicate);
    assert!(s.modules.length() < MAX_MODULES, ECapacity);
    let d = Descriptor {
        namespace: type_name::with_defining_ids<W>(), name,
        value_type: type_name::with_defining_ids<T>(), object: object::id(&value),
        schema, removable, handover_required, revision: 0, body_hash: child_hash(&value), semantic_hash,
    };
    dof::add(&mut s.id, ModuleKey<W> { name }, value);
    s.modules.push_back(d);
    if (native_namespace<W, T>()) s.nesting_revision = s.nesting_revision + 1;
    changed(s, 0, &d)
}

public fun borrow_module<W, T: key + store>(s: &Soul, name: vector<u8>): &T {
    ready(s); let _ = index<W, T>(s, &name);
    dof::borrow(&s.id, ModuleKey<W> { name })
}

public fun uninstall<W, T: key + store>(s: &mut Soul, name: vector<u8>, expected: u64): T {
    ready(s); cas(s, expected);
    let i = index<W, T>(s, &name); let d = s.modules[i];
    assert!(d.removable && !d.handover_required, EPermanent);
    let value = dof::remove<ModuleKey<W>, T>(&mut s.id, ModuleKey<W> { name });
    assert!(object::id(&value) == d.object, EIdentity);
    s.modules.remove(i);
    if (native_namespace<W, T>()) s.nesting_revision = s.nesting_revision + 1;
    changed(s, 1, &d); value
}

public fun begin_update<W: drop, T: key + store>(
    s: &mut Soul, witness: W, name: vector<u8>, expected: u64,
): (T, Edit<W, T>) {
    ready(s); cas(s, expected); same_module<W, T>(); let _ = witness;
    let i = index<W, T>(s, &name); let id = s.modules[i].object;
    let value = dof::remove<ModuleKey<W>, T>(&mut s.id, ModuleKey<W> { name });
    assert!(object::id(&value) == id, EIdentity);
    s.editing = true;
    (value, Edit { soul: object::id(s), object: id, name, revision: expected })
}

public fun commit_update<W: drop, T: key + store>(
    s: &mut Soul, ticket: Edit<W, T>, witness: W, value: T,
    schema: u16, semantic_hash: vector<u8>,
) {
    same_module<W, T>(); let _ = witness; hash32(&semantic_hash);
    let Edit { soul, object: id, name, revision } = ticket;
    assert!(s.editing && soul == object::id(s) && id == object::id(&value), EIdentity);
    cas(s, revision);
    let i = index<W, T>(s, &name);
    let mut d = s.modules[i];
    assert!(d.object == id, EIdentity); assert!(schema >= d.schema, ESchema);
    d.schema = schema; d.revision = d.revision + 1; d.body_hash = child_hash(&value); d.semantic_hash = semantic_hash;
    dof::add(&mut s.id, ModuleKey<W> { name }, value);
    *s.modules.borrow_mut(i) = d; s.editing = false; changed(s, 2, &d)
}

public fun revision(s: &Soul): u64 { s.revision }
public fun schema(s: &Soul): u16 { s.schema }
public fun name(s: &Soul): &String { &s.name }
public fun origin(s: &Soul): Origin { s.origin }
public fun source(o: &Origin): ID { o.source }
public fun source_type(o: &Origin): TypeName { o.source_type }
public fun producer(o: &Origin): TypeName { o.producer }
public fun source_version(o: &Origin): u64 { o.source_version }
public fun source_hash(o: &Origin): vector<u8> { o.source_hash }
public fun minted_by(o: &Origin): address { o.minted_by }
public fun module_count(s: &Soul): u64 { ready(s); s.modules.length() }
public fun descriptor<W>(s: &Soul, name: vector<u8>): Option<Descriptor> {
    ready(s); find<W>(s, &name).map!(|i| s.modules[i])
}
public fun module_page(s: &Soul, offset: u64, limit: u64): vector<Descriptor> {
    ready(s); assert!(limit <= MAX_MODULES && offset <= s.modules.length(), EInput);
    let end = if (limit < s.modules.length() - offset) offset + limit else s.modules.length();
    let mut result = vector[]; let mut i = offset;
    while (i < end) { result.push_back(s.modules[i]); i = i + 1 };
    result
}
public fun module_id(d: &Descriptor): ID { d.object }
public fun namespace(d: &Descriptor): TypeName { d.namespace }
public fun module_name(d: &Descriptor): vector<u8> { d.name }
public fun value_type(d: &Descriptor): TypeName { d.value_type }
public fun module_schema(d: &Descriptor): u16 { d.schema }
public fun removable(d: &Descriptor): bool { d.removable }
public fun handover_required(d: &Descriptor): bool { d.handover_required }
public fun module_revision(d: &Descriptor): u64 { d.revision }
public fun body_hash(d: &Descriptor): vector<u8> { d.body_hash }
public fun semantic_hash(d: &Descriptor): vector<u8> { d.semantic_hash }
public fun manifest(s: &Soul): Manifest {
    ready(s); Manifest {
        domain: b"soulidity/standard/manifest/v1", soul: object::id(s), schema: s.schema,
        name: s.name, revision: s.revision, origin: s.origin, modules: s.modules,
    }
}
public fun manifest_hash(s: &Soul): vector<u8> { hash::sha3_256(bcs::to_bytes(&manifest(s))) }
public fun assert_manifest(s: &Soul, expected_revision: u64, expected_hash: vector<u8>) {
    ready(s); cas(s, expected_revision); hash32(&expected_hash);
    assert!(manifest_hash(s) == expected_hash, EInput)
}

/// Native whole-asset composition. Unnesting is always available to the actual
/// parent holder; no application can turn this namespace into a permanent lock.
public fun nest(s: &mut Soul, child: Soul, expected: u64) {
    let id = object::id(&child);
    assert!(id != object::id(s), EIdentity);
    let semantic = manifest_hash(&child);
    install(s, NestedSoulWitness {}, bcs::to_bytes(&id), child, 1, true, semantic, expected)
}
public fun nested(s: &Soul, child: ID): &Soul {
    borrow_module<NestedSoulWitness, Soul>(s, bcs::to_bytes(&child))
}
public fun unnest(s: &mut Soul, child: ID, expected: u64): Soul {
    uninstall<NestedSoulWitness, Soul>(s, bcs::to_bytes(&child), expected)
}
/// PTB-compatible value path. No mutable child/root UID or reference escapes;
/// edited child must return under the same parent with the same object ID.
public fun begin_nested_update(s: &mut Soul, child: ID, expected: u64): (Soul, Edit<NestedSoulWitness, Soul>) {
    begin_update(s, NestedSoulWitness {}, bcs::to_bytes(&child), expected)
}
public fun commit_nested_update(s: &mut Soul, ticket: Edit<NestedSoulWitness, Soul>, child: Soul) {
    let semantic = manifest_hash(&child);
    commit_update(s, ticket, NestedSoulWitness {}, child, 1, semantic)
}

const EConstruction: u64 = 11;
/// Opaque linear fresh-root custody. A mutable root reference supports original
/// initialization, but cannot remove the independently pinned delivery duties.
public struct Construction {
    root: Soul, root_id: ID, fixed_origin: Origin, request: Snapshot,
    actor: address, obligations: vector<Obligation>,
}
/// An existing owned parent is held by value until all newly inserted roots are
/// delivered with it. Ref-only closure would permit a later unnest/share bypass.
public struct ParentDelivery {
    root: Soul, root_id: ID, fixed_origin: Origin, actor: address,
    obligations: vector<Obligation>,
}
public struct Obligation has copy, drop { root: ID, origin: Origin, fresh: bool }

fun attested_origin(snapshot: &Snapshot): Origin {
    Origin {
        producer: producer_origin::producer(snapshot),
        source_type: producer_origin::source_type(snapshot),
        source: producer_origin::source(snapshot),
        source_version: producer_origin::version(snapshot),
        source_hash: producer_origin::policy(snapshot),
        minted_by: producer_origin::actor(snapshot),
    }
}
/// This is the production defining constructor: UID is allocated and Soul is
/// packed here, never supplied as an arbitrary parameter or returned bare.
public fun new(request: OriginRequest, ctx: &mut TxContext): Construction {
    let request = producer_origin::consume_request<Soul>(request, ctx);
    assert!(producer_origin::operation(&request) == 0, EConstruction);
    let fixed_origin = attested_origin(&request);
    let root = Soul {
        id: object::new(ctx), schema: 1, name: producer_origin::name(&request),
        revision: 0, nesting_revision: 0, origin: fixed_origin, modules: vector[], editing: false,
    };
    let root_id = object::id(&root);
    Construction {
        root, root_id, fixed_origin, actor: ctx.sender(), request,
        obligations: vector[Obligation { root: root_id, origin: fixed_origin, fresh: true }],
    }
}
public fun new_from_origin(request: OriginRequest, ctx: &mut TxContext): Construction { new(request, ctx) }
public fun construction_id(c: &Construction): ID { pinned_construction(c); c.root_id }
public fun construction_snapshot(c: &Construction): Snapshot { pinned_construction(c); c.request }
public fun construction_ref(c: &Construction): &Soul { pinned_construction(c); &c.root }
public fun construction_mut(c: &mut Construction): &mut Soul { pinned_construction(c); &mut c.root }
public fun borrow_construction(c: &Construction): &Soul { construction_ref(c) }
public fun borrow_construction_mut(c: &mut Construction): &mut Soul { construction_mut(c) }
fun pinned(root: &Soul, root_id: ID, fixed_origin: Origin) {
    assert!(object::id(root) == root_id && root.origin == fixed_origin, EIdentity)
}
fun pinned_construction(c: &Construction) {
    pinned(&c.root, c.root_id, c.fixed_origin);
    assert!(c.fixed_origin == attested_origin(&c.request)
        && c.actor == producer_origin::actor(&c.request), EConstruction)
}
fun pinned_parent(p: &ParentDelivery) { pinned(&p.root, p.root_id, p.fixed_origin) }
/// Only native nested Souls are in this supported closure. The search has no
/// introduced depth/count ceiling; Sui execution/object limits still apply.
fun reachable_origin(root: &Soul, id: ID): Option<Origin> {
    ready(root);
    if (object::id(root) == id) return option::some(root.origin);
    let mut i = 0;
    while (i < root.modules.length()) {
        let d = &root.modules[i];
        if (d.namespace == type_name::with_defining_ids<NestedSoulWitness>()
            && d.value_type == type_name::with_defining_ids<Soul>()) {
            let child = dof::borrow<ModuleKey<NestedSoulWitness>, Soul>(
                &root.id, ModuleKey<NestedSoulWitness> { name: d.name },
            );
            assert!(object::id(child) == d.object, EIdentity);
            let found = reachable_origin(child, id);
            if (found.is_some()) return found;
        };
        i = i + 1
    };
    option::none()
}
fun closure(root: &Soul, obligations: &vector<Obligation>) {
    let mut i = 0;
    while (i < obligations.length()) {
        let o = &obligations[i]; let found = reachable_origin(root, o.root);
        assert!(found.is_some() && found.destroy_some() == o.origin, EConstruction);
        i = i + 1
    }
}
/// Freshness is private constructor evidence, never caller metadata. A raw
/// existing Soul inserted through nest has no true creation obligation.
fun fresh_node(s: &Soul, obligations: &vector<Obligation>): bool {
    let mut result = false;
    obligations.do_ref!(|o| { if (o.fresh && o.root == object::id(s) && o.origin == s.origin) result = true; });
    result
}
fun existing_protected(s: &Soul, obligations: &vector<Obligation>): bool {
    ready(s); let mut protected = false;
    s.modules.do_ref!(|d| { if (d.handover_required) protected = true; });
    if (protected && !fresh_node(s, obligations)) return true;
    let mut i = 0;
    // Genesis retains original execution/object bounds; this helper does not
    // impose the bounded supported-handover depth/node ceiling on fresh births.
    while (i < s.modules.length()) {
        let d = &s.modules[i];
        if (d.namespace == type_name::with_defining_ids<NestedSoulWitness>()) {
            assert!(d.value_type == type_name::with_defining_ids<Soul>(), EIdentity);
            let child = dof::borrow<ModuleKey<NestedSoulWitness>, Soul>(&s.id, ModuleKey<NestedSoulWitness> { name: d.name });
            assert!(object::id(child) == d.object, EIdentity);
            if (existing_protected(child, obligations)) return true
        };
        i = i + 1
    }; false
}
fun merge(target: &mut vector<Obligation>, mut incoming: vector<Obligation>) {
    while (!incoming.is_empty()) target.push_back(incoming.pop_back());
    incoming.destroy_empty()
}
public fun deliver(c: Construction, completion: CompletionAuthorization, recipient: address, ctx: &TxContext): ID {
    pinned_construction(&c);
    assert!(ctx.sender() == c.actor, EConstruction);
    closure(&c.root, &c.obligations);
    assert!(recipient == c.actor || !existing_protected(&c.root, &c.obligations), EHandover);
    producer_origin::consume_delivery(completion, &c.root, &c.request, ctx);
    let Construction { root, root_id, fixed_origin: _, request: _, actor: _, obligations: _ } = c;
    transfer::public_transfer(root, recipient); root_id
}
/// Cancellation deletes only its own untouched empty allocation. No replacement
/// root, nested obligation, or initialized child can be discarded by this exit.
public fun cancel_empty(c: Construction, ctx: &TxContext) {
    pinned_construction(&c);
    assert!(ctx.sender() == c.actor && c.obligations.length() == 1
        && c.root.modules.is_empty() && c.root.revision == 0, EConstruction);
    closure(&c.root, &c.obligations);
    let Construction { root, root_id: _, fixed_origin: _, request: _, actor: _, obligations: _ } = c;
    let Soul { id, schema: _, name: _, revision: _, nesting_revision: _, origin: _, modules: _, editing: _ } = root;
    object::delete(id)
}
public fun nest_construction(parent: &mut Construction, child: Construction,
    completion: CompletionAuthorization, expected: u64, ctx: &TxContext,
) {
    pinned_construction(parent); pinned_construction(&child);
    assert!(parent.actor == ctx.sender() && child.actor == parent.actor, EConstruction);
    closure(&child.root, &child.obligations);
    producer_origin::consume_delivery(completion, &child.root, &child.request, ctx);
    let Construction { root, root_id: _, fixed_origin: _, request: _, actor: _, obligations } = child;
    nest(&mut parent.root, root, expected); merge(&mut parent.obligations, obligations)
}
public fun nest_into_parent(mut parent: Soul, child: Construction,
    completion: CompletionAuthorization, expected: u64, ctx: &TxContext,
): ParentDelivery {
    ready(&parent); pinned_construction(&child);
    assert!(child.actor == ctx.sender(), EConstruction);
    closure(&child.root, &child.obligations);
    producer_origin::consume_delivery(completion, &child.root, &child.request, ctx);
    let root_id = object::id(&parent); let fixed_origin = parent.origin;
    let Construction { root, root_id: _, fixed_origin: _, request: _, actor: _, obligations } = child;
    nest(&mut parent, root, expected);
    let mut all = vector[Obligation { root: root_id, origin: fixed_origin, fresh: false }]; merge(&mut all, obligations);
    ParentDelivery { root: parent, root_id, fixed_origin, actor: ctx.sender(), obligations: all }
}
public fun parent_id(p: &ParentDelivery): ID { pinned_parent(p); p.root_id }
public fun parent_ref(p: &ParentDelivery): &Soul { pinned_parent(p); &p.root }
public fun parent_mut(p: &mut ParentDelivery): &mut Soul { pinned_parent(p); &mut p.root }
public fun nest_into_delivery(parent: &mut ParentDelivery, child: Construction,
    completion: CompletionAuthorization, expected: u64, ctx: &TxContext,
) {
    pinned_parent(parent); pinned_construction(&child);
    assert!(parent.actor == ctx.sender() && child.actor == parent.actor, EConstruction);
    closure(&child.root, &child.obligations);
    producer_origin::consume_delivery(completion, &child.root, &child.request, ctx);
    let Construction { root, root_id: _, fixed_origin: _, request: _, actor: _, obligations } = child;
    nest(&mut parent.root, root, expected); merge(&mut parent.obligations, obligations)
}
public fun deliver_parent(p: ParentDelivery, recipient: address, ctx: &TxContext): ID {
    pinned_parent(&p);
    assert!(p.actor == ctx.sender(), EConstruction);
    closure(&p.root, &p.obligations);
    assert!(recipient == p.actor || !existing_protected(&p.root, &p.obligations), EHandover);
    let ParentDelivery { root, root_id, fixed_origin: _, actor: _, obligations: _ } = p;
    transfer::public_transfer(root, recipient); root_id
}
public fun nest_parent_delivery(parent: &mut Construction, child: ParentDelivery, expected: u64, ctx: &TxContext) {
    pinned_construction(parent); pinned_parent(&child);
    assert!(parent.actor == ctx.sender() && child.actor == parent.actor, EConstruction);
    closure(&child.root, &child.obligations);
    let ParentDelivery { root, root_id: _, fixed_origin: _, actor: _, obligations } = child;
    nest(&mut parent.root, root, expected); merge(&mut parent.obligations, obligations)
}
/// Historical raw fixture only. It cannot appear in a production root build.
#[test_only]
public fun raw_from_request_for_testing(request: OriginRequest, ctx: &mut TxContext): Soul {
    let snapshot = producer_origin::consume_request<Soul>(request, ctx);
    assert!(producer_origin::operation(&snapshot) == 0, EConstruction);
    Soul { id: object::new(ctx), schema: 1, name: producer_origin::name(&snapshot),
        revision: 0, nesting_revision: 0, origin: attested_origin(&snapshot), modules: vector[], editing: false }
}

/// Deliberate internal corruption fixture to test independent pins at exits.
/// Foreign modules cannot repack Construction or move Soul from a reference.
#[test_only]
public fun swap_roots_for_testing(a: Construction, b: Construction): (Construction, Construction) {
    let Construction { root: ar, root_id: ai, fixed_origin: ao, request: aq, actor: aa, obligations: az } = a;
    let Construction { root: br, root_id: bi, fixed_origin: bo, request: bq, actor: ba, obligations: bz } = b;
    (Construction { root: br, root_id: ai, fixed_origin: ao, request: aq, actor: aa, obligations: az },
     Construction { root: ar, root_id: bi, fixed_origin: bo, request: bq, actor: ba, obligations: bz })
}

/// Optional pure Sui terminal. The borrowed actual cap is never returned.
public fun deliver_locked_with_cap(c:Construction,completion:CompletionAuthorization,k:&mut sui::kiosk::Kiosk,cap:&sui::kiosk::KioskOwnerCap,p:&sui::transfer_policy::TransferPolicy<Soul>,ctx:&TxContext):ID {
    pinned_construction(&c);assert!(ctx.sender()==c.actor,EConstruction);closure(&c.root,&c.obligations);
    assert!(!existing_protected(&c.root,&c.obligations),EHandover);
    producer_origin::consume_delivery(completion,&c.root,&c.request,ctx);
    assert!(sui::kiosk::owner(k)==ctx.sender() && sui::kiosk::has_access(k,cap),EAuthority);assert_legacy_disabled(k);
    let Construction{root,root_id,fixed_origin:_,request:_,actor:_,obligations:_}=c;
    sui::kiosk::lock(k,cap,p,root);root_id
}
public fun deliver_locked_cap(c:Construction,completion:CompletionAuthorization,k:&mut sui::kiosk::Kiosk,cap:sui::kiosk::KioskOwnerCap,p:&sui::transfer_policy::TransferPolicy<Soul>,ctx:&TxContext):ID {
    let id=deliver_locked_with_cap(c,completion,k,&cap,p,ctx);transfer::public_transfer(cap,ctx.sender());id
}
const ELegacyExtensions:u64=13;const EKioskLayout:u64=14;
/// Exact pinned Sui 2a0becb2 layout: UID(ID(address)), Balance<SUI>(u64),
/// owner(address), item_count(u32), allow_extensions(bool). No flag mutation.
public fun assert_legacy_disabled(k:&sui::kiosk::Kiosk) {
    let bytes=std::bcs::to_bytes(k);assert!(bytes.length()==77,EKioskLayout);
    let mut b=sui::bcs::new(bytes);let uid=b.peel_address();let profits=b.peel_u64();let owner=b.peel_address();let count=b.peel_u32();
    let flag=b.peel_u8();assert!(flag<=1,EKioskLayout);assert!(b.into_remainder_bytes().is_empty(),EKioskLayout);
    assert!(uid==object::id(k).to_address() && profits==sui::kiosk::profits_amount(k) && owner==sui::kiosk::owner(k) && count==sui::kiosk::item_count(k),EKioskLayout);
    assert!(flag==0,ELegacyExtensions)
}


// Fresh unpublished layout: persistent installed duties and native structural
// history. This is not ABI compatibility with historical published Souls.
const EHandover: u64 = 12;
const MAX_HANDOVER_DEPTH: u64 = 16;
const MAX_HANDOVER_NODES: u64 = 256;

/// No copy/drop/store/key: every transaction must discharge the actual owned
/// Soul through finish. References cannot move its Root, UID or private witness.
public struct Handover {
    root: Soul, nodes: vector<HandoverNode>, duties: vector<HandoverDuty>,
}
public struct HandoverNode has copy, drop {
    soul: ID, origin: Origin, parent: Option<ID>, name: vector<u8>, nesting_revision: u64,
}
public struct HandoverDuty has copy, drop {
    soul: ID, installed: Descriptor, acknowledged: Option<Descriptor>,
}

fun collect_handover(s: &Soul, parent: Option<ID>, name: vector<u8>, depth: u64,
    nodes: &mut vector<HandoverNode>, duties: &mut vector<HandoverDuty>,
) {
    ready(s);
    assert!(depth <= MAX_HANDOVER_DEPTH && nodes.length() < MAX_HANDOVER_NODES, ECapacity);
    let id = object::id(s);
    // Soul is privately packed with a fresh UID and is not copyable. Native
    // DOF ownership cannot duplicate a live Soul, so a quadratic ID scan adds
    // no authority check. Each edge and the complete final topology are checked.
    nodes.push_back(HandoverNode { soul: id, origin: s.origin, parent, name, nesting_revision: s.nesting_revision });
    s.modules.do_ref!(|d| {
        if (d.handover_required) duties.push_back(HandoverDuty { soul: id, installed: *d, acknowledged: option::none() });
        if (d.namespace == type_name::with_defining_ids<NestedSoulWitness>()) {
            assert!(d.value_type == type_name::with_defining_ids<Soul>() && d.schema == 1, EHandover);
            let child = dof::borrow<ModuleKey<NestedSoulWitness>, Soul>(&s.id, ModuleKey<NestedSoulWitness> { name: d.name });
            assert!(object::id(child) == d.object && child_hash(child) == d.body_hash, EHandover);
            collect_handover(child, option::some(id), d.name, depth + 1, nodes, duties)
        }
    })
}
public fun begin_handover(root: Soul): Handover {
    let mut nodes = vector[]; let mut duties = vector[];
    collect_handover(&root, option::none(), vector[], 0, &mut nodes, &mut duties);
    Handover { root, nodes, duties }
}
public fun handover_ref(h: &Handover): &Soul { &h.root }
public fun handover_mut(h: &mut Handover): &mut Soul { &mut h.root }
public fun handover_id(h: &Handover): ID { object::id(&h.root) }

fun same_duty(a: &Descriptor, b: &Descriptor): bool {
    a.namespace == b.namespace && a.name == b.name && a.value_type == b.value_type
        && a.object == b.object && a.schema == b.schema && a.handover_required && b.handover_required
}
fun duty_index(duties: &vector<HandoverDuty>, root: ID, d: &Descriptor): u64 {
    let mut i = 0;
    while (i < duties.length()) {
        if (duties[i].soul == root && same_duty(&duties[i].installed, d)) return i;
        i = i + 1
    }; abort EHandover
}
fun current_handover(h: &Handover): vector<HandoverDuty> {
    let mut nodes = vector[]; let mut duties = vector[];
    collect_handover(&h.root, option::none(), vector[], 0, &mut nodes, &mut duties);
    // Captures every native Soul, including an intermediate with no tools.
    assert!(nodes == h.nodes && duties.length() == h.duties.length(), EHandover);
    duties.do_ref!(|d| { let _ = duty_index(&h.duties, d.soul, &d.installed); });
    duties
}
fun acknowledge_tree<W, T: key + store>(s: &Soul, name: &vector<u8>, schema: u16,
    duties: &mut vector<HandoverDuty>,
) {
    if (find<W>(s, name).is_some()) {
        let i = index<W, T>(s, name); let d = s.modules[i];
        assert!(d.handover_required && d.schema == schema, EHandover);
        let actual: &T = dof::borrow(&s.id, ModuleKey<W> { name: *name });
        assert!(object::id(actual) == d.object && child_hash(actual) == d.body_hash, EHandover);
        let duty = duty_index(duties, object::id(s), &d);
        duties[duty].acknowledged = option::some(d)
    };
    s.modules.do_ref!(|d| {
        if (d.namespace == type_name::with_defining_ids<NestedSoulWitness>()) {
            let child = dof::borrow<ModuleKey<NestedSoulWitness>, Soul>(&s.id, ModuleKey<NestedSoulWitness> { name: d.name });
            acknowledge_tree<W, T>(child, name, schema, duties)
        }
    })
}
/// The source fixes the supported schema and invokes its full private clear or
/// rotation before supplying W. A copied descriptor/receipt is never authority.
public fun acknowledge_handover<W: drop, T: key + store>(h: &mut Handover,
    witness: W, name: vector<u8>, schema: u16,
) {
    same_module<W, T>(); let _ = witness;
    let _ = current_handover(h);
    acknowledge_tree<W, T>(&h.root, &name, schema, &mut h.duties)
}
/// Sole session sink: validates every current duty and sends the actual Soul
/// internally. There is no raw Root return or public cancellation escape.
fun validate_handover(h: &Handover) {
    let current = current_handover(h);
    current.do_ref!(|d| {
        let i = duty_index(&h.duties, d.soul, &d.installed);
        let stamp = &h.duties[i].acknowledged;
        assert!(stamp.is_some() && *stamp.borrow() == d.installed, EHandover)
    })
}
public fun finish_handover(h: Handover, recipient: address): ID {
    assert!(recipient != @0x0, EInput); validate_handover(&h);
    let Handover { root, nodes: _, duties: _ } = h;
    let id = object::id(&root); transfer::public_transfer(root, recipient); id
}
/// Same closure validation as the wallet terminal; the actual borrowed native
/// cap authorizes ordinary placement. Locked Soul issuance remains separate.
public fun finish_handover_place(h: Handover, k: &mut sui::kiosk::Kiosk,
    cap: &sui::kiosk::KioskOwnerCap): ID {
    validate_handover(&h);
    let Handover { root, nodes: _, duties: _ } = h;
    let id = object::id(&root); sui::kiosk::place(k, cap, root); id
}

/// Preserves original complete/source/actor/identity/closure duties before
/// converting by value to a mandatory handover. Never exports a raw Soul.
public fun begin_construction_handover(c: Construction, completion: CompletionAuthorization, ctx: &TxContext): Handover {
    pinned_construction(&c); assert!(ctx.sender() == c.actor, EConstruction);
    closure(&c.root, &c.obligations);
    producer_origin::consume_delivery(completion, &c.root, &c.request, ctx);
    let Construction { root, root_id: _, fixed_origin: _, request: _, actor: _, obligations: _ } = c;
    begin_handover(root)
}
public fun begin_parent_handover(p: ParentDelivery, ctx: &TxContext): Handover {
    pinned_parent(&p); assert!(ctx.sender() == p.actor, EConstruction);
    closure(&p.root, &p.obligations);
    let ParentDelivery { root, root_id: _, fixed_origin: _, actor: _, obligations: _ } = p;
    begin_handover(root)
}
