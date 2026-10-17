# MT5 EA 通用交易模块参数说明 v4.20

本文件记录 `MT5_EA_Common_Trading_Module.mqh` 中所有输入参数的语义与默认值（v4.20 版本：三套追踪 A/B/C + 盈亏比可调 + 同K线禁止重复交易 + 最大止损限制 + 最大同时持仓数(按magic) + 分批止盈模式 + **当日净亏损限制** + **连亏暂停(按持仓归组)** + 最小持仓时间 + 收盘强平；已真机编译验证 0 errors / 0 warnings）。

## 关键设计约束（永久归档）

### 1. 保留 TP 的反模式

**绝对禁止**：追踪止损修改 SL 时把 TP 设为 0。

```cpp
// ❌ 错误写法（会把开仓时的 660 点止盈清零）
m_trade.PositionModify(ticket, newSL, 0);

// ✅ 正确写法：先读取当前 TP，再传回去
double currTP = PositionGetDouble(POSITION_TP);
m_trade.PositionModify(ticket, newSL, currTP);
```

原因：MQL5 的 `PositionModify(ticket, sl, tp)` 中，`tp = 0` 表示"取消止盈"（不是"保留原 TP"）。本 Skill 全部追踪代码（A/B）均已严格使用正确写法。

### 2. 追踪必须早于风控检查

**绝对禁止**：在 `IsTradingAllowed()` 检查通过之前就 `return`，否则保本追踪会被跳过。

```cpp
// ❌ 错误写法（非交易时间/日亏损超标/点差过大时，追踪被跳过）
void OnTick()
{
   if(!g_Common.IsTradingAllowed()) return;   // ← 已持仓的 SL 永远不被追踪
   g_Common.OnTick();
   ...
}

// ✅ 正确写法：追踪在 OnTick 最前面，无条件执行
void OnTick()
{
   g_Common.OnTick();                          // ← 第一件事
   if(!g_Common.IsTradingAllowed()) return;    // ← 第二件事：仅用于控制开仓
   ...
}
```

**灾难场景**：当盈利已达 300 点时，若处于非交易时间，错误写法会导致 SL 永远停在原位。下一次行情回撤 350 点，账户直接被穿仓。

### 3. PositionModify 失败时必须打印日志

`SafeModifyPosition()` 已统一处理：失败时输出 `retcode` + 上下文 + 请求描述，例如：
```
[ApplyTrailingStop.Phase1.BreakEven] PositionModify FAILED ticket=12345 sl=2650.50 tp=2660.00 retcode=10016 (Invalid price) request=...
```
排查时直接搜索 `PositionModify FAILED` 即可定位所有失败调用。

### 4. 用 Bid/Ask 价格差触发，不用 POSITION_PROFIT 反算

**绝对禁止**：用 `POSITION_PROFIT` 反算等效点数来触发追踪。

```cpp
// ❌ 错误写法：POSITION_PROFIT 包含隔夜利息和手续费的"货币盈亏"
//              反算成点数后会被 swap 吃掉，追踪永远触发不到
double profitPoints = PositionGetDouble(POSITION_PROFIT) / tickValue / point;

// ✅ 正确写法：用原始 Bid/Ask 价格差，纯粹的"价格点数"
double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
double profitPoints = (posType == POSITION_TYPE_BUY)
                      ? (currentPrice - openPrice) / point
                      : (openPrice - currentPrice) / point;
```

**根因**：持隔夜仓的 swap 累积会让 POSITION_PROFIT 偏小，对应"等效点数"也偏小，追踪触发条件 `profitPoints >= X` 永远达不到；持短仓则相反（swap 短暂正向时可能提早触发）。改用纯价格差后行为可预测。

### 5. needMove 判定必须包含 (currentSL == 0) 强制分支

**绝对禁止**：BUY 端漏写 `currentSL == 0` 强制分支。

```cpp
// ❌ 错误写法（BUY 漏掉 currentSL==0 分支，与 SELL 行为不对称）
if(posType == POSITION_TYPE_BUY && newSL > currentSL + point)
   needMove = true;
if(posType == POSITION_TYPE_SELL && (currentSL == 0 || newSL < currentSL - point - point))
   needMove = true;

// ✅ 正确写法：BUY / SELL 都补上 (currentSL == 0) 强制分支
if(posType == POSITION_TYPE_BUY)
{
   if(currentSL == 0 || newSL > currentSL + point)
      needMove = true;
}
else // SELL
{
   if(currentSL == 0 || newSL < currentSL - point)
      needMove = true;
}
```

**根因**：当持仓从未设过 SL（`currentSL == 0`）时，若新 SL 恰好落在 `[0, point]` 区间内，BUY 不会触发移动；SELL 因为显式 `|| currentSL == 0` 分支会触发。两侧不对称。统一加强制分支后行为一致。

### 6. 持久化追踪索引：容量 10 不够 + 不会清理已平仓订单

