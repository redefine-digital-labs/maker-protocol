module refuse::refusal;
use soulidity_maker_publication::output_data::InitialRule;
public fun bad():InitialRule{InitialRule{kind:0,name:std::string::utf8(b"soul"),read_mask:3,download_policy:0}}
