module refuse::refusal;
use soulidity_content_kinds::content_kind_registry::KindAdminCap;
public fun bad(ctx:&mut TxContext):KindAdminCap{KindAdminCap{id:object::new(ctx),registry:object::id_from_address(@0x1)}}
