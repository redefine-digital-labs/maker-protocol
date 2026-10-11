module refuse::refusal;
use soulidity_model::components::Permit;
public fun bad(p:Permit){let _=p;}
