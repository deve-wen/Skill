---
name: mt5-ea-common-trading-module
description: 'Generate a reusable MQL5 common trading module (v4.20) for MT5 EAs and deploy the EA into <terminal data>\MQL5\Experts\ so F5 debugging works. Use for any MT5 EA strategy needing: Beijing trading hours, lot sizing, SL/TP switches, risk-reward ratio, same-bar no-reentry, max-stop-loss, max concurrent positions (magic-filtered), 3-stage scaling-out, 3 trailing modes (A progressive / B one-shot break-even / C pattern swing, mutex), daily net-loss cap, consecutive-loss pause, min-hold-time gate, end-of-session close-all. Trailing uses raw Bid/Ask differential, preserves TP on modify, treats currentSL==0 as forced-move, persistent trail slots (#define TRAIL_SLOT_COUNT 100). v4.20 rewrites daily-loss and consecutive-loss tracking as an idempotent per-position (DEAL_POSITION_ID) recompute: wins offset losses before the 5% cap, and scaling-out no longer resets the loss streak; pause persists via GlobalVariable. Deployment guide included: EAs outside MQL5\Experts\ compile with F7 but silently fail on F5.'
---

# MT5 EA 通用交易模块 Skill v4.20（模块 v4.20）

> **版本口径**：Skill 与模块同版本 `v4.20`（本次模块代码有实质修改：重写日亏损与连续亏损统计）。
> v4.19 只改文档与部署工具，模块停留 v4.18；v4.20 起两者对齐。

## Overview

This skill packages the v4.20 standard trading-management panels shown in the MT5 EA input dialog — including **three independent trailing-stop modes (A progressive / B one-shot break-even / C pattern-based)**, **independent SL/TP switches**, **adjustable risk-reward ratio**, **same-bar no-reentry guard**, **max-stop-loss limit**, **max concurrent positions**, **3-stage scaling-out**, **end-of-day close-all**, and **consecutive-loss pause** — into a single reusable MQL5 module.

When the user asks to develop any MT5 EA strategy and wants those common panels to be included automatically, generate the common module and an example EA template, explain how to integrate it, and **deploy the resulting EA into the MT5 terminal data directory** so that F5 debugging works.

> ⚠️ **F5 前置条件**：EA 必须位于 `<终端数据目录>\MQL5\Experts\` 才能被 MetaEditor 调试器（`metatester64.exe`）定位。只放在外部项目目录时 **F7 能编译、F5 静默失败**。详见第 17 节与 `references/deployment.md`。

## Triggering phrases

- "开发一个 MT5 EA"
- "EMA55MA233SuperTrend 共振吞没入场"
- "两套追踪止损都要保留"
- "按形态追踪止损" / "支撑位下方止损" / "形态止损"
- "盈亏比可调" / "盈亏比2:1 / 3:1 / 5:1"
- "同一根K线不能重复开仓" / "刚平仓不允许再开仓"
- "通用交易模块"
- "EA 仓位/止损/风控"
- "v4.18 参数面板" / "v4.20 参数面板"
- "按 F5 没反应" / "F5 调试失败" / "能编译不能调试"
- "EA 部署到 MT5" / "装到 Experts 目录" / "终端数据目录"
- "metaeditor.log 里没有 MQL5 debugger"
- "连续亏损3笔没暂停" / "连亏暂停不生效" / "暂停90分钟没触发"
- "日亏损5%没停止" / "当日最大亏损不生效" / "净亏损"

## Workflow

1. **Confirm requirements**: Verify whether the user wants only the common module, or also a full EA template with strategy-specific entry logic.
2. **Emit core asset**: Copy or customize `MT5_EA_Common_Trading_Module.mqh` to the user's project.
3. **Emit example EA** (optional): Copy `Example_EA_Template.mq5` and replace the placeholder `CheckEntrySignal()` with the user's actual strategy.
4. **Reference parameters**: If the user asks about specific inputs, load `parameters.md`.
5. **Integration instructions**: Tell the user how to `#include` the module, instantiate the class, and wire `OnTick`, `OnTrade`, `OnTimer`, and `OnInit`.
6. **★ Deploy into the MT5 terminal data directory**（**必做，否则用户无法 F5 调试**）:
   - Run `scripts/deploy_to_terminal.py` to place the `.mq5` into `<terminal data>\MQL5\Experts\` and the `.mqh` into `<terminal data>\MQL5\Include\` (all detected terminals).
   - **Never deliver an EA that only lives in an external project folder** (e.g. `F:\...\EA系列\`) — F7 will compile it, but **F5 will fail silently** with no error and no message.
   - Tell the user the correct launch path: open the MT5 terminal → press **F4** (do **not** double-click the `.mq5` in Explorer).
   - Full rationale, verification checklist and troubleshooting: load `references/deployment.md`.

## v4.20 input panel structure

The module presents this control panel in MT5:

```
=== ★ 交易时间(北京时间) ===
   服务器比北京晚N小时(MT5=5)              5
   交易开始 时/分(北京)                     7 : 30
   交易结束 时/分(北京次日)                 3 : 30