**绝对禁止**：用 `int g_trailTickets[10]; int g_trailPersistCount = 0;` 这样的"只增不减"数组做持久化追踪索引。

```cpp
// ❌ 旧错误代码（容量 10 + 只增不减）
int g_trailTickets[10];
int g_trailPersistCount = 0;

int FindOrCreateTrailIdx(ulong ticket)
{
   if(g_trailPersistCount >= 10) return(-1);  // ← 第 11 单开始永远返回 -1
   ...
}
```

**表现**：
- 前 10 单正常追踪 ✅
- 第 11 单开始 `FindOrCreateTrailIdx` 返回 -1 → 调用方 `continue` → 静默跳过 ❌
- 你以为"有时触发有时不触发"——其实前 10 单稳定触发，第 11 单后**全部失效**

**根因**：
- 数组容量太小（10 → 100+）
- `g_trailPersistCount` 只增不减（`++` 但从不 `--`），已平仓的槽位永远占用
- 失败时调用方 `continue` 不打印任何日志，问题被掩盖

**修复（v4.04）**：本 Skill 提供可复用工具类 `CCommonTradingModule` 内置成员：

```cpp
// Skill 内部已实现
int  TRAIL_SLOT_COUNT = 100;                              // 容量
ulong m_trailTickets[TRAIL_SLOT_COUNT];                   // ticket 存储
bool  m_trailSlotUsed[TRAIL_SLOT_COUNT];                  // 占用标志
int   m_trailNextIdx;                                     // 环形写入指针

int  FindOrCreateTrailSlot(ulong ticket, bool& outCreated);  // 找不到返回 -1
void PruneClosedTrailSlots();                                  // 每次查找前自动清理
```

三件套防回归：
1. **容量 100**（远超常见 EA 的同时持仓数）
2. **PruneClosedTrailSlots** — 每次 `FindOrCreateTrailSlot` 之前先扫一遍 `PositionsTotal()`，已平仓的 ticket 槽位立刻释放
3. **诊断日志** — 触发条件满足但 SL 无需修改时打印：
   ```
   [TrailingA.Phase2] SKIP ticket=12345 profit=320.5pts newSL=2660.00 currentSL=2659.50 (触发条件已满足但 SL 无需前移)
   [TrailingB.OneShot] SKIP ticket=12346 profit=320.0pts targetSL=2660.00 currentSL=2660.00 (已锁死在保护位或更优位置)
   [TrailSlot] 索引已满（容量=100），ticket=12347 跳过追踪
   ```
4. **环形分配** — `m_trailNextIdx` 即使前 100 个全填满也不会停，循环覆盖最旧的（极少触发）

## 1. 交易时间（北京时间）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpServerHourDiff | int | 5 | 服务器时间比北京时间晚的小时数。例如服务器时间=GMT+0，北京=GMT+8，则填 8。截图示例为 5。 |
| InpTradeStartHour | int | 7 | 交易开始小时（北京） |
| InpTradeStartMinute | int | 30 | 交易开始分钟（北京） |
| InpTradeEndHour | int | 3 | 交易结束小时（北京，次日） |
| InpTradeEndMinute | int | 30 | 交易结束分钟（北京，次日） |

模块内部将服务器时间转换为北京时间后判断是否在交易时段。若结束时间早于开始时间，则按跨天处理。

## 2. 仓位管理

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseFixedLot | bool | true | true=固定手数，false=按风险百分比计算手数 |
| InpFixedLot | double | 1.0 | 固定手数大小 |
| InpRiskPercent | double | 1.0 | 风险百分比（占账户余额） |
| InpMinLot | double | 0.01 | 最小手数限制 |
| InpMaxLot | double | 10.0 | 最大手数限制 |

按风险百分比计算时，公式为：
`lots = 风险金额 / (止损点数 × SYMBOL_TRADE_TICK_VALUE / SYMBOL_TRADE_TICK_SIZE)`
结果会按 `SYMBOL_VOLUME_STEP` 对齐并限制在最小/最大手数之间。

## 3. 止损止盈开关

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseFixedStopLoss | bool | true | 启用固定止损（关闭后开仓不设固定 SL，由追踪模式或人工管理） |
| InpUseFixedTakeProfit | bool | true | 启用固定止盈（关闭后开仓不设固定 TP） |

## 4. 止损与追踪（共用基础参数）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpFixedSLPoints | int | 300 | 固定止损点数（共用基础 SL） |
| InpFixedTPPoints | int | 660 | 固定止盈点数（共用基础 TP） |

这两个参数被两套追踪止损共用。追踪方式 A/B 启动后，会按各自规则覆盖 SL。

## 5. 追踪方式 A：渐进式（持续追踪 SL，二选一）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseTrailingA | bool | false | 启用追踪 A（与 B 互斥）。勾选即用 A。 |
| InpTrailingAActivatePts | int | 20 | A：追踪激活利润点数（达到后开始持续追踪 SL） |
| InpTrailingABreakEvenPts | int | 320 | A：保本点数（达到后将 SL 移到入场价） |

