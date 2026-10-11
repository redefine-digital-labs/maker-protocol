module refuse::refusal;
use soulidity_model::components::Permit;
use soulidity_model::policy::Source;
public fun bad<W:drop,P:key>(w:W,p:&P,target:&u64,source:Source):Permit{soulidity_model::components::authorize(w,p,target,source)}