=== ★ 仓位管理 ===
   true=固定手数 false=百分比               true
   固定手数                                 1.0
   风险百分比(%)                            1.0
   最小手数 / 最大手数                       0.01 / 10.0

=== ★ 止损止盈开关 ===
   启用固定止损                              true
   启用固定止盈                              true

=== ★ 止损与追踪(共用基础参数) ===
   固定止损点数                              300
   固定止盈点数                              660

=== ★ 追踪方式A: 渐进式(持续追踪SL,二选一) ===
   启用追踪A(与B/C互斥)  ← 勾选即用A        false
   A: 追踪激活利润点数                        20
   A: 保本点数(SL移入场价)                   320

=== ★ 追踪方式B: 一次性保本(触发后锁死,二选一) ===
   启用追踪B(与A/C互斥)  ← 勾选即用B        false
   B: 触发保本的利润点数                      320
   B: 保护利润(SL移开仓土此点数)              20

=== ★ 追踪方式C: 形态追踪(支撑/压力摆动位,二选一) ===
   启用追踪C(与A/B互斥)  ← 勾选即用C        false
   C: true=跳过触发阶段直接形态追踪           false
   C: 触发激活的利润点数(SL移到保本+保护点)   300
   C: 激活后SL移到开仓±此保护利润点数         55
   C: 形态追踪SL距支撑/压力位缓冲(点)         20
   C: 形态识别周期(摆动点检测)                PERIOD_M1

=== ★ 风控管理 ===
   启用当日最大亏损限制 / 当日最大亏损(%)    true / 5.0
   启用点差限制 / 最大允许点差               true / 50

=== ★ 风控: 最大止损限制 ===
   启用最大止损限制(止损过大不开仓)          true
   最大允许止损点数(默认1500点=15美金)       1500

=== ★ 连续亏损暂停 ===
   启用连续亏损暂停                           false
   连续亏损N次后暂停 / 暂停时间(分钟)         3 / 90

=== ★ 盈亏比设置(可调) ===
   启用盈亏比自动算止盈(TP=SL×盈亏比)        true
   盈亏比(2:1=2.0 / 3:1=3.0 / 5:1=5.0)      2.0

=== ★ 最大同时持仓数 ===
   最大同时持仓数(2=分批止盈平仓部分后可开新仓)  2
   盈亏比(TP/SL倍数): 2:1, 3:1, 3.2:1, 5:1等  3.0

=== ★ 分批止盈(独立开关,每档比例可调) ===
   启用分批止盈(利润达1/2/3倍止损空间分批平仓)  true
   第1档触发: 利润达此倍止损空间                1.0
   第1档平仓比例(占总仓位): 0.25=1/4, 0.33=1/3, 0.50=1/2  0.33
   第2档触发: 利润达此倍止损空间                2.0
   第2档平仓比例(占剩余仓位)                   0.5
   第3档触发: 利润达此倍止损空间                3.0
   第3档平仓比例(剩余全部, 默认1.0)            1.0

=== ★ 同K线禁止重复交易 ===
   同一根K线已开仓则禁止再开                  true
   同一根K线刚平仓则禁止再开                  true

=== ★ 收盘强平 + 禁开仓(不持仓过夜) ===
   总开关                                      true
   强平提前量(分钟): 距交易结束≤N分钟强平所有持仓,不论盈亏  2
   禁开仓提前量(分钟): 距交易结束≤N分钟禁止开新仓  30

=== ★ 最小持仓时间(仅延迟启用追踪止损, SL/TP 始终正常触发) ===
   启用最小持仓时间保护                        true
   最小持仓分钟数: 未满此时长不启用追踪        20