**追踪 A 的行为：**
- 利润 ≥ `InpTrailingABreakEvenPts`（320 点）：将 SL 移至入场价 ± 2 点（保本），然后本 tick 不再移动。
- 利润 ≥ `InpTrailingAActivatePts`（20 点）且 < 320 点：每 tick 将 SL 紧贴当前价 ± 1 点。
- 利润 < 20 点：保持固定 SL/TP 不动。

## 6. 追踪方式 B：一次性保本（触发后锁死，二选一）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseTrailingB | bool | false | 启用追踪 B（与 A 互斥）。勾选即用 B。 |
| InpTrailingBTriggerPts | int | 320 | B：触发保本的利润点数（达到后触发一次性保本） |
| InpTrailingBProtectPts | int | 20 | B：保护利润（SL 移至开仓价 ± 此点数） |

**追踪 B 的行为：**
- 利润 ≥ `InpTrailingBTriggerPts`（320 点）：将 SL 一次性移至开仓价 ± `InpTrailingBProtectPts`（20 点）的位置。**触发后锁死**，即使价格继续朝有利方向移动也不再调整 SL。
- 利润 < 320 点：保持固定 SL/TP 不动。

## 7. 追踪方式 C：形态追踪（支撑/压力摆动位，二选一）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseTrailingC | bool | false | 启用追踪 C（与 A/B 互斥）。勾选即用 C。 |
| InpTrailingCUsePatternOnly | bool | false | true=跳过"300点触发"阶段，直接独立使用形态追踪 |
| InpTrailingCTriggerPts | int | 300 | C：触发激活的利润点数（SL 移到保本+保护点） |
| InpTrailingCProtectPts | int | 55 | C：激活后 SL 移到开仓价 ± 此保护利润点数 |
| InpTrailingCSLBufferPts | int | 20 | C：形态追踪 SL 距支撑/压力位缓冲（点） |
| InpTrailingCPatternTF | ENUM_TIMEFRAMES | PERIOD_M1 | C：形态识别周期（摆动点检测用） |

**追踪 C 的行为（默认，非 pattern-only，金刚经 v1.2x 原版逻辑）：**
1. 入场后 SL/TP 已固定（默认盈亏比 2:1：SL 300 点 / TP 660 点）
2. **阶段 1（门控）**：**利润 < `InpTrailingCTriggerPts`（300 点）→ SL 完全不移动**（直接 return，不进入阶段 2/3）
3. **阶段 2（保本锁利）**：利润 ≥ 300 点 → SL 移到开仓价 ± `InpTrailingCProtectPts`（+55 点）的位置 → 保证盈利单不会变亏损
4. **阶段 3（形态追踪）**：之后按形态移动：
   - **摆动点检测**：`strength=2`（左右各 2 根 K 线确认极值），从当前往回扫描最近 60 根 K 线，找最近的摆动低点（BUY）/ 摆动高点（SELL）
   - BUY → `patternSL = 摆动低点 - InpTrailingCSLBufferPts`（20 点），若比保本锁 targetSL 更有利则采用
   - SELL → `patternSL = 摆动高点 + InpTrailingCSLBufferPts`（20 点），若比保本锁 targetSL 更有利则采用
   - 仅当新 SL 比当前 SL 更优（BUY 更高 / SELL 更低）时才移动
   - 未找到摆动位时退化为保本锁 targetSL（数据不足容错）

**追踪 C 的行为（pattern-only 模式）：**
- `InpTrailingCUsePatternOnly = true` 时跳过阶段 1/2，直接按阶段 3 形态追踪 —— 即"**单独使用形态止损**"，无需先走出固定利润。

**说明**：v4.18 起完全采用金刚经策略的追踪 C 模块（摆动点检测替代旧版极值法），参数对齐金刚经（`InpTrailingCSLBufferPts` / `InpTrailingCPatternTF`）。

**追踪 C 的行为（pattern-only 模式）：**
- `InpTrailingCUsePatternOnly = true` 时跳过阶段 1，直接按阶段 2 形态追踪 —— 即"**单独使用形态止损**"，无需先走出固定利润。

## 8. 风控管理

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseDailyLossLimit | bool | true | 是否启用当日最大亏损限制 |
| InpDailyLossPercent | double | 5.0 | 当日最大亏损占**当日起始余额**百分比 |
| InpUseSpreadLimit | bool | true | 是否启用点差限制 |
| InpMaxSpreadPoints | int | 50 | 最大允许点差（点） |

**v4.20 口径修正 — 当日亏损现在是"净亏损"：**

```
当日已实现净盈亏 = Σ(DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION)   ← 盈利为正，亏损为负
净亏损 m_dailyLoss = max(0, -当日已实现净盈亏)
触发条件           = 净亏损 ≥ 当日起始余额 × InpDailyLossPercent / 100
```

