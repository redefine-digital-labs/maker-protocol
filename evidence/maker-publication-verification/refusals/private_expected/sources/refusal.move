module refuse::refusal;
use soulidity_maker_publication::publication_validation::Expected;
public fun bad():Expected{Expected{asset:vector[],bytes:1}}