```

> ⚠️ **两个容易被忽略的默认值**：
> - `启用连续亏损暂停` 默认 **`false`** —— 不勾选就完全不会暂停。启动日志会打印 `连续亏损暂停 已启用 / *** 未启用 ***`，先看这一行。
> - `启用当日最大亏损限制` 默认 `true`，阈值 5.0；口径是**当日已实现净盈亏**（盈利抵扣亏损），分母为**当日起始余额**。

## Core capabilities

### 1. 交易时间（北京时间）
- Converts server time to Beijing time using `InpServerHourDiff`.
- Supports overnight trading windows (e.g., 7:30 to next-day 3:30).

### 2. 仓位管理
- `InpUseFixedLot=true` uses fixed lots.
- `InpUseFixedLot=false` calculates lots based on `InpRiskPercent`, stop-loss points, tick value, and tick size.
- Enforces `InpMinLot` / `InpMaxLot` and symbol volume step.

### 3. 止损止盈开关
- `InpUseFixedStopLoss` (true) / `InpUseFixedTakeProfit` (true) — 单独控制开仓时是否设置固定 SL/TP。
- 关闭后 `OpenPosition()` 不会设固定 SL/TP；追踪模式 (A/B/C) 仍可独立运行并自动接管 SL。

### 4. 共用基础止损止盈
- `InpFixedSLPoints` (300) and `InpFixedTPPoints` (660) are shared by all three trailing modes (默认盈亏比 2:1：SL300 / TP660)。
- `ApplyStopLossTakeProfit()` only fills in missing SL/TP — it never overwrites a SL that has already been moved by Mode A/B/C.
- 若 `InpUseFixedStopLoss=false`，则 `ApplyStopLossTakeProfit()` 不会补设 SL（但 TP 仍可补）。

### 5. 追踪方式 A：渐进式
- Tracked by `ApplyTrailingStop()`.
- **Phase 1 (break-even)**: when profit ≥ `InpTrailingABreakEvenPts` (320), move SL to entry price ± 2 points and stop trailing for that tick.
- **Phase 2 (active trailing)**: when profit ≥ `InpTrailingAActivatePts` (20) and < 320, move SL to current price ± 1 point every tick.
- Suitable for **strong trend strategies** — let profits run, SL keeps trailing tightly.

### 6. 追踪方式 B：一次性保本（触发后锁死）
- Tracked by `ApplyTrailingB()`.
- When profit ≥ `InpTrailingBTriggerPts` (320), move SL to entry price ± `InpTrailingBProtectPts` (20 points) **once** and lock it.
- Suitable for **ranging or scalping strategies** — lock in a small profit and don't give it back.

### 7. 追踪方式 C：形态追踪（支撑/压力摆动位，金刚经 v1.2x 原版）
- Tracked by `ApplyTrailingC()` — **direct port of the JinGangJing EA's Trailing-C module**.
- **Phase 1 (gate)**: if profit < `InpTrailingCTriggerPts` (300) → return immediately, **SL never moves**.
- **Phase 2 (break-even lock)**: when profit ≥ 300, SL = entry price ± `InpTrailingCProtectPts` (+55).
- **Phase 3 (pattern trailing)**: swing-point detection (`strength=2`, scan back up to 60 bars on `InpTrailingCPatternTF`):
  - BUY → find nearest swing **low** → `patternSL = swingLow - InpTrailingCSLBufferPts` (20), adopt only if more favorable than break-even targetSL.
  - SELL → find nearest swing **high** → `patternSL = swingHigh + InpTrailingCSLBufferPts` (20), adopt only if more favorable.
  - Only moves when the new SL is better (BUY higher / SELL lower). No swing found → fall back to break-even targetSL (graceful).
- **Pattern-only mode**: `InpTrailingCUsePatternOnly=true` skips Phases 1–2 and goes straight to Phase 3 — **use pattern-based trailing standalone**.
- Suitable for markets with **clear support/resistance structure**.

### 8. 互斥逻辑 (Mode A / B / C)
- All three modes are listed in the panel at all times; the user picks exactly **one** by ticking the appropriate checkbox.
- If multiple are ticked simultaneously, `Init()` counts and prints a warning, **priority A > B > C** wins.
- `IsTrailingAEnabled()` / `IsTrailingBEnabled()` / `IsTrailingCEnabled()` implement the mutex logic.

### 9. 风控管理（v4.20 重写：当日**净**亏损口径）
- **当日最大亏损**：`当日已实现净盈亏 = Σ(profit + swap + commission)`（账户级，含所有 EA 与手动单，即"当日所有交易之和"）。
  `净亏损 = max(0, -净盈亏)`；当 `净亏损 ≥ 起日余额 × InpDailyLossPercent%` 时，当日**禁止开新仓**。
  - **盈利抵扣亏损**：+800 与 -300 并存 → 净 +500 → 不触发（旧版会累加成"毛亏 300"而误判）。
  - **阈值分母固定**为当日起始余额 `m_dayStartBalance`，不随亏损扩大而缩小。
  - **重启不丢**：每次检查都从当日历史幂等重算，EA 重启/改参数后当日已亏 5% 依然拦住。
  - 实现：`RefreshDayStats()`（节流 `STATS_RECALC_SECONDS`=2 秒）+ `CheckDailyLossLimit()`。
- **点差限制**：`spread > InpMaxSpreadPoints` 时禁止开仓。
- 两者都在 `IsTradingAllowed()` 中检查，`OpenPosition()` 每次开仓都会重新校验。

### 10. 连续亏损暂停（v4.20 重写：按**持仓**判盈亏，不再被分批止盈破解）
- 触发条件：**本 EA**（按 `DEAL_MAGIC` 过滤）连续 `InpConsecutiveLossCount` 笔交易净亏损 → 暂停 `InpPauseMinutes` 分钟禁止开新仓。
- **旧实现三个漏（已修）**：
  1. 只靠 `OnTrade()` 增量 + 函数内 `static` 票号游标 —— EA 未接线或事件被 1 秒节流吞掉就完全不计数；
  2. **按单笔 deal 判盈亏** —— 分批止盈的盈利档位（`net>0`）会把连亏计数清零，真实亏损被抵消，**连亏永远凑不齐 N 笔**；
  3. `m_pauseUntil` 只在内存，EA 重启即丢。
- **现实现**：以 `DEAL_POSITION_ID` 为"一次交易"归组求和 → 一次交易里 3 档平仓 (+200/+400/−900) 判为 1 笔亏损 −300（旧版判成 0 笔亏损）。
- **统计来源**：`RefreshDayStats()` 从当日历史幂等重算，每 2 秒节流；`IsTradingAllowed()` / `OnTrade()` / `OnTimer()` 三处都会触发，**不依赖 EA 是否接了 `OnTrade()`**。
- **暂停持久化**：`GlobalVariable` 名 `CTM_PAUSE_<magic>`（到期时间）+ `CTM_LOSSRESET_<magic>`（连亏统计起点），重启后暂停不丢、也不会把已翻篇的旧连亏重算一遍。
- **暂停到期后**：`m_lossCountResetAt = now` → 只统计此刻起的交易，不会一到期就立刻再次触发。
- 日志：
  ```
  CommonModule: 连续亏损暂停 已启用（连亏 3 笔 → 暂停 90 分钟）
  CommonModule: 【连续亏损暂停】已连亏 3 笔（阈值 3）→ 暂停 90 分钟，至 2026.10.17 13:05 前禁止开新仓
  ```
- ⚠️ **`InpUseConsecutiveLossPause` 默认值为 `false`**：必须在参数面板勾选。`Init()` 会打印 `连续亏损暂停 已启用 / *** 未启用 ***`，启动后先看这一行。


### 11. 盈亏比设置（可调）
- `InpUseRiskRewardRatio=true` → TP 点数自动 = SL 点数 × `InpRiskRewardRatio`（2:1 / 3:1 / 5:1 任意可调）。
- Applies in both `OpenPosition()` and `ApplyStopLossTakeProfit()` (missed-SL/TP fill-in).
- 例：SL 300 点 + 2:1 → TP 600；3:1 → 900；5:1 → 1500。
- 关闭后回退到 `InpFixedTPPoints`（660）固定止盈。
- 盈亏比 < 0.1 时回退 2.0（防呆）。

### 12. 同K线禁止重复交易（金刚经 v1.21 冷却修复）
- `InpSameBarNoReopen=true` → 同一根 K 线已开过仓（无论是否平仓）禁止再次开仓。
- `InpSameBarNoAfterClose=true` → 同一根 K 线刚平仓，决不允许再开仓入场交易。
- 实现：模块记录 `m_lastOpenBarTime` / `m_lastCloseBarTime`；`OpenPosition()` 开头比对当前 K 线时间，命中则拒绝并打印日志。
- 开仓成功后本 K 线内永不再开（直到下一根 K 线）。
- **v1.21 修复 1（30 秒过滤）**：`OnTrade()` 中只认 30 秒内真实发生的本 EA 平仓才记录冷却：
  ```cpp
  bool isRecent = (dealTime > 0 && (TimeCurrent() - dealTime) <= 30);
  if(isRecent && dealMagic == m_magic && dealEntry == DEAL_ENTRY_OUT)
  ```
  - 历史平仓单（几天前）`isRecent=false` → 不记录冷却
  - 其他 EA / 手动单 `dealMagic != m_magic` → 不记录冷却
- **v1.21 修复 2（记录当前 K 线）**：用 `iTime(_Symbol, PERIOD_CURRENT, 0)` 记录当前K线时间，bar0 变 bar1 后正确解除冷却，严格只冷却 1 根 K 线（旧逻辑 `iTime(..., 1)` 会少冷却 1 根）。

### 13. 风控：最大止损限制（止损过大不开仓）
- `InpUseMaxSLPoints=true` 时，若 `slPoints > InpMaxSLPoints`，`OpenPosition()` 直接拒绝开仓并打印：
  ```
  CommonModule: 拒绝开仓 — 止损过大 (X 点 > 上限 Y 点)
  ```
- 默认上限 1500 点（≈ 15 美金），用户可根据品种与资金调整。
- 与「风控管理」互补：风控管理管综合维度（时间/日亏损/点差/暂停），最大止损限制管单笔风险敞口上限。
- 关闭后不限制 SL 大小（不推荐，止损过大会导致单笔风险失控）。

### 13.5 收盘强平 + 禁开仓（不持仓过夜，金刚经 v2.04 模式）
- `InpUseEndCloseAll=true`（总开关）时启用以下两个机制：
  - **收盘强平**：距交易结束 ≤ `InpCloseAllMinsBeforeEnd`（默认 2 分钟）时，`ManageAllPositions()` 开头遍历所有本 EA 持仓，逐一 `PositionClose`，**不论盈亏**。典型日志：
    ```
    [EndCloseAll] OK ticket=X profit=Y (距结束=N分钟)
    ```
  - **禁开仓**：距交易结束 ≤ `InpNoEntryMinsBeforeEnd`（默认 30 分钟）时，`OpenPosition()` 开头直接拒绝：
    ```
    CommonModule: 拒绝开仓 — 距交易结束仅 N 分钟（≤ 禁开仓阈值 M 分钟）
    ```
- `MinutesToEndOfTrading()` 处理**跨日场景**（如 7:30 ~ 次日 3:30），服务器时间 + 时差转北京时间，跨日时正确返回分钟数。
- `InpUseEndCloseAll=false` 时两个阈值都失效，行为退化为"允许持仓过夜"。

### 13.6 最小持仓时间（仅延迟启用追踪止损，金刚经 v2.06 模式）
- `InpUseMinHoldTime=true` + `InpMinHoldMinutes=20`：持仓未满 20 分钟时，**追踪 A/B/C 完全不动作**。
- **语义关键**：SL/TP 始终由经纪商端正常触发，本保护**只拦截"移动 SL"这一动作**；期间价格打掉 SL 或 TP 属正常平仓，**不干预**。
- **不受拦截**：分批止盈（`ApplyScalingOut`）、收盘强平（`CloseAllBeforeEndOfTrading`）、服务端 SL/TP。
- 实现：`GetHeldMinutes(ticket)` = `(TimeCurrent() - POSITION_TIME) / 60`；`IsMinHoldTimeSatisfied(ticket)` 判定是否放行；`ManageAllPositions()` 中未满时长则 `continue`。
- 拦截日志 60 秒节流防刷屏：
  ```
  [MinHoldTime] BLOCK Trailing ticket=X 已持仓=N分钟 < 要求=M分钟 (继续持仓)
  ```
- 公开 API 供 EA 自有逻辑复用：`CheckMinHoldTime(ticket)` / `GetHeldMinutes(ticket)`。
- `InpUseMinHoldTime=false` 或 `InpMinHoldMinutes<=0` → 恒放行（防呆）。

### 14. 最大同时持仓数（金刚经 v1.20 effectiveMaxPos + 每仓独立证明）
- `InpMaxPositions`（默认 2）控制 **本 EA** 同时能持多少张仓位。
- `OpenPosition()` 调用 `CountPositionsByMagic()` —— **按 magic 号只统计本 EA 的持仓**（排除其他 EA / 手动单 / 其他品种），已满则拒绝。
- **核心公式（金刚经 v1.20 修复 1：去掉 InpUseTieredTP 依赖）**：
  ```cpp
  int effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1;
  if(CountPositionsByMagic() >= effectiveMaxPos) 拒绝;
  ```
- **v1.20 修复 2：开仓成功后立即清零** `m_anyTier1Triggered = false`——**每个新仓位必须独立走出 1× 利润才能允许下一仓**。
- **保护门语义**：
  - `m_anyTier1Triggered=true` → `effectiveMaxPos = InpMaxPositions`（默认 2，允许双仓）
  - `m_anyTier1Triggered=false` → `effectiveMaxPos = 1` → **严格单仓**
- `m_anyTier1Triggered` 状态维护：
  - Init 中扫描追踪槽位恢复（任何仓位 stage>=1 → true）
  - 第 1 档触发后置 true
  - **开仓成功后立即清零**（v1.20 关键）
- 分批止盈平掉部分仓位后，仓位 ticket 不变仍占 1 个名额，完全平仓才释放。
- 设为 0 或负数则不限制。

### 15. 分批止盈（金刚经 v1.16 模式）
- 默认 3 档：1×SL → 平 33% / 2×SL → 平剩余 50% / 3×SL → 平剩余全部。
- 每档 trigger（倍 SL 空间）+ ratio（平仓比例）独立可调。
- 实现：模块用 `m_trailStage[100]` 追踪每张已分批档位；触发时用 `PositionClosePartial` 平仓。
- 第 1 档按占总仓位，第 2/3 档按剩余仓位比例计算平仓量（向下对齐到 volume step）。
- 与追踪 A/B/C 互补：分批按利润分批，追踪按规则调 SL。
- 典型日志：
  ```
  [ScalingOut.Stage1] OK ticket=X closeLots=0.33 remaining=0.67 profit=300.0pts trigger=1.00xSL=300.0pts nextStage=1
  ```

### 16. 编译期约束与 EA 侧集成（v4.18 / v4.20 补充）

**容量常量必须用 `#define`，不能用类内 `static const`**：