| 当日交易 | 旧实现（毛亏累加） | v4.20（净额） |
|---|---|---|
| +800 与 −300 并存 | 计为亏 300 → 可能误触发 | 净 +500 → 不触发 ✅ |
| −100 / −100 / −100（余额 10000，5%=500） | 亏 300 → 不触发 | 净 −300 → 不触发 ✅ |
| −300 / −300（余额 10000，5%=500） | 亏 600 → 触发 | 净 −600 → 触发 ✅ |
| EA 盘中重启 | `m_dailyLoss` 归零 → **当日亏 5% 后又开始交易** | 从历史重算，仍拦住 ✅ |

其它要点：
- **统计范围**：账户级 —— 含本 EA、其他 EA、手动单（即"当日所有交易之和"）。
- **阈值分母**：固定为当日起始余额 `m_dayStartBalance = 当前余额 − 当日已实现净盈亏`，不随亏损扩大而缩小。
- **重建时机**：`RefreshDayStats()` 节流 2 秒；`IsTradingAllowed()` / `OnTrade()` / `OnTimer()` 均可触发，**不依赖 EA 是否接了 `OnTrade()`**。
- 拦截日志（60 秒节流）：
  ```
  CommonModule: 拒绝开仓 — 当日净亏损 520.00 已达上限 500.00（起始余额 10000.00 × 5.0%）
  ```

## 8.5 风控: 最大止损限制（止损过大不开仓）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseMaxSLPoints | bool | true | 启用最大止损限制（止损点数超过上限则拒绝开仓） |
| InpMaxSLPoints | int | 1500 | 最大允许止损点数（默认 1500 点 ≈ 15 美金） |

**行为：**
- 在 `OpenPosition()` 中检查：若 `InpUseMaxSLPoints=true` 且 `slPoints > InpMaxSLPoints`，则直接拒绝开仓并打印：
  ```
  CommonModule: 拒绝开仓 — 止损过大 (X 点 > 上限 Y 点)
  ```
- 与"风控管理"组互补：风控管理管综合维度（时间/日亏损/点差/暂停），最大止损限制管单笔风险敞口上限。
- 关闭后不限制 SL 大小（不推荐，止损过大会导致单笔风险失控）。

## 9. 连续亏损暂停

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseConsecutiveLossPause | bool | **false** | 是否启用连续亏损暂停（**必须手动勾选**） |
| InpConsecutiveLossCount | int | 3 | 连续亏损 N 次后触发暂停 |
| InpPauseMinutes | int | 90 | 暂停时间（分钟） |

**v4.20 语义：按"一次交易"判盈亏，而不是按"一笔 deal"**

一次交易若分批平仓（1×SL 平 1/3、2×SL 平 50%、3×SL 平剩余），会产生多条 `DEAL_ENTRY_OUT`：

| 三档平仓明细 | 旧实现（按 deal） | v4.20（按 `DEAL_POSITION_ID` 归组） |
|---|---|---|
| +200 / +400 / −900 | +200 命中 `else` → 连亏计数 **清零** | 净 −300 → **计 1 笔亏损** ✅ |

这正是"连亏 3 笔后没有暂停"的根因：盈利档位把亏损抵消掉了。

**其它要点：**
- **只统计本 EA**：按 `DEAL_MAGIC == magic` 过滤；其他 EA / 手动单的盈利不会打断本 EA 的连亏。
- **暂停状态持久化**：`GlobalVariable` `CTM_PAUSE_<magic>`（到期时间）、`CTM_LOSSRESET_<magic>`（连亏统计起点）。EA 重启 / 改参数 / 重编译后暂停不丢失，也不会把已翻篇的旧连亏重算一遍。
- **暂停到期后**：连亏统计起点重置为"此刻"，只统计之后的交易，不会一到期就立刻再次触发。
- **触发/到期日志**：
  ```
  CommonModule: 连续亏损暂停 已启用（连亏 3 笔 → 暂停 90 分钟）
  CommonModule: 【连续亏损暂停】已连亏 3 笔（阈值 3）→ 暂停 90 分钟，至 2026.10.17 13:05 前禁止开新仓
  CommonModule: 【连续亏损暂停】已到期 — 恢复交易，连亏计数从此刻重新计算
  ```
- 若日志里出现 `连续亏损暂停 *** 未启用 ***`，说明面板里没勾选 —— 这是最常见的"不生效"原因。

## 10. 盈亏比设置（可调）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseRiskRewardRatio | bool | true | 启用盈亏比自动算止盈（TP 点数 = SL 点数 × 盈亏比） |
| InpRiskRewardRatio | double | 2.0 | 盈亏比（2:1=2.0 / 3:1=3.0 / 5:1=5.0） |

**行为：**
- 开启后，`OpenPosition()` 和 `ApplyStopLossTakeProfit()` 中 **TP 点数 = SL 点数 × 盈亏比**（自动取整）。
  - 例：SL 300 点 + 盈亏比 2:1 → TP 600 点；3:1 → 900 点；5:1 → 1500 点。
