# MT5 EA 通用交易模块 Skill v4.20（模块 v4.20）— 开发完成

> **v4.20 变化（模块代码实质修改）**：重写「当日最大亏损」与「连续亏损暂停」两条风控的统计内核——由 `OnTrade()` 增量累加改为**从当日历史幂等重算**，按 `DEAL_POSITION_ID` 归组判盈亏。同时修复 3 个**从未被真机编译发现**的编译错误（`CTrade::SetComment` / `ResultRequestDescription` 不存在、注释边框漏 `//`）。已实机编译验证 **0 errors / 0 warnings**。
>
> **v4.19 变化（仅文档 + 工具）**：新增「部署与调试」能力（`references/deployment.md` + `scripts/deploy_to_terminal.py`），把「部署进终端数据目录」列为交付必做步骤。

## 已完成内容

基于用户的多轮反馈（三套追踪止损 A/B/C + 独立 SL/TP 开关 + 盈亏比可调 + 同K线禁止重复交易 + 最大止损限制 + 最大同时持仓数 + 分批止盈模式 + 5 个生产 BUG 全部修复 + 持久化追踪索引工具），开发了 v4.18 版本的 WorkBuddy Skill：**mt5-ea-common-trading-module**。

该 Skill 生成的 MQL5 通用模块 `MT5_EA_Common_Trading_Module.mqh` 自动包含完整的参数面板：

1. **交易时间（北京时间）** — 服务器时差转换、跨天交易时段判断
2. **仓位管理** — 固定手数 / 风险百分比双模式、最小/最大手数限制
3. **止损止盈开关** — 启用固定止损 / 启用固定止盈（独立开关，可单独关闭）
4. **止损与追踪（共用基础参数）** — 固定止损 300 点 / 固定止盈 660 点（盈亏比 2:1）
5. **追踪方式 A：渐进式（持续追踪 SL）** — 三选一：勾选即用 A
   - 追踪激活利润点数 20
   - 保本点数(SL 移入场价) 320
6. **追踪方式 B：一次性保本（触发后锁死）** — 三选一：勾选即用 B
   - 触发保本的利润点数 320
   - 保护利润(SL 移开仓价 ± 此点数) 20
7. **追踪方式 C：形态追踪（支撑/压力摆动位）** — 三选一：勾选即用 C（金刚经原版模块）
   - 跳过触发阶段直接形态追踪（可独立使用）
   - 触发激活的利润点数(SL移到保本+保护点) 300
   - 激活后SL移到开仓±此保护利润点数 55
   - 形态追踪SL距支撑/压力位缓冲(点) 20
   - 形态识别周期(摆动点检测) PERIOD_M1
8. **风控管理** — 当日最大亏损限制、点差限制
9. **连续亏损暂停** — 达到指定连续亏损次数后暂停指定分钟数
10. **盈亏比设置（可调）** — TP = SL × 盈亏比（2:1 / 3:1 / 5:1 等，可调）
11. **同K线禁止重复交易** — 同 K 线已开仓 / 刚平仓均禁止再开仓
12. **风控: 最大止损限制** — 止损点数超过上限（默认 1500 点）直接拒绝开仓
13. **最大同时持仓数** — 同时持仓数上限（默认 2，按 magic 只统计本 EA；分批止盈平掉部分后仍占名额）
14. **分批止盈** — 利润达 1×/2×/3× SL 空间时按 33%/50%/全部 比例分批平仓（每档比例独立可调）
15. **收盘强平 + 禁开仓（不持仓过夜）** — 距交易结束 ≤ 30 分钟禁开仓；≤ 2 分钟全部强平持仓，不论盈亏
16. **最小持仓时间** — 持仓未满 N 分钟（默认 20）时追踪止损不动作；SL/TP 始终正常触发

## 关键设计