```cpp
#ifndef TRAIL_SLOT_COUNT
#define TRAIL_SLOT_COUNT 100
#endif
```

MQL5 中类内 `static const int` 不是编译期常量 → 作数组成员数组维度会报 `constant expression required`。
模块已用 `#ifndef` 保护，EA 侧**不必再定义**该宏（若定义请放在 `#include` 之前，或直接删除）。

**成员数组与成员变量必须成套声明**：`m_trailTickets[]` / `m_trailSlotUsed[]` / `m_trailStage[]`
三者共同构成持久化追踪槽位（容量 `TRAIL_SLOT_COUNT`）。缺少 `m_trailStage[]` 会报 `error 256: undeclared identifier`
并连带 6 处引用全部失败。

**EA 侧自有分批止盈必须回传通知**（否则双仓永远锁死）：

```cpp
// 模块内分批止盈：无需处理，自动置位
// EA 侧分批止盈：第 1 档平仓成功后调用
g_Common.NotifyTier1Triggered();
bool st = g_Common.IsTier1Triggered();   // 查询状态
```

原理：`effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1`。
`m_anyTier1Triggered` 只在模块内 `ApplyScalingOut()` 第 1 档触发时置位；
EA 侧实现分批时若不回传，该位恒为 `false` → `effectiveMaxPos` 恒为 `1` → 永远开不出第 2 仓。
`OpenPosition()` 成功后会立即清零该位（金刚经 v1.20：每个新仓独立证明）。

