module refuse::refusal;
use soulidity_model::components::Permit;
public fun as_key<T:key>(_p:&T){}
public fun bad(p:&Permit){as_key(p)}