- **三套追踪止损面板同时呈现**：A/B/C 在参数面板中始终都列出，用户使用时三选一勾选即可。
- **互斥逻辑**：当多套同时被勾选时，模块在 `Init()` 中打印警告并按优先级 A > B > C 处理。
- **共享基础 SL/TP**：固定止损/止盈参数被三套追踪共用，避免重复设置（默认盈亏比 2:1）。
- **锁死特性**：追踪 B 触发一次性保本后即锁死 SL（适合震荡市/剥头皮）。
- **形态追踪（v4.18 采用金刚经原版模块）**：追踪 C 完全移植金刚经策略实现——阶段1 利润<300 点 SL 不动；阶段2 利润≥300 点 SL 移开仓±55 保本锁；阶段3 **摆动点检测**（strength=2，扫描最近 60 根，找最近摆动低/高点）放支撑位下方/压力位上方 `InpTrailingCSLBufferPts`（20 点）缓冲；`InpTrailingCUsePatternOnly=true` 可跳过触发阶段直接独立使用形态止损。
- **追踪 C 阶段门控（v4.18 修复）**：非 pattern-only 模式下，利润 < `InpTrailingCTriggerPts`（300 点）时 SL 完全不移动、不进入阶段 2/3（旧版利润<300 也会进阶段 2，若开仓后支撑位在开仓价上方，SL 会被提前上移）；触发保本锁后才开始形态追踪。
- **盈亏比可调（v4.06 新增）**：`InpUseRiskRewardRatio=true` 时，开仓与补设 SL/TP 的 TP 点数 = SL 点数 × `InpRiskRewardRatio`，支持 2:1 / 3:1 / 5:1 任意可调；关闭则用固定 TP 660。
- **同K线禁止重复交易（v4.18 金刚经 v1.21 双修复）**：30 秒内真实发生的本 EA 平仓才记录冷却（历史单/其他 EA 忽略）；记录当前 K 线时间 `iTime(..., 0)`，bar0 变 bar1 后正确解除冷却，严格只冷却 1 根 K 线。
- **最大止损限制（v4.07 新增）**：`OpenPosition()` 中若 `slPoints > InpMaxSLPoints`（默认 1500 点）则直接拒绝开仓并打印日志，防止单笔止损过大的风险敞口。
- **最大同时持仓数（v4.18 金刚经 v1.20 修复）**：`OpenPosition()` 用 `CountPositionsByMagic()` 按 magic 只统计本 EA 持仓；**effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1**（去掉 InpUseTieredTP 依赖）；**开仓成功后立即清零 m_anyTier1Triggered**，每个新仓位必须独立走出 1× 利润才能允许下一仓；分批平掉部分后该仓位仍占名额。
- **分批止盈（v4.08 新增）**：参照金刚经 v1.16 模式，按 1×/2×/3× SL 空间利润分档触发（33%/50%/全部），模块用 `m_trailStage[100]` 追踪每张已分批档位。
- **最小持仓时间（v4.18 新增，参照金刚经 v2.06）**：持仓未满 `InpMinHoldMinutes`（默认 20 分钟）时，追踪 A/B/C 完全不动作——**SL/TP 始终由经纪商端正常触发，本保护只拦截"移动 SL"这一动作**；分批止盈与收盘强平不受拦截。
- **编译级修复（v4.18，两个致命 BUG）**：
  1. `TRAIL_SLOT_COUNT` 原为类内 `static const int` —— MQL5 中类内 `static const` **不是编译期常量**，不能作数组成员数组维度（报 `constant expression required`）。改用文件顶部 `#define TRAIL_SLOT_COUNT 100`，并用 `#ifndef` 保护以兼容调用方自定义。
  2. `m_trailStage[TRAIL_SLOT_COUNT]` 在 **6 处被使用但类内从未声明**（报 `error 256: undeclared identifier`）—— 已补声明，与 `m_trailTickets[]` / `m_trailSlotUsed[]` 成套。
