/// Actual wallet-owned pre-Complete selections. Preview data never grants issued rights.
module soulidity_maker_manufacturing::maker_player;
use sui::table::{Self,Table};
use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,Product};
use soulidity_model::policy::{Self,Source,Layout};
use soulidity_foundation::economics::{Self,Config};
use sui::clock::Clock;
use soulidity_visual::visual::{Self,Scene,ColorChoice,Layer};
use soulidity_maker_publication::output_data as output;
use soulidity_maker_publication::output_data::{RecipeSlot};
use soulidity_model::assembly::{Self,State,Scope,PartKey,ProfileSnapshot};
const EOwner:u64=1;const EBinding:u64=2;const ERevision:u64=3;const ESelection:u64=4;
public struct Player has key {id:UID,holder:address,protocol:ID,maker:ID,version:u64,revision:u64,selections:Table<PartKey,Selection>,scene:Scene,colors:vector<ColorChoice>,assembly:State}
public struct Selection has copy,drop,store {source:Source,layout:Layout}
public(package) fun create<C>(maker:&mut Product<C>,cfg:&Config<C>,version:u64,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext):ID{create_value(maker,cfg,version,fee_revision,expiry,attempt,clock,ctx,false)}
fun create_value<C>(maker:&mut Product<C>,cfg:&Config<C>,version:u64,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext,native_route:bool):ID{
    assert!(catalog::parent(maker).is_none() && catalog::protocol(maker)==object::id(cfg),EBinding);catalog::assert_active(maker);if(native_route)economics::assert_primary_live(cfg,fee_revision,expiry,clock) else economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock);
    catalog::ensure_access_value(maker,cfg,version,attempt,fee_revision,expiry,clock,ctx,native_route);let v=catalog::published(maker,version);catalog::assert_runtime_access_value(maker,cfg,version,catalog::policy_hash(v),catalog::manifest(v),fee_revision,economics::commitment(cfg),clock,ctx,native_route);
    let scene=*catalog::scene(v);let colors=visual::default_colors(&scene);let profile=catalog::assembly_profile(maker,version);let p=Player{id:object::new(ctx),holder:ctx.sender(),protocol:object::id(cfg),maker:object::id(maker),version,revision:0,selections:table::new(ctx),scene,colors,assembly:assembly::new(&profile,ctx)};assert_size(&p);
    let id=object::id(&p);transfer::transfer(p,ctx.sender());id
}
public(package) fun create_native<C,A:drop,R:drop,T:key>(maker:&mut Product<C>,cfg:&Config<C>,version:u64,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext,a:A,r:R):ID{catalog::assert_execution<A,R,T>(catalog::published(maker,version),a,r);create_value(maker,cfg,version,fee_revision,expiry,attempt,clock,ctx,true)}

public fun holder(p:&Player):address{p.holder}
public fun maker(p:&Player):ID{p.maker}
public fun maker_version(p:&Player):u64{p.version}
public fun protocol(p:&Player):ID{p.protocol}
public fun revision(p:&Player):u64{p.revision}
public fun selection(p:&Player,part:vector<u8>):Option<Selection>{scoped_selection(p,assembly::root_part(part))}
public fun scoped_selection(p:&Player,part:PartKey):Option<Selection>{if(p.selections.contains(part))option::some(*p.selections.borrow(part)) else option::none()}
public fun parts(p:&Player):vector<PartKey>{assembly::parts(&p.assembly)}
public fun profiles(p:&Player):vector<ProfileSnapshot>{assembly::active_snapshots(&p.assembly,&equipped(p))}
public fun profile_scopes(p:&Player):vector<Scope>{assembly::scopes(&p.assembly)}
public fun published_profiles(p:&Player):vector<assembly::Profile>{assembly::scopes(&p.assembly).map_ref!(|scope|*assembly::published_profile(&p.assembly,*scope))}
public fun source(s:&Selection):&Source{&s.source}
public fun layout(s:&Selection):Layout{s.layout}
public fun assert_owner(p:&Player,expected:u64,ctx:&TxContext){assert!(p.holder==ctx.sender(),EOwner);assert!(p.revision==expected,ERevision)}
public(package) fun set_base<C>(p:&mut Player,maker:&Product<C>,cfg:&Config<C>,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext){set_base_value(p,maker,cfg,definition,layout,expected,fee_revision,expiry,clock,ctx,false)}
fun set_base_value<C>(p:&mut Player,maker:&Product<C>,cfg:&Config<C>,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext,native_route:bool){
    assert_owner(p,expected,ctx);assert!(object::id(maker)==p.maker && object::id(cfg)==p.protocol,EBinding);
    if(native_route)economics::assert_primary_live(cfg,fee_revision,expiry,clock) else economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock);let v=catalog::published(maker,p.version);catalog::assert_runtime_access_value(maker,cfg,p.version,catalog::policy_hash(v),catalog::manifest(v),fee_revision,economics::commitment(cfg),clock,ctx,native_route);
    let version=p.version;let source=catalog::preview_source(maker,version,definition);set(p,source,layout)
}
public(package) fun set_base_native<C,A:drop,R:drop,T:key>(p:&mut Player,maker:&Product<C>,cfg:&Config<C>,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext,a:A,r:R){catalog::assert_execution<A,R,T>(catalog::published(maker,p.version),a,r);set_base_value(p,maker,cfg,definition,layout,expected,fee_revision,expiry,clock,ctx,true)}