**静态自检工具**：`scripts/check_mqh.py` ——
无 MetaEditor 环境下对 `.mqh` 做编译前体检（input 声明/成员数组维度/括号配对/声明-定义配对）：

```bash
python scripts/check_mqh.py MT5_EA_Common_Trading_Module.mqh
```

### 17. 部署与调试（F5 前置条件，v4.19 新增）

**问题**：MetaEditor 的调试（F5）由 `metatester64.exe` 完成，它**只会在 MT5 终端自己的数据目录里定位 EA**：

```
<终端数据目录>\MQL5\Experts\<EA名称>.mq5
```

源码放在外部项目目录（如 `F:\...\EA系列\`）时：

| 动作 | 结果 |
|---|---|
| **F7** 编译 | ✅ 成功（编译不依赖终端数据目录） |
| **F5** 调试 | ❌ **静默失败**——不报错、不提示、进程直接退出 |

**判定铁证（`...\Terminal\<哈希>\logs\metaeditor.log`，UTF-16LE）**：

- 调试成功 → 出现 **`MQL5 debugger`** 行
- 静默失败 → **只有 `Compile` 行，从不出现 `MQL5 debugger`**
- 辅助判据 → F5 会产出含调试信息的 `.ex5`，体积约 **1.6~1.8 倍**（如 107 KB → 177 KB）；体积没变大 = 没进调试器

**目录布局与 `#include` 写法对照（务必匹配）**：