- **EA 侧分批止盈联动 API（v4.18 新增）**：`NotifyTier1Triggered()` / `IsTier1Triggered()` —— EA 自行实现分批止盈（关 `InpUseScalingOut`）时，第 1 档平仓成功后必须回传通知，否则 `m_anyTier1Triggered` 恒为 `false` → `effectiveMaxPos` 恒为 `1` → **永远开不出第 2 仓**。
- **编译前静态自检工具（v4.18 新增）**：`scripts/check_mqh.py` —— 无 MetaEditor 环境下体检 `.mqh`（input 声明、成员数组维度、类内 static const、括号配对、声明-定义配对），可复现真实编译器的报错类别。
- **独立 SL/TP 开关**：用户可单独关闭固定止损或止盈；追踪 A/B/C 仍可独立运行。
- **TP 保留硬约束**：所有 `PositionModify(ticket, newSL, ...)` 第三参数必须传 `currentTP`，绝不能传 0（传 0 会清掉 660 点止盈）。
- **追踪优先级（v4.02 修复）**：`g_Common.OnTick()` 必须放在 `IsTradingAllowed()` 检查**之前**，避免非交易时间/日亏损/点差超标时追踪被跳过，导致"已盈利 300 点但 SL 还在原位"的灾难。
- **失败日志（v4.02 修复）**：所有 `PositionModify` 通过 `SafeModifyPosition()` 包装，失败时打印 retcode + 上下文，方便排查。
- **价格差触发（v4.03 修复）**：用 Bid/Ask 价格差计算 `profitPoints`，不用 `POSITION_PROFIT` 反算（避免 swap 吃掉点数）。
- **needMove 对称（v4.03 修复）**：BUY 和 SELL 都需要 `(currentSL == 0)` 强制分支，避免一侧漏判导致无 SL 持仓不更新。
- **持久化追踪索引（v4.04 修复）**：内置 `FindOrCreateTrailSlot` + `PruneClosedTrailSlots` 工具，容量 100、环形写入、自动清理已平仓订单；解决"10 槽位 + 只增不减"导致的第 11 单静默跳过问题。
- **SKIP 诊断日志（v4.04 修复）**：追踪 A/B/C 触发条件满足但 SL 不需修改时打印 SKIP 日志（含 ticket / profit / newSL / currentSL），方便排查"为何第 N 单没动"。
- **交付即部署（v4.19 修正）**：EA 只放在外部项目目录时 **F7 能编译、F5 静默失败**。Skill 现在把「部署进 `<终端数据目录>\MQL5\Experts\`」列为交付必做步骤，并提供 `scripts/deploy_to_terminal.py`（自动发现终端 + SHA-256 校验 + 调试日志核查）。同时修正了文档中把 MT5 目录写成 `MQL5/Includes/` 的错误（实际为 **`MQL5\Include\`**，单数）。
- **当日风控改为"净值口径"（v4.20 修复）**：`m_dailyLoss` 原为"只加亏损、不加盈利"的毛亏损累加，且 `Init()` 会清零、历史重建只恢复连亏不恢复日亏损 → 分批止盈的盈利完全不抵扣，EA 重启后当日已亏 5% 也会重新开始交易。现改为 `当日已实现净盈亏 = Σ(profit+swap+commission)`（账户级），净亏损 = `max(0, -净盈亏)`，阈值分母固定为当日起始余额，且每次检查都从历史幂等重算。
- **连亏暂停按"持仓"判盈亏（v4.20 修复）**：原实现按**单笔 deal** 判断盈亏，分批止盈时盈利档位（`net>0`）会把 `m_consecutiveLoss` 清零 —— 真实亏损被抵消，**连亏永远凑不齐 N 笔**；且只靠 `OnTrade()` 增量 + `static` 票号游标，EA 未接线即完全不计数。现以 `DEAL_POSITION_ID` 归组求和（+200/+400/−900 → 判 1 笔亏损 −300），并按 magic 只统计本 EA；`RefreshDayStats()` 由 `IsTradingAllowed()` / `OnTrade()` / `OnTimer()` 三处触发，不依赖 EA 是否接了 `OnTrade()`。
- **暂停状态持久化（v4.20 新增）**：`GlobalVariable` `CTM_PAUSE_<magic>`（到期时间）/ `CTM_LOSSRESET_<magic>`（连亏统计起点）—— EA 重启、改参数、重编译后暂停不丢，也不会把已翻篇的旧连亏重算一遍。
- **3 个编译错误修复（v4.20）**：模块此前**从未真机编译过**（只有静态自检），藏有 `CTrade::SetComment()` 不存在、`CTrade::ResultRequestDescription()` 不存在、注释边框漏 `//` 三个错误。v4.20 用 MetaEditor 命令行实机编译到 **0 errors / 0 warnings**（TradeMax 与 BTGT 两个终端均验证）。

## 交付文件