- 关闭后，使用 `InpFixedTPPoints`（660）固定止盈点数。
- 盈亏比小于 0.1 时回退到 2.0（防呆）。

## 10.5 最大同时持仓数

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpMaxPositions | int | 2 | 最大同时持仓数（2=分批止盈平仓部分后可开新仓） |
| InpScalingOutRR | double | 3.0 | 盈亏比（TP/SL 倍数）：2:1, 3:1, 3.2:1, 5:1 等 |

**行为（v4.18 修正，金刚经 v1.20 修复）：**
- `OpenPosition()` 中调用 `CountPositionsByMagic()` —— **只统计本 EA（magic 号）的持仓**，排除其他 EA / 手动单 / 其他品种。
- **核心公式（金刚经 v1.20 修复 1：去掉 InpUseTieredTP 依赖）**：
  ```cpp
  int effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1;
  if(CountPositionsByMagic() >= effectiveMaxPos) 拒绝;
  ```
- **金刚经 v1.20 修复 2：开仓成功后立即清零** `m_anyTier1Triggered = false`（每个新仓位必须独立证明自己走出 1× 利润，才能允许下一仓；不能共享上一仓的"已触发"状态）。
- **双重保护门语义**：
  - `m_anyTier1Triggered=true` → `effectiveMaxPos = InpMaxPositions`（默认 2，允许双仓）
  - `m_anyTier1Triggered=false` → `effectiveMaxPos = 1` → **严格单仓**
  - 状态在 `ApplyScalingOut` 第 1 档触发时置 true；在 `OpenPosition` 成功时立即清零
- 已满则拒绝并打印：
  ```
  CommonModule: 拒绝开仓 — 已达最大持仓 (CountPositions=N effectiveMaxPos=M InpMaxPositions=X Tier1Triggered=true/false)
  ```
- `m_anyTier1Triggered` 状态维护：
  - EA 重启时 Init 中扫描追踪槽位，只要任何仓位 `m_trailStage >= 1` 即置 true（恢复历史状态）
  - 第 1 档分批止盈成功时（`ApplyScalingOut`）置 true
  - **每次开仓成功后立即清零**（v4.18 关键）
- **关键语义**：分批止盈平掉部分仓位后，该仓位 **ticket 不变、仍是 1 个持仓**，所以**仍占 1 个名额**，直到**完全平仓**才释放名额。
- 示例（上限=2）：
  - 第 1 仓开仓成功 → `m_anyTier1Triggered=false` → effectiveMaxPos=1（严格单仓）
  - 第 1 仓走出 1× 利润 → 第 1 档平 1/3 → `m_anyTier1Triggered=true` → effectiveMaxPos=2
  - 出现符合规则的新信号 → **可开第 2 仓**
  - 第 2 仓开仓成功 → `m_anyTier1Triggered=false` → effectiveMaxPos=1（再次严格单仓）
  - 第 3 仓必须等第 2 仓自己走出 1× 利润（独立证明）
- `InpMaxPositions <= 0` 时不限制。

## 10.6 分批止盈（独立开关，每档比例可调）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseScalingOut | bool | true | 启用分批止盈（利润达 1/2/3 倍止损空间分批平仓） |
| InpScalingOutTrig1 | double | 1.0 | 第1档触发：利润达此倍止损空间 |
| InpScalingOutRatio1 | double | 0.33 | 第1档平仓比例（占总仓位）：0.25=1/4, 0.33=1/3, 0.50=1/2 |
| InpScalingOutTrig2 | double | 2.0 | 第2档触发：利润达此倍止损空间 |
| InpScalingOutRatio2 | double | 0.5 | 第2档平仓比例（占剩余仓位） |
| InpScalingOutTrig3 | double | 3.0 | 第3档触发：利润达此倍止损空间 |
| InpScalingOutRatio3 | double | 1.0 | 第3档平仓比例（剩余全部，默认 1.0） |

**行为（金刚经 v1.16 模式）：**
- 模块内部用 `m_trailStage[100]` 追踪每张已分批止盈的档位（0/1/2/3）。
- 第 N 档触发条件：`profitPoints >= InpScalingOutTrigN × 止损空间点数`
- 第 N 档平仓量：`剩余仓位 × InpScalingOutRatioN`（向下对齐到 volume step）
  - 第 1 档占总仓位，第 2/3 档占剩余仓位
- 默认 1×SL → 平 33%、2×SL → 平剩余 50%、3×SL → 平剩余全部（默认 1.0）
- 第 3 档平掉全部后 `m_trailStage=3`，不再处理
- 与追踪 A/B/C 互补：分批止盈按利润分批，追踪 A/B/C 仍按规则调整 SL