| 布局 | `.mq5` | `.mqh` | `#include` 写法 |
|---|---|---|---|
| A. 单文件合并（推荐） | `MQL5\Experts\` | 已并入 `.mq5` | 无 |
| B. 模块走 Include | `MQL5\Experts\` | `MQL5\Include\` | `#include <MT5_EA_Common_Trading_Module.mqh>` |
| C. 同目录共存 | `MQL5\Experts\` | `MQL5\Experts\` | `#include "MT5_EA_Common_Trading_Module.mqh"` |

> ⚠️ 注意目录名是 **`MQL5\Include\`（单数）**，不是 `Includes`。
> ⚠️ 用引号 `"..."` 会优先在 `.mq5` 同目录找；`.mqh` 只在 `Include\` 时必须用尖括号 `<...>`，否则报 `cannot open source file`。

**一键部署**：

```bash
# 列出本机所有终端数据目录
python scripts/deploy_to_terminal.py --list

# 部署 EA + 模块到全部终端（自动发现，SHA-256 校验）
python scripts/deploy_to_terminal.py --expert <路径.mq5> --include <路径.mqh> --terminal all

# 预演 / 拉回 .ex5 / 核查是否真的进了调试器
python scripts/deploy_to_terminal.py --expert <路径.mq5> --dry-run
python scripts/deploy_to_terminal.py --pull-ex5 <路径.mq5> --terminal all
python scripts/deploy_to_terminal.py --check-log <EA名称关键字> --terminal all
```

**启动姿势（本机特有陷阱）**：`.mq5` 文件关联可能指向**另一个终端**的 `MetaEditor64.exe`——用资源管理器双击会打开"错误"的编辑器，F5 被绑定到未运行的终端，同样静默失败。
**正确做法：打开目标 MT5 终端 → 按 F4。**

**交付前验证清单**（详见 `references/deployment.md`）：源文件已落到 `MQL5\Experts\` 且哈希一致 → `.ex5` 已生成 → `metaeditor.log` 出现 `MQL5 debugger` → MT5 导航器「EA交易」下可见。

## Integration guide

### Step 1: Include the module

```cpp
#include "MT5_EA_Common_Trading_Module.mqh"
```

### Step 2: Declare global instance

```cpp
CCommonTradingModule g_Common;
```

### Step 3: Initialize in OnInit

```cpp
int OnInit()
{
   if(!g_Common.Init(20250709, "MyStrategy"))
      return INIT_FAILED;

   // ... your strategy-specific init (indicators, buffers, etc.)
   EventSetTimer(60);
   return INIT_SUCCEEDED;
}
```

### Step 4: Wire events

```cpp
void OnTick()
{
   // 【最优先】追踪：必须在风控检查之前执行
   // 避免"已盈利 300 点但 SL 还在原位"的灾难
   g_Common.OnTick();

   // 风控检查：仅用于控制"是否开新仓"
   if(!g_Common.IsTradingAllowed())
      return;

   // your entry signal logic
   ENUM_ORDER_TYPE signal = CheckEntrySignal();
   if(signal == ORDER_TYPE_BUY || signal == ORDER_TYPE_SELL)
   {
      double price = (signal == ORDER_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      g_Common.OpenPosition(signal, price, InpFixedSLPoints, InpFixedTPPoints);
   }
}

void OnTrade()
{
   g_Common.OnTrade();         // track daily loss and consecutive loss
}

void OnTimer()
{
   g_Common.OnTimer();         // expiry checks
}
```

### Step 5: Replace strategy entry logic

Open `Example_EA_Template.mq5` and replace the `CheckEntrySignal()` body with your actual EMA/SuperTrend/engulfing conditions.

## Resources

### MT5_EA_Common_Trading_Module.mqh
The reusable MQL5 include file. Deploy it to **`MQL5\Include\`** (note: `Include`, **singular**) inside the MT5 terminal data directory, or merge it into the EA as a single file. The literal folder name `MQL5/Includes/` does **not** exist in MT5.

### Example_EA_Template.mq5
A working EA skeleton that demonstrates module integration. Replace `CheckEntrySignal()` with real strategy logic. Must be deployed to `MQL5\Experts\` before F5 debug will work.

### references/deployment.md
**Deployment & debug guide (v4.19)** — why F5 silently fails outside the terminal data directory, the `metaeditor.log` / `.ex5`-size evidence, the two-terminal and file-association pitfalls on this machine, the three directory layouts vs `#include` syntax, a 4-item pre-delivery checklist and a troubleshooting table.

### scripts/deploy_to_terminal.py
Auto-discovers `%APPDATA%\MetaQuotes\Terminal\*\MQL5`, copies the `.mq5` → `Experts\` and `.mqh` → `Include\` with SHA-256 verification. Modes: `--list`, `--expert/--include/--terminal`, `--dry-run`, `--pull-ex5`, `--check-log` (parses the UTF-16LE `metaeditor.log` and reports whether this EA ever reached `MQL5 debugger`).

### scripts/check_mqh.py
Pre-compile static checker for the `.mqh` (input declarations, member-array dimensions, class-scope `static const`, brace/paren balance, declaration-definition pairing).

### parameters.md
Detailed description of every input parameter, its default value, behavior notes, and a Mode A vs B vs C comparison table.

## Notes

- The module is intentionally generic. It does not contain strategy-specific entry logic; that belongs in the EA file.
- Input defaults are taken from the user's screenshot. If the user asks to change defaults, update the `input` lines in the `.mqh` file and `parameters.md`.
- All prices/stops are normalized to `SYMBOL_DIGITS`.
- The module uses `CTrade` from `<Trade\Trade.mqh>` for order execution.
- v4.18 specifically: when multiple of A/B/C are ticked, the mode with the highest priority (A > B > C) wins and a warning is logged at init. **Trailing-C phase gate**: in non-pattern-only mode, if `profitPoints < InpTrailingCTriggerPts`, the function returns early — SL never moves and Phase-2 pattern trailing never runs until the break-even lock (Phase-1) has fired. BUG #6: Phase-2 support/resistance only from bars since position open (old code included pre-open bars, freezing SL).
- v4.20 specifically: **risk-statistics rewrite**. Daily-loss and consecutive-loss are no longer accumulated incrementally in `OnTrade()`; both are recomputed idempotently from the day's history by `RefreshDayStats()` (throttled by `STATS_RECALC_SECONDS`). Daily loss is now **net** (wins offset losses) against a fixed day-start balance. Consecutive losses are grouped by `DEAL_POSITION_ID` and filtered by magic, so scaling-out tiers can no longer reset the streak. Pause state is persisted in GlobalVariables `CTM_PAUSE_<magic>` / `CTM_LOSSRESET_<magic>`. Also fixes 3 compile errors that had never been caught (no real compile had ever been run): `CTrade::SetComment()` does not exist, `CTrade::ResultRequestDescription()` does not exist, and a comment border line missing its `//`.
- v4.19 specifically: **no MQL5 code change** — the module stays at v4.18 so its hash in every terminal stays stable. v4.19 adds `references/deployment.md` + `scripts/deploy_to_terminal.py`, corrects the non-existent folder name `MQL5/Includes/` to `MQL5\Include\`, and makes deployment into `MQL5\Experts\` a mandatory workflow step. **Delivering an EA only to an external project folder is now considered an incomplete delivery.**
- **CRITICAL anti-pattern #1 (TP clearing)**: when modifying SL via `PositionModify(ticket, newSL, ...)`, the third argument **MUST** be the current `POSITION_TP` value, **never** `0`. Passing `0` clears the take-profit.
- **CRITICAL anti-pattern #2 (trailing blocked)**: `g_Common.OnTick()` must be called at the **top** of `OnTick()`, **before** `IsTradingAllowed()` checks. Otherwise break-even/trailing is skipped during off-hours / over-loss / wide-spread periods, leading to catastrophic unprotected profits.
- **CRITICAL anti-pattern #3 (swap eats points)**: trigger trailing on raw Bid/Ask price differential, not on `POSITION_PROFIT / tickValue`. Overnight swap accumulation skews monetary profit and would prevent trailing from ever firing for held positions.
- **CRITICAL anti-pattern #4 (asymmetric needMove)**: both BUY and SELL `needMove` checks **MUST** include an explicit `(currentSL == 0)` forced-move branch. Without it, BUY would silently skip moving when an unmanaged position has no SL yet set.
- **CRITICAL anti-pattern #5 (10-slot trail index)**: persistent trail ticket arrays must have **capacity ≥ 100** (not 10) and **auto-prune closed positions** on every lookup. A "g_trailPersistCount++ only" pattern silently breaks trailing for the 11th and every subsequent position. Use the built-in `FindOrCreateTrailSlot` / `PruneClosedTrailSlots` helpers; never roll your own.
- **CRITICAL anti-pattern #6 (class-scope `static const` as array dimension)**: MQL5 does **not** treat a class-scope `static const int` as a compile-time constant. Using it as an array member dimension fails with `constant expression required`. Always use a file-scope `#define` (guarded with `#ifndef`) — this is exactly the v4.18 fix for `TRAIL_SLOT_COUNT`.
- **CRITICAL anti-pattern #7 (delivering the EA only to an external folder)**: an EA that lives only in the project directory (e.g. `F:\...\EA系列\`) compiles with **F7** but **F5 debug fails silently** — no error, no dialog. `metatester64.exe` only resolves sources under `<terminal data>\MQL5\Experts\`. Always run `scripts/deploy_to_terminal.py` before telling the user to debug, and tell them to open the terminal and press **F4** (never double-click the `.mq5`, which may launch a *different* terminal's MetaEditor and bind the debugger to a terminal that is not running).
- **CRITICAL anti-pattern #8 (per-deal P&L judgement)**: never judge win/loss per *deal*. With scaling-out, one trade produces several `DEAL_ENTRY_OUT` deals; a profitable tier would reset the consecutive-loss streak and a per-deal sum would inflate gross loss past the daily cap. Always group deals by `DEAL_POSITION_ID` and sum `profit+swap+commission` per position.
- **CRITICAL anti-pattern #9 (incremental risk counters)**: never keep `m_dailyLoss` / `m_consecutiveLoss` as `OnTrade()`-driven accumulators. If the EA omits `g_Common.OnTrade()`, or the event is throttled, the counters silently stay zero. Recompute from history idempotently (`RefreshDayStats()`), so the state is survivable and self-healing across restarts.
- **CTrade API trap (v4.20)**: `CTrade` has **no** `SetComment()` and **no** `ResultRequestDescription()`. Order comments must be passed through the `comment` parameter of `PositionOpen(...)`; request info comes from `ResultComment()`. Using the nonexistent members fails with `error 256: undeclared identifier 'SetComment'`.
- **Pair rule (v4.18)**: `m_trailTickets[]`, `m_trailSlotUsed[]` and `m_trailStage[]` form one unit — all three must be declared with the same `TRAIL_SLOT_COUNT` dimension. A missing declaration surfaces as `error 256: undeclared identifier` at every usage site (6 sites for `m_trailStage`).
- **EA-side scaling-out handshake (v4.18)**: if the EA implements partial closes itself (i.e. `InpUseScalingOut=false`), it **must** call `g_Common.NotifyTier1Triggered()` after its tier-1 partial close succeeds. Otherwise the double-position guard `effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1` stays `1` forever and the 2nd position can never open.
- **Pre-compile static check**: run `python scripts/check_mqh.py MT5_EA_Common_Trading_Module.mqh` to catch missing declarations, illegal array dimensions, brace/paren imbalance and declaration-definition mismatches without MetaEditor.
- **Pre-delivery deploy check (v4.19)**: run `python scripts/deploy_to_terminal.py --check-log <EA名称> --terminal all`. If it reports `本 EA 只有 Compile、没有 MQL5 debugger`, the EA has **never actually been debugged** — the fix is deploying it to `MQL5\Experts\`, **not** changing the code. Do not start hunting logic bugs in this situation.
- **Failure logging**: every `PositionModify` goes through `SafeModifyPosition()` which prints `retcode` + context on failure. Search the journal for `PositionModify FAILED` to find all failed modify calls.
- **Skip diagnostic logging**: every trailing mode prints a `[TrailingA.Phase2] SKIP`, `[TrailingB.OneShot] SKIP`, or `[TrailingC.Phase2] SKIP` line when the trigger conditions are met but the SL is already in the target position. Search for `SKIP ticket=` to find silent no-ops that look like dead trailing.
