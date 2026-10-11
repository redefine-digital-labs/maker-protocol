# Maker 两叶包实际施工评审

2026-10-10，手册v1.0，适用§1–4、5、6（支付／精度）、7、8.3–8.4、9、12。沿用原DOF-001/P01/P09和Maker原范围卡、Owner及验收职责；本地证据附件见实际工作树 docs/ecosystem-construction/ACTIVE_CONSTRUCTION_CN.md。实际人员和合格独立验收资格尚未落实；内部AI复核不替代外部审计。未写Slack或建立第二看板。

本增量Code/Build/Test已验证。MakerTerms拥有实际Coin结算与物理事实，MakerAdmission是Soul-specific发行适配。只移动109个公开函数、16种规范类型，原Application留薄调用；原资金公式、供给及私有票据约束按显式namespace map保留。两叶包不直接依赖Application/Core；Terms经Model仍传递依赖Standard，Admission直接依赖Soul。完整Maker制造及Binder/Operator职责尚未分离。

| 检查域 | 结果和证据 | 剩余检查 |
| --- | --- | --- |
| 管理／敏捷 | 通过本增量：41实际输入和42fixture逐SHA导入，34独立恢复副本；原157职责和1528队列未改 | 完整Owner/验收与原旅程继续按原卡 |
| DevOps／恢复 | 通过本地：35根440输入及配置/工具/候选制品前后不变；7实际生产根逐字节等于审核候选；已登记本仓产品CI | 无远端CI、发布或链状态回滚证明 |
| 资金／精度 | 通过本增量：保留role3、最新Config/receipt重算/exactCoin/Secondary、收入与收款方；gross逐组件FLOOR、Collection逐组件CEIL及溢出拒绝 | 真实链上Coin/事件/钱包、旧writer接替和完整原市场待验收；无借贷/AMM/收益产品新增 |
| 合约／权限／Sui | 通过本增量：1038原Core与10重点VM默认预算；17foreign首诊断匹配各自源；三线性票据无copy/drop/store，metadata不授予权力，实际Cap不导出 | D26 freshKiosk失败保留；完整owned-only构造与有效权限未闭合 |
| 治理／迁移 | 待核验：新unpublished规范类型和Settled事件地址改变；字段形状保持不能证明旧类型/child/linkage兼容 | 无UpgradeCap部署、旧入口拒绝、独立升级或初始化证明；不执行多签/timelock/不可升级权限变更 |
| EVM／运行 | 本增量不适用：Sui源码验证，零RPC/签名/发布，无运行服务部署 | 原运行恢复、完整用户旅程及Release/Deploy/Operate/Monitor继续待验收 |

原Source SHA与职责数量保留；当前38原源未改、14显式重构、5新增=57生产实现，116输入守卫通过。候选与实际编译证据均是未发布图。SDK/UI745源未变且无三旧namespace的字面业务引用，只是源影响排查，不等于链上地址适配或完整UI验收。原Native四根629模块/140输入证明为本增量前历史；当前实际组合以本目录runs/唯一记录为准。

恢复必须先核当前SHA与writer，再按source-transition-registered.json和payload/manifest.json还原整个对应源码/manifest/lock组合。不能只删除新leaf，也不能覆盖后续合法变更。原链上资产、钱包、回执、DB与Genesis未动。完整目标仍进行中；B0/CASE-19未运行，D26失败未关闭。
