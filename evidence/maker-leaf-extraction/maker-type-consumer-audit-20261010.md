# Maker 类型、调用方与 ABI 独立审查（2026-10-10）

结论：源码、类型、调用方、测试正常化、最终冻结构建与退休命名空间反例审查 PASS。Replay verifier代码与16个离线回归检查PASS；实际导入后的35roots/440inputs与闭包绑定PASS，可供root运行一次组合CI。此报告只读取 actual 与 isolated candidate；只写 /tmp 两个报告。没有运行 Sui、链操作、密钥、提交或共享源码修改。

- Actual: /Users/naoer/.codex/worktrees/soul-dof-v1-rebuild/soulidity
- Candidate: /Users/naoer/.codex/worktrees/maker-leaf-construction/soulidity/candidate
- 正常化只允许三个模块前缀和 use 声明内新增的 Self/module alias；不正常化签名、方法名、属性、断言或失败意图。
- 手册 v1.0；适用 8.3/8.4，基线 1–4、9、12。

## 源码与测试范围

导入前140 actual原输入全部保持原 SHA，冻结原始baseline继续保留；协调者随后导入的实际路径已按registered after SHA另行核对；121 Move 输入逐字节通过 namespace-only 正常化。三实现共109公开函数、16类型；Application只保留109单调用 delegates，无定义类型、私有权限或公开类型 reexport。

| 范围 | 文件 | 测试 | expected_failure | assert! 全文件代码 |
|---|---:|---:|---:|---:|
| Core 原测试 | 58 | 1038 | 659 | 904 |
| 全部10包原测试 | 67 | 1173 | 766 | 1005 |

Core实际测试方法内871条断言；904包含测试helper内33条。所有测试方法名、完整属性（含合并属性）、方法签名/体/断言和负例意图保持一致。1038不是此前错误 regex 得出的711；两者不能相互替代。最终baseline与candidate各1038实际VM名称已分别关联其140/147冻结输入；源码清点与执行证据分别保留。

## 调用方精确计数

计数解析 use alias 与全路径，排除字符串、注释、import声明；源内 test_only helper 与三代理单列。不存在与这些叶函数同名的点式方法歧义。

| 范围 | 文件 | 不同函数 | 调用引用数 | 不同类型 | 类型引用数 |
|---|---:|---:|---:|---:|---:|
| 外部生产 | 7 | 55 | 89 | 11 | 75 |
| 原测试 | 18 | 85 | 223 | 7 | 9 |
| 源内test_only helper | 2 | 2 | 3 | 2 | 2 |
| 叶间引用 | 1 | 2 | 2 | 1 | 3 |
| Application代理 | 3 | 109 | 109 | 11 | 124 |

生产55函数/11类型分布：resale13函数/3类型；physical_metadata37函数/5类型；issuance5函数/3类型。生产引用文件为character、publication_rules、catalog、issuer、market、native_binding、physical。18测试文件消耗85不同函数/7类型。正常化后baseline与candidate逐项相等。

## 身份与兼容边界

| 实现 | 公共函数 | 类型 | 新身份 |
|---|---:|---:|---|
| soulidity_application::issuance | 5 | 3 | soulidity_maker_admission::maker_issuance |
| soulidity_application::physical_metadata | 73 | 9 | soulidity_maker_terms::maker_physical_metadata |
| soulidity_application::resale | 31 | 4 | soulidity_maker_terms::maker_resale |

16类型：resale Rates/Snapshot/Receipt为copy+drop+store，Settled为copy+drop；physical_metadata9种metadata为copy+drop+store；Binding/Genesis/Contribution无abilities，保持linear且无key资产。字段顺序、标量/嵌套布局与hash domain一致。相同字段值的裸BCS可相等，但名义类型/TypeTag/ABI、来源包与链接身份改变。

旧Application-qualified Rates、Proof、Binding等类型没有公开alias；三个独立编译反例均以目标sources/refusal.move主诊断EC03003证明拒绝。即使调用Application wrapper，Settled仍从MakerTerms::maker_resale发出；事件filter必须跟随实际发布来源。12生产结构嵌入新叶类型，另有2测试shape；完整字段清单在JSON。历史部署对象、事件、ABI、类型来源与链接不能由未发布0x0构建推断兼容。

三叶不声明dynamic-field key、不执行DF/DOF操作；现有消费者key定义和命名空间不变。key相同不意味着历史child value名义类型与新的读取类型兼容。没有本轮链上key/child/升级证据。

Admission是Soul-specific adapter：Genesis验证Standard Soul Origin；bind硬编码application_operator::ApplicationOperator，且要求operator与NativeInstaller witness原始包地址相等。不是通用Maker core，也没有消除Binder/Operator共同发布约束。

## 实际依赖图

两叶均无Application/Core反向依赖。MakerTerms声明直接Model、Foundation；传递包含Standard、Visual。Admission声明直接Model、Foundation、Standard；传递包含Visual。

独立读取已冻结 .mv ModuleHandles：

| 模块 | 直接项目模块依赖 |
|---|---|
| soulidity_maker_admission::maker_issuance | soulidity_foundation::economics, soulidity_model::policy, soulidity_standard::soul |
| soulidity_maker_terms::maker_physical_metadata | soulidity_foundation::economics, soulidity_maker_terms::maker_resale, soulidity_model::material_policy, soulidity_model::policy |
| soulidity_maker_terms::maker_resale | soulidity_foundation::economics, soulidity_model::policy |

