# Maker / Native / Operator / Custody 最小切口只读评审
日期：2026-10-10；阶段 Plan / Reviewed source。未运行 build、VM 或链上操作；未写共享源码、锁、远端或链。
适用手册：PRODUCT_ENGINEERING_HANDBOOK_CN.md v1.0，1–4、7、8.3–8.4、9、12；沿原 Delivery/DEV/BUG Owner。本报告是方案/验收输入，不是已实施 ABI 或权限证明。

## 结论
不建议直接将 Maker 的 12 个目标文件变为一个独立 Move 包。至少存在三条真实循环：
1. Maker release/runtime → Native native_binding → Maker catalog/issuer；
2. Maker issuer/physical/collection → Extensions application_operator，而 native_binding 私有 binding 也要该 operator；
3. Maker collection / Extensions access → Native custody 私有 cap，且当前被调用方、消费者全部靠同包 private/package 可见性成立。
还有目标归属本身的循环：character → issuance/resale（目标 Maker），Maker catalog/issuer → character；publication_rules → output::Policy（Application）。
真实 Native birth/registry 当前没有 import v1；这两文件已是向下依赖 Standard/Foundation/Content 的生产者包。不要把它们再绑回 Maker。

推荐下一有边界的执行增量：提取独立 NativeCustody 叶发布单元（custody + native_creation；保留 NATIVE.PRODUCER Owner/仓库归属），同时只为原 Collection 与 Access 调用增加具体验证 consumer 或线性操作请求。Account 的原生 cap 继续封装、不能 borrow/export。这先消除最危险的 cap 私有跨包边界，可独立生产构建和具体验收，完整 Maker 提取仍明确 Pending。
若本轮必须交付全部 Maker 源权威，需一个独立隔离执行阶段同时完成以下 MakerTypes / Maker制造 / Soul分发适配发布单元和 NativeBinder 反向导入消除；不能把本切口称“12文件独立Maker完成”。

## 当前具体调用与能力路径（实际工作树 move）
- native_binding.move:20–52 roles/defining_roles 固定15类型。包含 issuer::Build、catalog::Product<C>/Control（反向 Maker），custody::Account、Vault/Artifact/ContentOperator，以及框架/Walrus类型。角色顺序和 original+defining 类型一起进入 Catalog commitment；迁仓改变其实际类型身份。
- native_binding.move:115 application_binding 为 public(package)；执行 assert_current(cfg)，调用 issuance::bind(cfg, private NativeInstaller1{}, NativeRevision2{}, application_operator::operator())。没有对外合法替代入口。
- release.move:58–60 install / 69–70 assert_catalog 对 Native catalogue ID/hash做强绑定，并调用 native_binding::assert_current。runtime.move:73 begin 取 native_binding::application_binding。只改import会循环。
- application_operator.move:5 operator() public(package)，返回只有 drop 的 ApplicationOperator。不能公开此构造或返回值：character.move:639 assert_operator 只比较 ApplicationState.operator 的 original TypeName，没有动作/主体/实例/最新Revision检查。
- issuer.move:42 enhance_pack → character::admit_profile(op, Soul, Profile)；127 finish → character::install_output(op, Soul, Artifact)。
- physical.move:120 materialize_scoped → character::reserve_materialization(op, Soul, key, proof_hash, expected_soul)。
- collection.move:69 add_soul → character::bind_collection(op, Soul, collection_id, expected_soul)。
- access.move:104、107、113–120、124、129 使用 operator 做 paid purchase/read/delegate/content/output权限消费；权限来源是库存真实Soul路径+record.owner+Account证明或实际delegate，而不是operator本身认证owner。
- custody.move:27–31 assert_access 是 public(package)，核Account.owner==sender、Account.kiosk==Kiosk ID、kiosk::owner==owner、实际cap访问权；cap()返回原生KioskOwnerCap引用，public(package)。
- collection.move:57–62 create使用assert_access/cap锁Right；72 add_kiosk_soul借实际Soul；98–100 list借Right及生成PurchaseCap；104 cancel验证账户；108–110 buy验证买家并锁Right。Collection资金/holder/epoch/supply仍应在Collection最终写点管理。
- access.move:54–66 install/disable/enable/uninstall使用Account cap进行kiosk_extension add/enable/disable/remove；add原权限固定0。owner()逐次验证record.account与实际Account，而非只看owner缓存。
- native_creation.move:15–36每个register/place/prepare/begin/finish先验证真实Account，再私有借cap调用独立Native producer。将此薄适配器与custody放同一独立包保留private调用即可。
- runtime没有custody::cap调用；实际Cap用户是collection、access、native_creation。
- catalog.move:36–55 mint_soul 在私有函数里创建真实Soul、authorize_complete计wallet/aggregate、exact Coin primary settlement、Genesis认证；322–345 reserve completion/definition supply；387–393 contribution计数+结算后返回线性Contribution。这些不能移动成公有任意计数/发行授权接口。

