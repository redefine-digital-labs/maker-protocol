module refuse::refusal;
use soulidity_model::components::Permit;
use soulidity_model::policy::Source;
public fun bad(source:Source):Permit{Permit{source,target:object::id_from_address(@0x1)}}