public(package) fun set_pack<C>(p:&mut Player,maker:&Product<C>,pack:&Product<C>,cfg:&Config<C>,version:u64,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext){set_pack_value(p,maker,pack,cfg,version,definition,layout,expected,fee_revision,expiry,clock,ctx,false)}
fun set_pack_value<C>(p:&mut Player,maker:&Product<C>,pack:&Product<C>,cfg:&Config<C>,version:u64,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext,native_route:bool){
    assert_owner(p,expected,ctx);assert!(object::id(maker)==p.maker && object::id(cfg)==p.protocol && catalog::protocol(pack)==p.protocol,EBinding);
    if(native_route)economics::assert_primary_live(cfg,fee_revision,expiry,clock) else economics::assert_manufacturing_live(cfg,fee_revision,expiry,clock);let v=catalog::published(pack,version);catalog::assert_runtime_pack_value(pack,maker,p.version,version,cfg,catalog::policy_hash(v),catalog::manifest(v),fee_revision,economics::commitment(cfg),clock,ctx,native_route);
    assembly::admit(&mut p.assembly,&p.scene,catalog::assembly_profile(pack,version));
    set(p,catalog::preview_source(pack,version,definition),layout)
}
public(package) fun set_pack_native<C,A:drop,R:drop,T:key>(p:&mut Player,maker:&Product<C>,pack:&Product<C>,cfg:&Config<C>,version:u64,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext,a:A,r:R){catalog::assert_execution<A,R,T>(catalog::published(pack,version),a,r);set_pack_value(p,maker,pack,cfg,version,definition,layout,expected,fee_revision,expiry,clock,ctx,true)}

