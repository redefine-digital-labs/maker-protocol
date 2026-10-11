/// Synthetic Foundation gate fixture only; no Native package or installed production gate.
#[test_only]
module foreign_publication_producer::native_binding;
use soulidity_foundation::economics::{Self,Config,Admin};
public struct NativeInstaller1 has drop {}
public struct NativeRevision2 has drop {}
public struct Catalog has key,store {id:UID}
public fun create<C>(ctx:&mut TxContext):(Config<C>,Admin){
 let(mut c,mut a)=economics::new_config_for_testing<C>(1000,500,7,@0xf,ctx);
 economics::bootstrap_application_for_testing(&mut c,&mut a,NativeInstaller1{},NativeRevision2{});
 let r=Catalog{id:object::new(ctx)};let h=vector::tabulate!(32,|_|1);
 let permit=economics::authorize_installation(&c,&mut a,0,economics::commitment(&c),0,NativeInstaller1{},NativeRevision2{},&r,0,h);
 economics::install_native_initial_for_testing(&mut c,&mut a,permit,r,h);economics::enable_initial_for_testing(&mut c);(c,a)
}