**典型计算示例**（SL 300 点、开仓 1.0 手）：
- 利润达 300 点（1×SL）：平 `1.0 × 0.33 = 0.33` 手，剩余 0.67 手
- 利润达 600 点（2×SL）：平 `0.67 × 0.50 = 0.335` 手，剩余 0.335 手
- 利润达 900 点（3×SL）：平 `0.335 × 1.00 = 0.335` 手，全平

## 11. 同K线禁止重复交易

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpSameBarNoReopen | bool | true | 同一根 K 线已开过仓（无论是否平仓）则禁止再次开仓 |
| InpSameBarNoAfterClose | bool | true | 同一根 K 线刚平仓，则决不允许再开仓入场交易 |

**行为（v4.18 修正，金刚经 v1.21 双修复）：**
- 模块内部记录 `m_lastOpenBarTime`（最近开仓所在 K 线）和 `m_lastCloseBarTime`（最近平仓所在 K 线）。
- `OpenPosition()` 开头检查：当前 K 线与 `m_lastOpenBarTime` 相同 → 拒绝开仓；当前 K 线与 `m_lastCloseBarTime` 相同 → 拒绝开仓。
- 开仓成功后在当前 K 线内**永不再开**（直到下一根 K 线）。
- **v1.21 修复 1（30 秒过滤）**：`OnTrade()` 中**只认 30 秒内真实发生的本 EA 平仓**才记录冷却：
  ```cpp
  bool isRecent = (dealTime > 0 && (TimeCurrent() - dealTime) <= 30);
  if(isRecent && dealMagic == m_magic && dealEntry == DEAL_ENTRY_OUT)
  ```
  - EA 加载时历史平仓单（几天前）`isRecent=false` → 不记录冷却
  - 其他 EA / 手动单平仓 `dealMagic != m_magic` → 不记录冷却
- **v1.21 修复 2（记录当前 K 线）**：`m_lastCloseBarTime = iTime(_Symbol, PERIOD_CURRENT, 0)`——记录当前K线时间（bar0）
  - 旧逻辑用 `iTime(..., 1)`（已收盘K线）→ 冷却少 1 根 K 线
  - 新逻辑：bar0 变 bar1 后 sigBarTime（新 bar0） != m_lastCloseBarTime → **正确解除冷却**，严格只冷却 1 根 K 线
- 两个开关都关闭时不做任何限制（恒放行）。
- 被拒绝时会打印日志，方便排查：
  ```
  CommonModule: 拒绝开仓 — 同一根K线已交易过（lastOpen=... lastClose=... 当前bar=...）
  ```

## 12. 收盘强平 + 禁开仓（不持仓过夜）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseEndCloseAll | bool | true | 总开关（false 时全部失效） |
| InpCloseAllMinsBeforeEnd | int | 2 | 强平提前量：距交易结束 ≤ N 分钟强平所有本 EA 持仓，不论盈亏 |
| InpNoEntryMinsBeforeEnd | int | 30 | 禁开仓提前量：距交易结束 ≤ N 分钟禁止开新仓 |

**行为（v4.18，金刚经 v2.04 模式）：**
- 收盘强平：`ManageAllPositions()` 开头调用 `CloseAllBeforeEndOfTrading()`，遍历所有本 EA 持仓逐一 `PositionClose`，不论盈亏：
  ```
  [EndCloseAll] OK ticket=X profit=Y (距结束=N分钟)
  ```
- 禁开仓：`OpenPosition()` 开头检查 `MinutesToEndOfTrading()`（处理跨日：服务器时间 + InpServerHourDiff 转北京时间），距结束 ≤ 阈值则拒绝：
  ```
  CommonModule: 拒绝开仓 — 距交易结束仅 N 分钟（≤ 禁开仓阈值 M 分钟）
  ```
- **跨日场景**：交易时段为 7:30 ~ 次日 3:30 时也能正确计算（次日 2:00 时返回 90 分钟）
- `InpUseEndCloseAll=false` 时两个阈值都失效，行为退化为"允许持仓过夜"

## 13. 最小持仓时间（仅延迟启用追踪止损）

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| InpUseMinHoldTime | bool | true | 启用最小持仓时间保护 |
| InpMinHoldMinutes | int | 20 | 最小持仓分钟数：未满此时长不启用追踪 |

**行为（v4.18，参照金刚经 v2.06）：**
- **语义**：SL/TP 始终由经纪商端正常触发，本保护**只拦截"移动 SL"这一动作**。
- 持仓未满 `InpMinHoldMinutes` 分钟时，追踪 A/B/C 完全不动作（`ManageAllPositions()` 中 `continue`）。
- 若期间价格打掉 SL 或 TP，属正常平仓，本保护**不干预**。
- **不受拦截的模块**：分批止盈（`ApplyScalingOut`）、收盘强平（`CloseAllBeforeEndOfTrading`）、服务端 SL/TP。
- 实现：
  ```cpp
  bool IsMinHoldTimeSatisfied(ulong ticket);   // 已持仓分钟数 >= InpMinHoldMinutes
  int  GetHeldMinutes(ulong ticket);           // (TimeCurrent() - POSITION_TIME) / 60
  ```
