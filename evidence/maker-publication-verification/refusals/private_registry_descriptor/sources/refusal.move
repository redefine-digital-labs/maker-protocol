module refuse::refusal;
use soulidity_content_kinds::content_kind_registry::KindDescriptor;
public fun bad():KindDescriptor{KindDescriptor{version:1,kind:16,name:std::string::utf8(b"custom"),op_mask:0,read_mode_mask:1,has_active_binding:false,requires_download_policy:false,default_grant_scope_mask:0,deprecated:false}}