fun set(p:&mut Player,source:Source,layout:Layout) {
    let part=assembly::source_part(&p.assembly,&p.scene,&source);assert!(parts(p).contains(&part),ESelection);policy::assert_layout(policy::source_bounds(&source),&layout);
    let s=Selection{source,layout};if(p.selections.contains(part))*p.selections.borrow_mut(part)=s else p.selections.add(part,s);p.revision=p.revision+1;assert_size(p)
}
public fun clear(p:&mut Player,part:vector<u8>,expected:u64,ctx:&TxContext){clear_scoped(p,assembly::root_part(part),expected,ctx)}
public fun clear_scoped(p:&mut Player,part:PartKey,expected:u64,ctx:&TxContext){assert_owner(p,expected,ctx);p.selections.remove(part);p.revision=p.revision+1}
public fun colors(p:&Player):vector<ColorChoice>{p.colors}
public fun set_colors(p:&mut Player,colors:vector<ColorChoice>,expected:u64,ctx:&TxContext){assert_owner(p,expected,ctx);visual::assert_colors(&p.scene,&colors);p.colors=colors;p.revision=p.revision+1}
public fun pack_colors(p:&Player,scope:Scope):vector<ColorChoice>{assembly::pack_colors(&p.assembly,scope)}
public fun set_pack_colors(p:&mut Player,scope:Scope,colors:vector<ColorChoice>,expected:u64,ctx:&TxContext){assert_owner(p,expected,ctx);assembly::set_pack_colors(&mut p.assembly,&p.scene,scope,colors);p.revision=p.revision+1;assert_size(p)}
public fun reset_layout(p:&mut Player,part:vector<u8>,expected:u64,ctx:&TxContext){reset_scoped_layout(p,assembly::root_part(part),expected,ctx)}
public fun reset_scoped_layout(p:&mut Player,part:PartKey,expected:u64,ctx:&TxContext){assert_owner(p,expected,ctx);let source=p.selections.borrow(part).source;set(p,source,policy::default_layout(&source))}
public fun semantic_recipe(p:&Player):vector<RecipeSlot>{assembly::active_parts(&p.assembly,&equipped(p)).map_ref!(|part|output::scoped_slot(*part,scoped_selection(p,*part).map_ref!(|s|output::selection(s.source,s.layout,option::none()))))}
public fun semantic_recipe_hash(p:&Player):vector<u8>{output::profile_recipe_hash(&p.scene,&p.colors,profiles(p),semantic_recipe(p))}
public fun render_plan(p:&Player):vector<Layer>{
    assembly::render(&p.assembly,&p.scene,&p.colors,&equipped(p))
}
fun equipped(p:&Player):vector<assembly::Equipped>{let mut equipped=vector[];parts(p).do_ref!(|part|scoped_selection(p,*part).do_ref!(|s|equipped.push_back(assembly::equipped(*part,s.source,s.layout))));equipped}
/// Exit never consults source lifecycle. No issued asset is stored in Player.
public fun close(p:Player,expected:u64,ctx:&TxContext){assert_owner(&p,expected,ctx);let parts=parts(&p);let Player{id,holder:_,protocol:_,maker:_,version:_,revision:_,mut selections,scene:_,colors:_,assembly}=p;parts.do!(|part|{if(selections.contains(part)){selections.remove(part);}});selections.destroy_empty();assembly::destroy(assembly);id.delete()}
fun assert_size(p:&Player){assert!(std::bcs::to_bytes(p).length()<=245760,ESelection)}

#[test_only]
public fun create_for_testing<C>(maker:&mut Product<C>,cfg:&Config<C>,version:u64,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext):ID { soulidity_maker_manufacturing::maker_player::create(maker,cfg,version,fee_revision,expiry,attempt,clock,ctx) }

#[test_only]
public fun set_base_for_testing<C>(p:&mut Player,maker:&Product<C>,cfg:&Config<C>,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext) { soulidity_maker_manufacturing::maker_player::set_base(p,maker,cfg,definition,layout,expected,fee_revision,expiry,clock,ctx) }

#[test_only]
public fun set_pack_for_testing<C>(p:&mut Player,maker:&Product<C>,pack:&Product<C>,cfg:&Config<C>,version:u64,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext) { soulidity_maker_manufacturing::maker_player::set_pack(p,maker,pack,cfg,version,definition,layout,expected,fee_revision,expiry,clock,ctx) }

#[test_only]
public fun create_native_for_testing<C,A:drop,R:drop,T:key>(maker:&mut Product<C>,cfg:&Config<C>,version:u64,fee_revision:u64,expiry:u64,attempt:vector<u8>,clock:&Clock,ctx:&mut TxContext,a:A,r:R):ID{catalog::assert_execution<A,R,T>(catalog::published(maker,version),a,r);create_value(maker,cfg,version,fee_revision,expiry,attempt,clock,ctx,true)}
#[test_only]
public fun set_base_native_for_testing<C,A:drop,R:drop,T:key>(p:&mut Player,maker:&Product<C>,cfg:&Config<C>,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext,a:A,r:R){catalog::assert_execution<A,R,T>(catalog::published(maker,p.version),a,r);set_base_value(p,maker,cfg,definition,layout,expected,fee_revision,expiry,clock,ctx,true)}
#[test_only]
public fun set_pack_native_for_testing<C,A:drop,R:drop,T:key>(p:&mut Player,maker:&Product<C>,pack:&Product<C>,cfg:&Config<C>,version:u64,definition:vector<u8>,layout:Layout,expected:u64,fee_revision:u64,expiry:u64,clock:&Clock,ctx:&TxContext,a:A,r:R){catalog::assert_execution<A,R,T>(catalog::published(pack,version),a,r);set_pack_value(p,maker,pack,cfg,version,definition,layout,expected,fee_revision,expiry,clock,ctx,true)}