- 拦截日志 60 秒节流，避免每 tick 刷屏：
  ```
  [MinHoldTime] BLOCK Trailing ticket=X 已持仓=N分钟 < 要求=M分钟 (继续持仓)
  ```
- 公开 API 供 EA 自有平仓逻辑复用：`CheckMinHoldTime(ticket)` / `GetHeldMinutes(ticket)`
- `InpUseMinHoldTime=false` 或 `InpMinHoldMinutes<=0` → 恒放行（防呆）

## 三套追踪止损的对比

| 特性 | 追踪 A（渐进式） | 追踪 B（一次性保本） | 追踪 C（形态追踪） |
|---|---|---|---|
| 触发后是否持续移动 SL | 是（每 tick 紧贴） | 否（触发后锁死） | 是（按形态移动） |
| SL 位置依据 | 当前价 ± 1 点 | 开仓价 ± 保护点数 | 支撑/压力位 ± 偏移点数 |
| 适合市场 | 强趋势行情 | 区间震荡行情 | 有明确支撑/压力结构的行情 |
| 最大利润保护 | 持续提升 | 固定 ± 20 点 | 跟随形态结构 |
| 特殊能力 | — | — | 可跳过触发阶段独立使用 |

## 互斥逻辑

- A / B / C 三套追踪**始终都保留在参数面板上**，使用时**三选一勾选**。
- 若同时勾选了多个，模块在 `Init()` 中统计数量并打印警告，按 **优先级 A > B > C** 处理。
- `IsTrailingAEnabled()` / `IsTrailingBEnabled()` / `IsTrailingCEnabled()` 已实现互斥逻辑。

## 止损止盈开关与追踪模式的关系

- `InpUseFixedStopLoss = false` + 不启用追踪 A/B/C → 开仓时不设固定 SL，由人工/EA 外部管理。
- `InpUseFixedStopLoss = false` + 启用追踪 A/B/C → 开仓时不设固定 SL，但追踪模式仍会在达到条件时自动设置 SL（追踪独立运行）。
- `InpUseFixedStopLoss = true` + 不启用追踪 A/B/C → 开仓时直接设固定 SL/TP（标准行为）。
- `InpUseFixedStopLoss = true` + 启用追踪 A/B/C → 开仓时设固定 SL/TP，达到追踪条件后由追踪模式接管 SL（TP 保持不变）。

## 使用建议

1. **强趋势策略** → 启用追踪 A：让利润奔跑、SL 持续跟随。
2. **震荡或剥头皮策略** → 启用追踪 B：触发保本后即锁定，避免回吐。
3. **形态/支撑压力策略** → 启用追踪 C：先 300 点保本锁 +55，再按支撑/压力位移动 SL。
4. **只想用形态止损** → 启用追踪 C + `InpTrailingCUsePatternOnly=true`：跳过触发阶段，直接按形态移动。
5. **不使用追踪** → 三套都不勾选，则按 `InpFixedSLPoints` / `InpFixedTPPoints` 固定 SL/TP 即可。
6. 在已有持仓时，`ManageAllPositions()` 会自动为未设置 SL/TP 的订单补设止损止盈、执行对应的追踪模式。

## 14. 编译期常量与 EA 侧集成约定（v4.18）

### 14.1 容量常量 `TRAIL_SLOT_COUNT`

模块顶部的 `TRAIL_SLOT_COUNT` 定义**追踪槽位容量**（默认 100），必须以 `#define` 宏形式存在：

```cpp
#ifndef TRAIL_SLOT_COUNT
#define TRAIL_SLOT_COUNT 100
#endif
```

**为什么不能用类内 `static const int`**：MQL5 中类内的 `static const` 成员**不是编译期常量**，不能用作数组成员的数组维度，会报：

```
error: constant expression required
```

**与调用方 EA 的兼容**：`#ifndef` 保护意味着——

| EA 侧写法 | 结果 |
|---|---|
| EA 未定义该宏 | 模块使用默认 100 ✅ |
| EA 在 `#include` **之前** `#define TRAIL_SLOT_COUNT 100` | 复用 EA 的定义，不冲突 ✅ |
| EA 在 `#include` **之后** 再 `#define TRAIL_SLOT_COUNT 100` | 报 macro redefinition 警告 ⚠️（删掉 EA 侧那行即可） |

> 建议：EA 侧**不要再定义** `TRAIL_SLOT_COUNT`，直接由模块提供。

### 14.2 EA 侧自有分批止盈的联动（重要）

模块的「最大持仓双重保护门」依赖状态位 `m_anyTier1Triggered`：

```cpp
int effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1;
```

该状态位**只在模块内部的 `ApplyScalingOut()` 第 1 档触发成功时置位**。因此：