源码57项目模块、12包与编译模块图均没有有向SCC。残余Maker/Operator/Binder问题是Core职责与同包权限耦合：NativeBinder仍引用catalog Product/Control、issuer Build及ApplicationOperator；Operator本身无项目模块依赖。不要把这个残余称为当前编译器环，也不要宣称已完成完整Maker生产者拆分。

最终编译图证据：/Users/naoer/.codex/worktrees/maker-leaf-construction/soulidity/evidence/candidate-soulidity_v1-production.modules.json；SHA 108437ba6ce8617a047a7d18f1e929b15af67ee695602878d0fc7d69c0783243。179个冻结编译模块均独立解码；历史未冻结命令不计入最终放行证据。

## 原始客户端与放行范围

独立核对协调者745 SDK/UI源SHA全部未变；0直接Application leaf命名空间引用，3 Genesis字符串属于UI占位内容。来源：/tmp/maker-client-impact-review-20261010.json，SHA 8cac4fc8a96aab78154fd9e25a452e774994176573a3128f1f66b2b404454455。词法零命中不证明动态目标、既有对象、钱包PTB、索引/事件与完整原产品旅程可运行。原客户端保持现状；链目标适配/产品验收和Release/Deploy仍未完成。

## 最终证据与剩余边界

- JSON: /tmp/maker-type-consumer-audit-20261010.json
- 最终147 candidate source/manifest/lock输入及每运行pre/post SHA均核对；独立生产结果及baseline/candidate1038结果已关联。
- 退休Application三个qualified类型拒绝的独立主诊断已核对。
- 原本计数遗漏的合并test属性已修复，1173 local/1038 Core与本审查对齐。
- 新未发布目标与历史部署origin/linkage区别必须进入交付文档；当前wrapper与namespace-relocation已披露，但不代表发布兼容。

## Replay verifier 独立代码审查

初版工具的assert优化绕过、final完整性未决定PASS、EC诊断regex与主source绑定问题已修复。原版SHA和具体修复范围保存在JSON；当前修复版为8d136fcb4359e0017f1033e7b2f72327475cce5a074cff038090f70b9328f337。未执行真实Sui；实际config已核对PASS。

退休namespace反例已独立验明：RefuseOldRates、RefuseOldProof、RefuseOldBinding各自exit1；主诊断EC03003在本fixture sources/refusal.move:2并明确Unbound member；后继EC03004为级联unbound type。各次pre/post及当前输入SHA一致。三个类型均无Application公开reexport。

Replay修复版SHA 8d136fcb4359e0017f1033e7b2f72327475cce5a074cff038090f70b9328f337：16个独立offline gate fixture全部PASS，其中optimized字节码仍拒绝错误PIN/初始drift，final输入/control drift生成FAIL并抛错，EC诊断主block/location正确绑定，错误counts/bytes/dump、漏项与artifact SHA均拒绝。正例combined产生24命令结果。使用进程stub；0真实Sui命令。实际config完整闭包与SHA已在协调者导入后绑定PASS。

Final freeze independent recheck: PASS. Baseline140/candidate147 complete current inputs; original140 inputs unchanged;121 namespace-only original Move bodies and all attributes/assertions remain exact. Guarded payload41 files and42 verification fixture files match reviewed SHA/absence/writer guards. All32 accepted command records bind unchanged exact input snapshots, pinned Sui1.80.1-671ba71e69c7,default102400 without overrides,stdout/stderr and frozen bytecode artifacts. Baseline+candidate each1038 exact original Core methods, focused10, and all17 distinct refusals with intended primarycode at intended frozen source location passed. Native raw dump unchanged. Final compiledCore179 modules,57 project modules, no directed compiler/package SCC; Maker/Binder/operator co-location remains responsibility/authority constraint. This is new unpublished source evidence; no chain/client/full-goal acceptance.

Final summary SHA256 a7a064dda07f159d14297bd364a2e6be9e57357e2fd2876811c8ee5fb85533e4; payload manifest e70112343d21ed7fdb1d336038faa67e2a7cd2581da39c6cb23f3ac2bbe6ff7d; final candidate inputs fb6c352bec12802c2a64cfdfb4cefe71027a497cb78290e768932f8eaeb79d38.

Full frozen inventory recheck also PASS:1,045 files,21,268,985 bytes,SHA2566f5a41c71df7129727180aac21f754ea9f9b0120ceff0e19af79abb08259dd82,tree98797a35c206c9474d62bb7e3235e28d095d14bd2d25cb22778cf07fea8a2235.

Actual config binding review PASS:35 exact roots,440 current source/manifest/lock/writer inputs,guarded imported payload41+fixtures42,7 durable build reference filesets and17 exact refusal sources/codes. Config8255119c7b8643707796df6e7d196688a513f390dda7c1c7cda7fa759bdab5ef; installedverifier9ceb39529c49a920165aa242753c09f3c0e5cebb60c7c8058015ae38d2c46d18 differs from reviewed8d13 only in requiredcombined4 and helptext. CachedSui/Stdlib/Walrus/Wal effective closure all frozen; old vendor Sui rev is explicitly overridden by every actual build/fixture root. RegisteredCI uses --combined and remains not_run. No realSui executed by reviewer.

Installedcombined4 verifier additionally passes17 optimize=2 offline regression fixtures,including valid26-command plan,missingCustody gate,and finaldrift failure. Loaded source/currentSHA9ceb39529c49a920165aa242753c09f3c0e5cebb60c7c8058015ae38d2c46d18 exact. Prior16 fixture evidence retained. Reviewer realSui0.