## 候选方案（2–3项）
A. 只公开operator()/cap()/ApplicationOperator构造：改动最小但拒绝。
真实原生cap可绕过受控薄适配；operator允许任意Profile admission、Collection绑定、Physical reservation或内容访问。名字叫Witness不改变这个结果。public泛型方法也不能只检查W:drop或模块名字，必须持有不可公开构造的具体值并核实际已注册type/对象关系。

B. 每域private witness + public generic认证consumer：推荐Custody下一切口。
在原collection模块继续私有构造CollectionAuthority1和当前Revision，Custody公有consumer接收这些真实值并核Config当前角色4。再核T为同实际collection模块的Right、实际Kiosk/Account/Cap、期望ID及对应TransferPolicy。认证使用assert_role_types，业务Primary/Secondary/paused仍由原入口判断；不要把create调用改为assert_business(kind4)从而引入Secondary gate。
候选consumer明确枚举 lock_right / borrow_right / list_right / borrow_soul_for_collection；不得有公有cap getter、万能with_cap、任意take<T>或任意cap转移。借Soul返回实际Kiosk存储引用，不能返回新构造Soul或UID。
Access的namespace add/enable/disable/remove也应作为具体验证consumer，add固定permissions=0，并证明实际namespace就是受选择的AccessExtension，绑定实际Account/Kiosk/协议。如用泛型X，它的实际TypeName必须由本实例已认证目录/选择记录绑定，不能允许客户端仅传模块字符串。错误namespace/clone包/Account/权限位反例必须失败。
优点：控制对象/资金/供给写点原位，最少运行行为变化；真实Sui公有入口继续可PTB调用。
代价：public ABI增加、类型/角色注册更新；若需要新增跨包namespace登记，应明确是新目标具体身份绑定，不能说旧行为或ABI零变化。消费者可直接在执行入口内认证，别发可重用OwnerProof。
注意：原create没有role4 latest检查；新增该检查会加强旧入口拒绝行为。执行者需区分“角色身份验证所必需”与“新增业务gate”，用新目标一致注册fixture证明，并记录这个准确变化。

C. 线性操作请求/完成凭证：推荐用于涉及跨包最终动作的边界。
例如Collection定义No copy/drop/store的RightDelivery/RightListing请求，绑定protocol、collection/right ID、policy ID、Kiosk ID、actor、epoch/revision、action/attempt；NativeCustody consumer先assert_access，在同PTB执行lock/list等原生动作，返回不可伪造Completion或直接调用最终消费。Collection消费核Kiosk实际contains/locked/type和全部绑定，再更新holder/epoch/listing/账本。
欠完成、弃票据、错Kiosk/Account/right/policy、跨动作、重复消费必须abort。不要将copyable历史Receipt当Completion。Sui不能做“动态回调”；公有generic同步consumer或明确PTB两步。
优点：高风险完成不可跳过，易证明结算与交付原子性。
代价：更多公有临时类型/ABI，新增PTB步骤和客户端适配；创建新UID须仍在定义constructor内直接object::new；与D26 owned-only交付一起验证。可先用B闭合纯读取/权限管理，用C闭合Right交付/挂牌/成交。

## Maker的下一完整切口（避免制造与链上分发混同）
MakerTypes叶包（同maker-protocol仓的独立release_unit）：
- resale和physical_metadata当前没有Soul import，依赖Foundation/Model；可先迁为真实叶包。
- issuance是通用线性Genesis/Contribution admission，依赖Foundation/Standard/Model，而不是catalog类型。将它置于独立MakerAdmission叶包可使character和MakerSoulAdapter共同依赖，不能与导入character的catalog/issuer合并。
- publication_rules依赖output::Policy和输出getter；完整制造内核不依赖Soul要求把output中Policy/InitialRule/Intent/Recipe等纯数据契约从Artifact/Soul动作划成leaf，或先把publication_rules放SoulAdapter。不要把整output放MakerCore造成Core→Standard；这是具体当前耦合，不是新产品路线。
Maker制造包仅拥有Product/Version/Control、版本认证、access、wallet/aggregate/definition supply、实际收入与原经济规则。产品metadata/制造不要求Soul根。catalog当前mint_soul、issue(target:&Soul)、complete_contribution等必须拆为制造请求+SoulAdapter消费者，不能裸公开SoulProducer/ComponentProducer，也不能在SoulAdapter复制计数。
MakerSoulAdapter在同仓独立发布，包含issuer/runtime及Collection/Physical实际Soul桥；依赖制造/Admission/ApplicationSchema/Standard/NativeCustody。保留直接发行公有PTB入口，不引入平台调度或Channel必选。
现有Model components::authorize(ComponentProducer,product,target:&Soul,Source)及Standard::new(SoulProducer,source,...)都要求private witness与实际source同模块，不能直接把catalog source证明改成issuer模块witness。应由catalog在本身最终供给写点产出线性请求，经具体验证consumer装配，并保留标准生产者同模块关系；必要ABI变更要显式设计和生产build证明。