| 场景 | 是否需要联动 |
|---|---|
| 使用模块内的分批止盈（`InpUseScalingOut=true`） | 无需处理，模块自动置位 ✅ |
| **EA 侧自行实现分批止盈**（关闭 `InpUseScalingOut`） | **必须**在 EA 侧第 1 档平仓成功后调用 `g_Common.NotifyTier1Triggered()` ⚠️ |

不调用的话，`m_anyTier1Triggered` 恒为 `false` → `effectiveMaxPos` 恒为 `1` → **永远开不出第 2 仓**。

```cpp
// EA 侧自有分批止盈示例
if(profitReachedTier1 && ClosePartial(ticket, thirdOfVolume))
{
   g_Common.NotifyTier1Triggered();   // v4.18：解锁双仓保护门
}
```

配套查询接口：

```cpp
bool triggered = g_Common.IsTier1Triggered();
```

> 语义提醒：`OpenPosition()` 成功后会**立即清零** `m_anyTier1Triggered`（金刚经 v1.20 逻辑），
> 即**每个新仓位必须独立走出 1× 利润**才能再允许下一仓，不能沿用上一仓的状态。

### 14.3 `m_trailStage[]` 的职责

`m_trailStage[TRAIL_SLOT_COUNT]` 记录**每个 ticket 的分批止盈档位**（0=未触发 / 1·2·3=已触发档数）：

- 由 `FindOrCreateTrailSlot()` 按 ticket 分配槽位
- `ApplyScalingOut()` 读取档位决定本档的触发倍数与平仓比例，平仓成功后写入下一档
- **每张仓位独立计档**——第 2 仓有自己的 `m_trailStage`，不受第 1 仓进度影响
- EA 重启时按现有持仓的档位重建 `m_anyTier1Triggered`

### 14.4 部署位置：F5 调试的前置条件（v4.19 新增）

参数调不出效果的常见原因不是参数写错，而是**EA 根本没被调试器加载**。

MetaEditor 的调试（F5）由 `metatester64.exe` 完成，它**只会在 MT5 终端自己的数据目录里定位 EA**：

```
<终端数据目录>\MQL5\Experts\<EA名称>.mq5
```

| 源码位置 | F7 编译 | F5 调试 |
|---|---|---|
| `<终端数据目录>\MQL5\Experts\` | ✅ | ✅ |
| 外部项目目录（`F:\...\EA系列\` 等） | ✅ | ❌ **静默失败** |

> 部署位置与 `#include` 写法必须匹配：
> - `.mqh` 放 `MQL5\Include\`（**单数**，MT5 无 `Includes` 目录）→ EA 内用 `#include <...>`
> - `.mqh` 与 `.mq5` 同目录 → EA 内用 `#include "..."`

一键部署与核查：

```bash
python scripts/deploy_to_terminal.py --expert <EA.mq5> --include <模块.mqh> --terminal all
python scripts/deploy_to_terminal.py --check-log <EA名称> --terminal all
```

完整说明见 `references/deployment.md`。

### 14.5 CTrade API 陷阱（v4.20 真机编译暴露）

模块曾长期只做静态自检、从未真机编译，因此藏了 3 个编译错误（v4.20 已修）：

| 错误用法 | 编译器报错 | 正确写法 |
|---|---|---|
| `m_trade.SetComment("xxx")` | `error 256: undeclared identifier 'SetComment'` | `CTrade` **没有** `SetComment()`；注释走 `PositionOpen(..., comment)` 参数 |
| `m_trade.ResultRequestDescription()` | `error 256: undeclared identifier 'ResultRequestDescription'` | 用 `m_trade.ResultComment()` |
| 注释边框行漏写 `//` | `error 175: expressions are not allowed on a global scope` | 补回 `//+---...+` |

**EA 侧注意**：若你的单文件 EA 里还留着 `m_trade.SetComment(...)`，编译会失败——需改为把注释作为 `PositionOpen()` 第 7 个参数传入。

### 14.6 风控统计 API（v4.20 新增/变更）

```cpp
double GetDailyLoss()        // 当日净亏损额（正值；净盈利时为 0）
double GetDailyNet()         // 当日已实现净盈亏（有符号，盈利为正）  ← v4.20 新增
double GetDayStartBalance()  // 当日起始余额（阈值分母）              ← v4.20 新增
int    GetConsecutiveLoss()  // 当前连续亏损笔数（按持仓归组、按 magic 过滤）
datetime GetPauseUntil()     // 暂停到期时间（0 = 未在暂停中）
bool   IsPaused()            // 当前是否处于连亏暂停                 ← v4.20 新增
```

**接线要求（重要）**：
- `g_Common.IsTradingAllowed()` 或 `g_Common.OpenPosition()` **必须被调用**——风控统计在 `OpenPosition()` 里校验，每次开仓都会重算。
- `g_Common.OnTrade()` 与 `g_Common.OnTimer()` 是"加速触发"通道，**不再是唯一通路**；即使 EA 没接 `OnTrade()`，只要走 `OpenPosition()` 开仓，连亏暂停与日亏损限制都会生效。

