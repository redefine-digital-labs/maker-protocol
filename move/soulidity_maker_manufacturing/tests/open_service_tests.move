#[test_only]
module soulidity_maker_manufacturing::open_service_tests;
use sui::test_scenario::{Self,Scenario};
use sui::package;
use sui::coin;
use sui::clock::{Self,Clock};
use std::type_name;
use soulidity_foundation::economics::{Self,Config,Admin};
use soulidity_foundation::package_roles::{Self,RoleCertificate};
use soulidity_foundation::revenue;
use soulidity_maker_manufacturing::maker_catalog::{Self as catalog,CreatorAuthority1,CreatorRevision3,Product,Control};
use soulidity_maker_manufacturing::maker_release::{Self as release,ReleaseInstaller1,ReleaseRevision3};
use soulidity_maker_manufacturing::maker_factory as factory;
use soulidity_maker_manufacturing::manufacturing_storage_fixture as storage;
use walrus::system::System;
use walrus::test_node::TestStorageNode;
public struct USD has drop {}
public struct WrongWitness has drop {}
public struct WrongRevision1 has drop {}
public struct F {sc:Scenario,cfg:Config<USD>,admin:Admin,release:RoleCertificate<ReleaseInstaller1,ReleaseRevision3>,creator:RoleCertificate<CreatorAuthority1,CreatorRevision3>,system:System,nodes:vector<TestStorageNode>,clock:Clock}
fun h(n:u8):vector<u8>{vector::tabulate!(32,|_|n)}
/// These frozen certificates are explicitly unpublished 0x0 fixtures. The
/// following create_service/new_service/install/activate/create_maker calls are
/// production functions, without Authority, Publisher or UpgradeCap inputs.
fun setup(primary:u16,fixed:u64):F {
    let mut sc=test_scenario::begin(@0xf);let(nodes,clock)=storage::bootstrap(&mut sc);
    let release_id=package_roles::certificate_for_testing<ReleaseInstaller1,ReleaseRevision3>(1,1,sc.ctx());
    let creator_id=package_roles::certificate_for_testing<CreatorAuthority1,CreatorRevision3>(2,1,sc.ctx());
    sc.next_tx(@0xa);let system:System=sc.take_shared();
    let release:RoleCertificate<ReleaseInstaller1,ReleaseRevision3> =sc.take_immutable_by_id(release_id);
    let creator:RoleCertificate<CreatorAuthority1,CreatorRevision3> =sc.take_immutable_by_id(creator_id);
    let id=factory::create_service<USD>(&release,&creator,primary,500,fixed,@0xa,&system,h(80),h(81),sc.ctx());
    test_scenario::return_shared(system);test_scenario::return_immutable(release);test_scenario::return_immutable(creator);sc.next_tx(@0xa);
    F{cfg:sc.take_shared_by_id(id),admin:sc.take_from_sender(),release:sc.take_immutable_by_id(release_id),creator:sc.take_immutable_by_id(creator_id),system:sc.take_shared(),sc,nodes,clock}
}
fun activate(f:&mut F){let F{cfg,admin,system,sc:_,release:_,creator:_,nodes:_,clock:_}=f;let rev=economics::revision(cfg);let hash=economics::commitment(cfg);economics::set_primary_enabled(cfg,admin,rev,hash,true);let rev=economics::revision(cfg);let hash=economics::commitment(cfg);release::activate(cfg,admin,system,rev,hash)}
fun activate_without_primary(f:&mut F){let F{cfg,admin,system,sc:_,release:_,creator:_,nodes:_,clock:_}=f;let rev=economics::revision(cfg);let hash=economics::commitment(cfg);release::activate(cfg,admin,system,rev,hash)}
fun register_creator(f:&mut F,rev:u64,hash:vector<u8>){let F{cfg,admin,creator,sc:_,release:_,system:_,nodes:_,clock:_}=f;catalog::register_from_certificate(cfg,admin,rev,hash,creator)}
fun register_release(f:&mut F,rev:u64,hash:vector<u8>){let F{cfg,admin,release,sc:_,creator:_,system:_,nodes:_,clock:_}=f;release::register_from_certificate(cfg,admin,rev,hash,release)}
fun register_other_admin(f:&mut F,other:&mut Admin,rev:u64,hash:vector<u8>){let F{cfg,release,admin:_,sc:_,creator:_,system:_,nodes:_,clock:_}=f;release::register_from_certificate(cfg,other,rev,hash,release)}
fun settle(f:&mut F,receipt:economics::PrimaryReceipt):sui::coin::Coin<USD>{let F{cfg,sc,clock,admin:_,release:_,creator:_,system:_,nodes:_}=f;let payment=coin::mint_for_testing<USD>(107,sc.ctx());catalog::settle_quote_for_testing(cfg,receipt,payment,clock,sc.ctx())}
fun end(f:F){let F{mut sc,cfg,admin,release,creator,system,nodes,clock}=f;test_scenario::return_shared(cfg);test_scenario::return_to_address(@0xa,admin);test_scenario::return_immutable(release);test_scenario::return_immutable(creator);test_scenario::return_shared(system);nodes.do!(|node|node.destroy());clock::destroy_for_testing(clock);sc.end();}