Maker与Operator拆分建议用现有票据而非新总权限：
- issuer::finish的install_output改为character公有consume安装，强制Draft+真实Soul+Artifact控制关系+actor，assert_draft；无需输出通用op。
- issuer::enhance_pack先真实complete_contribution→begin_enhancement，再用Enhancement绑定product/version/policy/actor来admit_profile，不能提前仅凭copyableProfile。
- collection::bind_collection用private Collection witness/linearMembership经consumer，保留creator一致、protocol、max_supply、唯一membership、expected revision与原collection supply写点。
- physical::reserve_materialization用private physical CaptureProducer+实际Registry同模块认证或线性Materialization请求；终点仍核真实Soul/Artifact/genesis、原rule/supply/replay/key和expected revision。capture已有visual_capture::new/assert_controller同模块模式可参考，但copyableProof不能当权威。
- Access保留自己的private operator；它只处理已验证实际容器路径。不要使Maker可借它去触发paid read或delegate操作。

NativeBinder从总产品tuple拆成Native域目录；Maker自己的release/creator/collection类型与兼容身份由对应目录维护。或者将它明确置于只向下依赖的Integration发布单元，并移除Maker/Access反向调用，仅消费Foundation已认证不可伪造快照。不能删除role tuple条目以后仍宣称旧catalog commitment/identity含义未变。
issuance::bind当前强制O与NativeInstaller同original地址，硬编码application_operator/ApplicationOperator；独立Extensions后必然不成立，需准确绑定独立operator type+revision及配置选定身份。公有generic参数单独不构成认证。

## 行为验收与身份变更
下一Custody切口：
1. 独立生产root构建；依赖图无v1/Maker反向引用；原消费者真实生产构建。只在隔离候选写lock，不刷新共享基线。
2. Account仍key-only/no-store/no-drop；new线性(Kiosk,Account)，finalize核真实pair/sender；cap不能返回、被存出、转走或从public包装拿到。
3. 原Collection create→add wallet/Kiosk Soul→list/cancel→list/buy：实际锁Right、membership supply、current holder/epoch、exact金额/逐组件CEIL、收入Control相同。Secondary-off不阻断原Primary创建；失败交付原子回滚资金/Right/新对象。
4. Access安装permissions=0；grant/revoke、delegate/paid读取、付费ledger和owner/generation保持；disable和协议pause后withdraw/uninstall_empty恢复仍可用；handover清授权并遍历原Vault树（depth16/nodes256），read不变spend。
5. Native六种source/config公开薄适配仍直接Sui调用，Registry/Claim/Draft、真实Kiosk绑定、原source/issuer revision、paid资源连续；只迁源码不复用未知签名、不重付或重铸。
6. foreign反例只覆盖受影响consumer：private W无法伪造，metadata/同名clone替代失败，错cfg角色/旧revision/类型/实例/actor/动作/票据/完成均拒绝。完成凭证必须不可copy/drop/store，所有终点闭合实际资产交付。

公有身份：custody::Account若从原soulidity_v1包迁到新package，新TypeName/defining ID/原始type地址，所有Account参数的规范type tag、native_binding catalogue、SDK输入类型、库存binding与候选依赖字节码都会变化；soulidity_v1::collection Right/Factory/Product/Control以及resale::Rates/Snapshot、physical_metadata、issuance::Genesis/Contribution迁新包同理。
这是evolving_new_target的新一致类型，不是旧ABI兼容。历史Account/资产留原合法入口；未冻结新目标前更新候选并记录新baseline，冻结后不得换身份掩盖失败。保持独立source唯一writer只是源码权威；没有实际Published linkage/旧writer拒绝/PTB回执前，不称链上接替或B0/CASE19通过。

