---
name: mt5-ea-common-trading-module
description: 'Generate a reusable MQL5 common trading module (v4.17) for MetaTrader 5 Expert Advisors. Use when developing any MT5 EA strategy (e.g., EMA55MA233SuperTrend engulfing, or any future) and wants to inherit the common trading panels — Beijing trading hours, position/lot sizing, independent SL/TP switches, risk-reward ratio, same-bar no-reentry, max-stop-loss, max concurrent positions, 3-stage scaling-out (1×/2×/3× SL-space profit), fixed SL/TP, triple trailing-stop modes (A progressive + B one-shot break-even + C pattern-based, mutex), risk control (daily loss + spread limit), and consecutive-loss pause. Trailing runs unconditionally in OnTick, triggers on raw Bid/Ask differential, preserves TP via read-back, treats (currentSL==0) as forced-move, logs retcode on modify failure, and ships a persistent-trail-slot helper (capacity 100, auto-prune, ring-allocation, stage-tracking). v4.17: Trailing-C gates Phase-2 behind Phase-1 (no SL move until TriggerPts profit; BUG #6 uses only bars since open).'
---

# MT5 EA 通用交易模块 v4.17

## Overview

This skill packages the v4.17 standard trading-management panels shown in the MT5 EA input dialog — including **three independent trailing-stop modes (A progressive / B one-shot break-even / C pattern-based)**, **independent SL/TP switches**, **adjustable risk-reward ratio**, **same-bar no-reentry guard**, **max-stop-loss limit**, **max concurrent positions**, **3-stage scaling-out**, **end-of-day close-all**, and **consecutive-loss pause** — into a single reusable MQL5 module.

When the user asks to develop any MT5 EA strategy and wants those common panels to be included automatically, generate the common module and an example EA template, then explain how to integrate it.

## Triggering phrases

- "开发一个 MT5 EA"
- "EMA55MA233SuperTrend 共振吞没入场"
- "两套追踪止损都要保留"
- "按形态追踪止损" / "支撑位下方止损" / "形态止损"
- "盈亏比可调" / "盈亏比2:1 / 3:1 / 5:1"
- "同一根K线不能重复开仓" / "刚平仓不允许再开仓"
- "通用交易模块"
- "EA 仓位/止损/风控"
- "v4.17 参数面板"

## Workflow

1. **Confirm requirements**: Verify whether the user wants only the common module, or also a full EA template with strategy-specific entry logic.
2. **Emit core asset**: Copy or customize `MT5_EA_Common_Trading_Module.mqh` to the user's project.
3. **Emit example EA** (optional): Copy `Example_EA_Template.mq5` and replace the placeholder `CheckEntrySignal()` with the user's actual strategy.
4. **Reference parameters**: If the user asks about specific inputs, load `parameters.md`.
5. **Integration instructions**: Tell the user how to `#include` the module, instantiate the class, and wire `OnTick`, `OnTrade`, `OnTimer`, and `OnInit`.

## v4.17 input panel structure

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

### 9. 风控管理
- Daily loss limit: stops trading when losses reach `InpDailyLossPercent` of balance.
- Spread limit: blocks entries when spread exceeds `InpMaxSpreadPoints`.
- Both are checked in `IsTradingAllowed()`.

### 10. 连续亏损暂停
- Counts consecutive losses in `OnTrade()`.
- Pauses new entries for `InpPauseMinutes` after `InpConsecutiveLossCount` consecutive losses.

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
The reusable MQL5 include file. Copy this into the user's `MQL5/Includes/` folder or project directory.

### Example_EA_Template.mq5
A working EA skeleton that demonstrates module integration. Replace `CheckEntrySignal()` with real strategy logic.

### parameters.md
Detailed description of every input parameter, its default value, behavior notes, and a Mode A vs B vs C comparison table.

## Notes

- The module is intentionally generic. It does not contain strategy-specific entry logic; that belongs in the EA file.
- Input defaults are taken from the user's screenshot. If the user asks to change defaults, update the `input` lines in the `.mqh` file and `parameters.md`.
- All prices/stops are normalized to `SYMBOL_DIGITS`.
- The module uses `CTrade` from `<Trade\Trade.mqh>` for order execution.
- v4.17 specifically: when multiple of A/B/C are ticked, the mode with the highest priority (A > B > C) wins and a warning is logged at init. **Trailing-C phase gate**: in non-pattern-only mode, if `profitPoints < InpTrailingCTriggerPts`, the function returns early — SL never moves and Phase-2 pattern trailing never runs until the break-even lock (Phase-1) has fired. BUG #6: Phase-2 support/resistance only from bars since position open (old code included pre-open bars, freezing SL).
- **CRITICAL anti-pattern #1 (TP clearing)**: when modifying SL via `PositionModify(ticket, newSL, ...)`, the third argument **MUST** be the current `POSITION_TP` value, **never** `0`. Passing `0` clears the take-profit.
- **CRITICAL anti-pattern #2 (trailing blocked)**: `g_Common.OnTick()` must be called at the **top** of `OnTick()`, **before** `IsTradingAllowed()` checks. Otherwise break-even/trailing is skipped during off-hours / over-loss / wide-spread periods, leading to catastrophic unprotected profits.
- **CRITICAL anti-pattern #3 (swap eats points)**: trigger trailing on raw Bid/Ask price differential, not on `POSITION_PROFIT / tickValue`. Overnight swap accumulation skews monetary profit and would prevent trailing from ever firing for held positions.
- **CRITICAL anti-pattern #4 (asymmetric needMove)**: both BUY and SELL `needMove` checks **MUST** include an explicit `(currentSL == 0)` forced-move branch. Without it, BUY would silently skip moving when an unmanaged position has no SL yet set.
- **CRITICAL anti-pattern #5 (10-slot trail index)**: persistent trail ticket arrays must have **capacity ≥ 100** (not 10) and **auto-prune closed positions** on every lookup. A "g_trailPersistCount++ only" pattern silently breaks trailing for the 11th and every subsequent position. Use the built-in `FindOrCreateTrailSlot` / `PruneClosedTrailSlots` helpers; never roll your own.
- **Failure logging**: every `PositionModify` goes through `SafeModifyPosition()` which prints `retcode` + context on failure. Search the journal for `PositionModify FAILED` to find all failed modify calls.
- **Skip diagnostic logging**: every trailing mode prints a `[TrailingA.Phase2] SKIP`, `[TrailingB.OneShot] SKIP`, or `[TrailingC.Phase2] SKIP` line when the trigger conditions are met but the SL is already in the target position. Search for `SKIP ticket=` to find silent no-ops that look like dead trailing.