#[test]
fun fresh_service_has_exact_certificates_catalog_and_explicit_activation(){
    let mut f=setup(0,0);let root=object::id(&f.cfg);
    assert!(!economics::enabled(&f.cfg) && !economics::primary_enabled(&f.cfg) && !economics::secondary_enabled(&f.cfg),200);
    assert!(economics::manufacturing_creator(&f.cfg)==@0xa && economics::recipient(&f.cfg)==@0xa && economics::primary_bps(&f.cfg)==0 && economics::complete_fee(&f.cfg)==0,201);
    assert!(economics::native_snapshot(&f.cfg).is_none() && !package_roles::pinned(&economics::role(&f.cfg,0)),202);
    assert!(revenue::root(economics::income(&f.cfg))==root && revenue::balance(economics::income(&f.cfg))==0,203);
    assert!(package_roles::certificate_kind(&f.release)==1 && package_roles::certificate_kind(&f.creator)==2 && economics::role(&f.cfg,1)==package_roles::certificate_role(&f.release) && economics::role(&f.cfg,2)==package_roles::certificate_role(&f.creator),204);
    assert!(release::catalog_system(release::current(&f.cfg))==object::id(&f.system),205);
    activate(&mut f);assert!(economics::enabled(&f.cfg) && economics::primary_enabled(&f.cfg) && !economics::secondary_enabled(&f.cfg),206);
    let product=factory::create_maker(&f.cfg,0,&f.system,f.sc.ctx());f.sc.next_tx(@0xa);
    let p:Product<USD> =f.sc.take_shared_by_id(product);let control:Control=f.sc.take_from_sender();
    assert!(catalog::protocol(&p)==root && catalog::control_product(&control)==product && revenue::root(catalog::income(&p))==product,207);
    test_scenario::return_shared(p);f.sc.return_to_sender(control);end(f)
}
#[test]
fun two_ordinary_creators_get_distinct_admin_configs_ledgers_and_terms(){
    let F{mut sc,cfg,admin,release,creator,system,nodes,clock}=setup(1000,7);
    let first=object::id(&cfg);let first_ledger=revenue::root(economics::income(&cfg));
    let release_id=object::id(&release);let creator_id=object::id(&creator);
    test_scenario::return_shared(cfg);test_scenario::return_to_address(@0xa,admin);test_scenario::return_immutable(release);test_scenario::return_immutable(creator);test_scenario::return_shared(system);sc.next_tx(@0xb);
    assert!(!test_scenario::has_most_recent_for_sender<Admin>(&sc),208);
    let system:System=sc.take_shared();let release:RoleCertificate<ReleaseInstaller1,ReleaseRevision3> =sc.take_immutable_by_id(release_id);let creator:RoleCertificate<CreatorAuthority1,CreatorRevision3> =sc.take_immutable_by_id(creator_id);
    let(mut cfg,mut admin)=factory::new_service<USD>(&release,&creator,0,0,0,@0xb,&system,h(82),h(83),sc.ctx());let second=object::id(&cfg);
    assert!(first!=second && first_ledger!=revenue::root(economics::income(&cfg)) && economics::manufacturing_creator(&cfg)==@0xb && economics::recipient(&cfg)==@0xb,209);
    let revision=economics::revision(&cfg);let hash=economics::commitment(&cfg);economics::set_primary_enabled(&mut cfg,&mut admin,revision,hash,true);
    let revision=economics::revision(&cfg);let hash=economics::commitment(&cfg);release::activate(&mut cfg,&mut admin,&system,revision,hash);
    factory::create_maker(&cfg,0,&system,sc.ctx());economics::finalize_manufacturing_instance(cfg,admin,sc.ctx());
    test_scenario::return_shared(system);test_scenario::return_immutable(release);test_scenario::return_immutable(creator);sc.next_tx(@0xb);
    let mut second_cfg:Config<USD> =sc.take_shared_by_id(second);let mut second_admin:Admin=sc.take_from_sender();
    let revision=economics::revision(&second_cfg);let hash=economics::commitment(&second_cfg);economics::set_secondary_enabled(&mut second_cfg,&mut second_admin,revision,hash,true);
    let first_cfg:Config<USD> =sc.take_shared_by_id(first);assert!(!economics::enabled(&first_cfg) && economics::primary_bps(&first_cfg)==1000 && economics::complete_fee(&first_cfg)==7 && !economics::secondary_enabled(&first_cfg),210);
    test_scenario::return_shared(first_cfg);test_scenario::return_shared(second_cfg);sc.return_to_sender(second_admin);nodes.do!(|node|node.destroy());clock::destroy_for_testing(clock);sc.end();
}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun certificate_metadata_does_not_enable_service(){let mut f=setup(0,0);factory::create_maker(&f.cfg,0,&f.system,f.sc.ctx());end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun activation_does_not_open_primary_gate(){let mut f=setup(0,0);activate_without_primary(&mut f);factory::create_maker(&f.cfg,0,&f.system,f.sc.ctx());end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun register_from_certificate_wrong_cas_refused(){let mut f=setup(0,0);let hash=economics::commitment(&f.cfg);register_creator(&mut f,999,hash);end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun register_from_certificate_wrong_commitment_refused(){let mut f=setup(0,0);let rev=economics::revision(&f.cfg);register_creator(&mut f,rev,h(99));end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun old_foundation_callable_cannot_register_from_certificate(){let mut f=setup(0,0);economics::drift_callable_for_testing(&mut f.cfg);let rev=economics::revision(&f.cfg);let hash=economics::commitment(&f.cfg);register_creator(&mut f,rev,hash);end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun finalizer_requires_original_instance_creator(){let mut f=setup(0,0);let(cfg,admin)=factory::new_service<USD>(&f.release,&f.creator,0,0,0,@0xa,&f.system,h(80),h(81),f.sc.ctx());f.sc.next_tx(@0xb);economics::finalize_manufacturing_instance(cfg,admin,f.sc.ctx());end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun enabled_service_cannot_register_from_certificate(){let mut f=setup(0,0);activate(&mut f);let rev=economics::revision(&f.cfg);let hash=economics::commitment(&f.cfg);register_creator(&mut f,rev,hash);end(f)}
#[test,expected_failure(abort_code=3,location=soulidity_foundation::package_roles)]
fun same_or_stale_release_certificate_refused(){let mut f=setup(0,0);let rev=economics::revision(&f.cfg);let hash=economics::commitment(&f.cfg);register_release(&mut f,rev,hash);end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun other_instance_admin_cannot_select_release_certificate(){let mut f=setup(0,0);let(cfg,mut admin)=factory::new_service<USD>(&f.release,&f.creator,0,0,0,@0xa,&f.system,h(80),h(81),f.sc.ctx());let rev=economics::revision(&f.cfg);let hash=economics::commitment(&f.cfg);register_other_admin(&mut f,&mut admin,rev,hash);economics::finalize_manufacturing_instance(cfg,admin,f.sc.ctx());end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::economics)]
fun finalizer_rejects_other_instances_admin(){let mut f=setup(0,0);let(cfg,admin)=factory::new_service<USD>(&f.release,&f.creator,0,0,0,@0xa,&f.system,h(80),h(81),f.sc.ctx());let(other_cfg,wrong_admin)=factory::new_service<USD>(&f.release,&f.creator,0,0,0,@0xa,&f.system,h(80),h(81),f.sc.ctx());economics::finalize_manufacturing_instance(cfg,wrong_admin,f.sc.ctx());economics::finalize_manufacturing_instance(other_cfg,admin,f.sc.ctx());end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::package_roles)]
fun wrong_role_kind_refused(){let f=setup(0,0);package_roles::assert_certificate(&f.release,2);end(f)}
#[test,expected_failure(abort_code=1,location=soulidity_foundation::package_roles)]
fun wrong_private_module_refused_by_real_attest(){let mut sc=test_scenario::begin(@0xa);let p=package::test_claim(USD{},sc.ctx());let cap=package::test_publish(object::id_from_address(@0x0),sc.ctx());package_roles::attest_role(1,WrongWitness{},WrongRevision1{},&p,&cap,sc.ctx());transfer::public_transfer(p,@0xa);transfer::public_transfer(cap,@0xa);sc.end();}
#[test,expected_failure(abort_code=2,location=soulidity_foundation::package_roles)]
fun real_attest_refuses_zero_latest_cap(){let mut sc=test_scenario::begin(@0xa);let creator=catalog::publisher_for_testing(sc.ctx());let release=release::publisher_for_testing(sc.ctx());let cap=package::test_publish(object::id_from_address(@0x0),sc.ctx());factory::attest_bootstrap(&creator,&release,&cap,sc.ctx());transfer::public_transfer(creator,@0xa);transfer::public_transfer(release,@0xa);transfer::public_transfer(cap,@0xa);sc.end();}
#[test,expected_failure(abort_code=2,location=soulidity_foundation::package_roles)]
fun real_attest_refuses_latest_callable_mismatch(){let mut sc=test_scenario::begin(@0xa);let creator=catalog::publisher_for_testing(sc.ctx());let release=release::publisher_for_testing(sc.ctx());let cap=package::test_publish(object::id_from_address(@0xbeef),sc.ctx());factory::attest_bootstrap(&creator,&release,&cap,sc.ctx());transfer::public_transfer(creator,@0xa);transfer::public_transfer(release,@0xa);transfer::public_transfer(cap,@0xa);sc.end();}
#[test,expected_failure(abort_code=2,location=soulidity_foundation::package_roles)]
fun real_attest_refuses_wrong_publisher_module(){let mut sc=test_scenario::begin(@0xa);let creator=package::test_claim(USD{},sc.ctx());let release=release::publisher_for_testing(sc.ctx());let cap=package::test_publish(object::id_from_address(@0x0),sc.ctx());factory::attest_bootstrap(&creator,&release,&cap,sc.ctx());transfer::public_transfer(creator,@0xa);transfer::public_transfer(release,@0xa);transfer::public_transfer(cap,@0xa);sc.end();}

#[test]
fun new_service_preserves_old_instance_economic_snapshot_and_nonzero_income(){
    let mut f=setup(1000,7);activate(&mut f);let old=object::id(&f.cfg);let policy=economics::manufacturing_primary_policy(&f.cfg);let product=factory::create_maker(&f.cfg,0,&f.system,f.sc.ctx());f.sc.next_tx(@0xa);let mut p:Product<USD> =f.sc.take_shared_by_id(product);let control:Control=f.sc.take_from_sender();
    let receipt=economics::manufacturing_primary_quote(&policy,&f.cfg,100,true,@0xd,old,h(90),@0xa,h(91),clock::timestamp_ms(&f.clock)+1000);
    let receipt=economics::route_primary(receipt,product);let metadata=receipt;let net=settle(&mut f,receipt);transfer::public_transfer(net,@0xd);let product_income=revenue::snapshot(catalog::income(&p));
    let income=revenue::snapshot(economics::income(&f.cfg));assert!(revenue::balance(economics::income(&f.cfg))==17,211);
    let snapshot=economics::snapshot(&f.cfg);let commitment=economics::commitment(&f.cfg);
    let(new,admin)=factory::new_service<USD>(&f.release,&f.creator,0,0,0,@0xa,&f.system,h(82),h(83),f.sc.ctx());assert!(object::id(&new)!=old && revenue::balance(economics::income(&new))==0,212);
    economics::finalize_manufacturing_instance(new,admin,f.sc.ctx());
    assert!(economics::snapshot(&f.cfg)==snapshot && economics::commitment(&f.cfg)==commitment && revenue::snapshot(economics::income(&f.cfg))==income && economics::primary_receipt_policy(&metadata)==policy && economics::primary_receipt_fee(&metadata)==10 && catalog::protocol(&p)==old && revenue::snapshot(catalog::income(&p))==product_income,213);
    let rev=economics::revision(&f.cfg);economics::configure(&mut f.cfg,&mut f.admin,rev,0,0,0,@0xb,false);
    assert!(economics::primary_policy_bps(&policy)==1000 && economics::primary_policy_fixed(&policy)==7 && revenue::snapshot(economics::income(&f.cfg))==income,214);test_scenario::return_shared(p);f.sc.return_to_sender(control);end(f)
}

/// Synthetic previous callable models a historical release, not actual package
/// upgrade/type-origin execution. Production selection checks are unchanged.
#[test]
fun certificate_role_selection_requires_new_callable_marker_and_version(){
    let mut sc=test_scenario::begin(@0xa);let id=package_roles::certificate_for_testing<CreatorAuthority1,CreatorRevision3>(2,2,sc.ctx());sc.next_tx(@0xa);let c:RoleCertificate<CreatorAuthority1,CreatorRevision3> =sc.take_immutable_by_id(id);
    let mut state=package_roles::initial(object::id_from_address(type_name::original_id<CreatorAuthority1>()),object::id_from_address(@0x99));package_roles::pin(&mut state,2,type_name::with_defining_ids<catalog::CreatorRevision1>());
    catalog::select_certificate_state_for_testing(&mut state,&c);assert!(package_roles::role(&state,2)==package_roles::certificate_role(&c),215);test_scenario::return_immutable(c);sc.end();
}
#[test,expected_failure(abort_code=3,location=soulidity_foundation::package_roles)]
fun certificate_version_downgrade_refused(){let mut sc=test_scenario::begin(@0xa);let newer=package_roles::certificate_for_testing<CreatorAuthority1,CreatorRevision3>(2,2,sc.ctx());let older=package_roles::certificate_for_testing<CreatorAuthority1,CreatorRevision3>(2,1,sc.ctx());sc.next_tx(@0xa);let new:RoleCertificate<CreatorAuthority1,CreatorRevision3> =sc.take_immutable_by_id(newer);let old:RoleCertificate<CreatorAuthority1,CreatorRevision3> =sc.take_immutable_by_id(older);let mut state=package_roles::initial(object::id_from_address(type_name::original_id<CreatorAuthority1>()),object::id_from_address(@0x99));catalog::select_certificate_state_for_testing(&mut state,&new);assert!(package_roles::version(&package_roles::role(&state,2))==2,217);catalog::select_certificate_state_for_testing(&mut state,&old);test_scenario::return_immutable(new);test_scenario::return_immutable(old);sc.end();}
#[test,expected_failure(abort_code=3,location=soulidity_foundation::package_roles)]
fun certificate_foreign_original_lineage_refused(){let mut sc=test_scenario::begin(@0xa);let id=package_roles::certificate_for_testing<CreatorAuthority1,CreatorRevision3>(2,2,sc.ctx());sc.next_tx(@0xa);let c:RoleCertificate<CreatorAuthority1,CreatorRevision3> =sc.take_immutable_by_id(id);let mut state=package_roles::initial(object::id_from_address(@0x88),object::id_from_address(@0x99));package_roles::pin(&mut state,2,type_name::with_defining_ids<catalog::CreatorRevision1>());catalog::select_certificate_state_for_testing(&mut state,&c);test_scenario::return_immutable(c);sc.end();}

#[test,expected_failure(abort_code=2,location=soulidity_foundation::package_roles)]
fun zero_version_certificate_refused(){let mut sc=test_scenario::begin(@0xa);let id=package_roles::certificate_for_testing<CreatorAuthority1,CreatorRevision3>(2,0,sc.ctx());sc.next_tx(@0xa);let c:RoleCertificate<CreatorAuthority1,CreatorRevision3> =sc.take_immutable_by_id(id);package_roles::assert_certificate(&c,2);test_scenario::return_immutable(c);sc.end();}