| 文件 | 说明 |
|---|---|
| `mt5-ea-common-trading-module.skill` | 可直接安装/分发的 WorkBuddy Skill 包 |
| `SKILL.md` | Skill 定义与 v4.19 使用说明 |
| `MT5_EA_Common_Trading_Module.mqh` | 核心 MQL5 通用模块（#include 即可复用，含三套追踪 + 盈亏比 + 防重开） |
| `Example_EA_Template.mq5` | 示例 EA 模板（v4.00），展示如何接入通用模块 |
| `parameters.md` | 所有输入参数的详细说明 + A/B/C 对比表 |
| `references/deployment.md` | **（v4.19 新增）** 部署与调试权威指南：F5 为何静默失败、日志/ex5 体积判据、目录布局与 include 写法对照、验证清单、故障排查表 |
| `scripts/deploy_to_terminal.py` | **（v4.19 新增）** 一键部署 + 调试核查脚本（自动发现终端、SHA-256 校验、`--list/--dry-run/--pull-ex5/--check-log`） |
| `scripts/check_mqh.py` | （v4.18 新增）`.mqh` 编译前静态自检器 |

## 使用方式

1. 将 `MT5_EA_Common_Trading_Module.mqh` 放入 MT5 终端数据目录的 **`MQL5\Include\`**（注意是 `Include`，**单数**；MT5 里不存在 `Includes` 目录），或者直接把模块内容并入 EA 做成单文件。
2. 在 EA 中 `#include` 该文件（放在 `Include\` 时用尖括号 `#include <MT5_EA_Common_Trading_Module.mqh>`）。
3. 声明 `CCommonTradingModule g_Common;` 全局实例。
4. 在 `OnInit`/`OnTick`/`OnTrade`/`OnTimer` 中调用对应函数。
5. 替换 `CheckEntrySignal()` 为你自己的策略入场逻辑。
6. **★ 把 EA 部署进终端数据目录**（否则无法 F5 调试，见下节）：
   ```bash
   python scripts/deploy_to_terminal.py --expert <你的EA.mq5> --include <模块.mqh> --terminal all
   ```
7. 在 MT5 参数面板中：
   - **强趋势策略** → 勾选"启用追踪A"
   - **震荡/剥头皮策略** → 勾选"启用追踪B"
   - **形态/支撑压力策略** → 勾选"启用追踪C"
   - **调整盈亏比** → 改 `InpRiskRewardRatio`（2 / 3 / 5 等）
   - **不使用追踪** → 三套都不勾选，按固定 SL/TP 运行

## 部署与调试（v4.19 新增，交付必读）

**症状**：EA 放在外部目录（如 `F:\...\EA系列\`）时，**F7 能编译、F5 按下去毫无反应**——不报错、不提示、进程直接退出。

**根因**：MetaEditor 的调试由 `metatester64.exe` 完成，它**只会在 MT5 终端自己的数据目录里定位 EA**：

```
<终端数据目录>\MQL5\Experts\<EA名称>.mq5
```

**判定铁证**（`...\Terminal\<哈希>\logs\metaeditor.log`，UTF-16LE）：
- 调试成功 → 出现 **`MQL5 debugger`** 行
- 静默失败 → **只有 `Compile` 行，从不出现 `MQL5 debugger`**
- 辅助判据 → F5 产出的 `.ex5` 体积约为普通编译的 **1.6~1.8 倍**（如 107 KB → 177 KB）

**正确姿势**：打开目标 MT5 终端 → 按 **F4**（不要用资源管理器双击 `.mq5`，本机 `.mq5` 关联到另一个终端的 MetaEditor，会绑定到未运行的终端）。

**一键核查**：
```bash
python scripts/deploy_to_terminal.py --list
python scripts/deploy_to_terminal.py --check-log <EA名称> --terminal all
```

完整说明（目录布局 × include 写法对照表、4 项验证清单、7 行故障排查表）见 `references/deployment.md`。


## 后续扩展

- 可在此基础上继续添加其他通用功能（如分批止盈、移动止损、新闻过滤等）。
- 若策略需要特殊的指标入场逻辑，直接修改 `Example_EA_Template.mq5` 中的 `CheckEntrySignal()` 函数即可。
- 任何新 EA 策略只要 `#include` 此模块并保留参数面板顺序，v4.06 的完整功能将自动继承。
