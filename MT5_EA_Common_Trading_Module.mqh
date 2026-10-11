//+------------------------------------------------------------------+
//|  MT5 EA 通用交易模块 v4.17                                        |
//|  功能：交易时间、仓位管理、止损与追踪(三模式)、风控、连续亏损暂停   |
//|  用法：#include <MT5_EA_Common_Trading_Module.mqh>               |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  v4.14 修复: 追踪C阶段2支撑/压力取"开仓后到当前"K线               |
//|  (旧版取最近N根包含开仓前K线, 支撑/压力被旧K线拉死, SL不跟随)      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  v4.15 修复: 追踪C阶段门控——利润 < InpTrailingCTriggerPts 时       |
//|  SL 完全不移动、不进入阶段2 (旧版利润<300也会进阶段2形态追踪,       |
//|  若开仓后支撑位在开仓价上方, SL 会被提前上移)                       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  v4.16 变更: 追踪C 采用金刚经原版模块（摆动点检测）                  |
//|  v4.17 新增: 最小持仓时间（参照金刚经 v2.06）——                    |
//|  持仓未满 N 分钟时追踪(A/B/C)不动作, SL/TP 始终正常触发              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  重要约定：所有追踪止损修改 SL 时必须保留 TP                          |
//|  - 错误写法：PositionModify(ticket, newSL, 0)   ← 这会把 TP 改成 0    |
//|  - 正确写法：PositionModify(ticket, newSL, currentTP)              |
//|  - 原因：MQL5 PositionModify 第三个参数 0 表示"取消止盈"             |
//+------------------------------------------------------------------+
#ifndef C_COMMON_TRADING_MODULE_MQH
#define C_COMMON_TRADING_MODULE_MQH

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| 输入参数：交易时间（北京时间）                                     |
//+------------------------------------------------------------------+
input group "=== 交易时间(北京时间) ==="
input int    InpServerHourDiff     = 5;      // 服务器比北京晚N小时(MT5=5)
input int    InpTradeStartHour     = 7;      // 交易开始 时(北京)
input int    InpTradeStartMinute   = 30;     // 交易开始 分(北京)
input int    InpTradeEndHour       = 3;      // 交易结束 时(北京次日)
input int    InpTradeEndMinute     = 30;     // 交易结束 分(北京次日)

//+------------------------------------------------------------------+
//| 输入参数：仓位管理                                                 |
//+------------------------------------------------------------------+
input group "=== 仓位管理 ==="
input bool   InpUseFixedLot        = true;   // true=固定手数 false=百分比
input double InpFixedLot           = 1.0;    // 固定手数
input double InpRiskPercent        = 1.0;    // 风险百分比(%)
input double InpMinLot             = 0.01;   // 最小手数
input double InpMaxLot             = 10.0;   // 最大手数

//+------------------------------------------------------------------+
//| 输入参数：止损止盈开关                                              |
//+------------------------------------------------------------------+
input group "=== 止损止盈开关 ==="
input bool   InpUseFixedStopLoss   = true;   // 启用固定止损
input bool   InpUseFixedTakeProfit = true;   // 启用固定止盈

//+------------------------------------------------------------------+
//| 输入参数：止损与追踪（共用基础参数）                                |
//+------------------------------------------------------------------+
input group "=== 止损与追踪(共用基础参数) ==="
input int    InpFixedSLPoints      = 300;    // 固定止损点数
input int    InpFixedTPPoints      = 660;    // 固定止盈点数

//+------------------------------------------------------------------+
//| 输入参数：追踪方式 A：渐进式（持续追踪SL, 二选一）                  |
//+------------------------------------------------------------------+
input group "=== 追踪方式A: 渐进式(持续追踪SL,二选一) ==="
input bool   InpUseTrailingA       = false;  // 启用追踪A(与B互斥)  ← 勾选即用A
input int    InpTrailingAActivatePts = 20;   // A: 追踪激活利润点数
input int    InpTrailingABreakEvenPts = 320; // A: 保本点数(SL移入场价)

//+------------------------------------------------------------------+
//| 输入参数：追踪方式 B：一次性保本（触发后锁死, 二选一）              |
//+------------------------------------------------------------------+
input group "=== 追踪方式B: 一次性保本(触发后锁死,二选一) ==="
input bool   InpUseTrailingB       = false;  // 启用追踪B(与A互斥)  ← 勾选即用B
input int    InpTrailingBTriggerPts  = 320;  // B: 触发保本的利润点数
input int    InpTrailingBProtectPts  = 20;   // B: 保护利润(SL移开仓土此点数)

//+------------------------------------------------------------------+
//| 输入参数：追踪方式 C：形态追踪（支撑/压力摆动位, 二选一）           |
//| - 入场后 SL/TP 已固定（默认盈亏比 2:1，SL300/TP660）                |
//| - 阶段1: 利润 < InpTrailingCTriggerPts 点 → SL 完全不移动           |
//| - 阶段2: 利润 ≥ InpTrailingCTriggerPts → SL 移到开仓±保护利润       |
//| - 阶段3: 之后按形态移动：多头放最近摆动低点下方、                    |
//|   空头放最近摆动高点上方 InpTrailingCSLBufferPts 缓冲点处            |
//| - InpTrailingCUsePatternOnly=true 时跳过阶段1/2触发，                |
//|   直接独立使用形态追踪（无需先走出固定利润）                         |
//+------------------------------------------------------------------+
input group "=== 追踪方式C: 形态追踪(支撑/压力,二选一) ==="
input bool   InpUseTrailingC          = false; // 启用追踪C(与A/B互斥) ← 勾选即用C
input bool   InpTrailingCUsePatternOnly = false; // C: true=跳过触发阶段直接形态追踪
input int    InpTrailingCTriggerPts    = 300;   // C: 触发激活的利润点数(SL移到保本+保护点)
input int    InpTrailingCProtectPts    = 55;    // C: 激活后SL移到开仓±此保护利润点数
input int    InpTrailingCSLBufferPts   = 20;    // C: 形态追踪SL距支撑/压力位缓冲(点)
input ENUM_TIMEFRAMES InpTrailingCPatternTF = PERIOD_M1; // C: 形态识别周期(摆动点检测)

//+------------------------------------------------------------------+
//| 输入参数：风控管理                                                 |
//+------------------------------------------------------------------+
input group "=== 风控管理 ==="
input bool   InpUseDailyLossLimit  = true;   // 启用当日最大亏损限制
input double InpDailyLossPercent   = 5.0;    // 当日最大亏损(%)
input bool   InpUseSpreadLimit     = true;   // 启用点差限制
input int    InpMaxSpreadPoints    = 50;     // 最大允许点差

//+------------------------------------------------------------------+
//| 输入参数：风控: 最大止损限制（止损过大不开仓）                      |
//+------------------------------------------------------------------+
input group "=== 风控: 最大止损限制 ==="
input bool   InpUseMaxSLPoints     = true;   // 启用最大止损限制(止损过大不开仓)
input int    InpMaxSLPoints        = 1500;   // 最大允许止损点数(默认1500点=15美金)

//+------------------------------------------------------------------+
//| 输入参数：连续亏损暂停                                             |
//+------------------------------------------------------------------+
input group "=== 连续亏损暂停 ==="
input bool   InpUseConsecutiveLossPause = false; // 启用连续亏损暂停
input int    InpConsecutiveLossCount  = 3;     // 连续亏损N次后暂停
input int    InpPauseMinutes        = 90;     // 暂停时间(分钟)

//+------------------------------------------------------------------+
//| 输入参数：盈亏比设置（可调）                                        |
//| - 开启后 TP 点数 = SL 点数 × 盈亏比（如 2:1 / 3:1 / 5:1）           |
//| - 若关闭，则使用 InpFixedTPPoints 固定止盈点数                      |
//+------------------------------------------------------------------+
input group "=== 盈亏比设置(可调) ==="
input bool   InpUseRiskRewardRatio = true;    // 启用盈亏比自动算止盈(TP=SL×盈亏比)
input double InpRiskRewardRatio     = 2.0;    // 盈亏比(2:1=2.0 / 3:1=3.0 / 5:1=5.0)

//+------------------------------------------------------------------+
//| 输入参数：最大同时持仓数                                        |
//| - OpenPosition 检查 PositionsTotal()，已满则拒绝                    |
//| - 分批止盈平仓部分仓位后，仓位数减少 → 又可开新仓                    |
//| - 盈亏比参数供分批止盈与手动盈亏比需求参考                          |
//+------------------------------------------------------------------+
input group "=== ★ 最大同时持仓数 ==="
input int    InpMaxPositions        = 2;      // 最大同时持仓数(2=分批止盈平仓部分后可开新仓)
input double InpScalingOutRR        = 3.0;    // 盈亏比(TP/SL倍数): 2:1, 3:1, 3.2:1, 5:1等

//+------------------------------------------------------------------+
//| 输入参数：分批止盈（独立开关，每档比例可调）                     |
//| - 第1档: 利润达 InpScalingOutTrig1×SL 空间时，平掉 总仓位×Ratio1     |
//| - 第2档: 利润达 InpScalingOutTrig2×SL 空间时，平掉 剩余仓位×Ratio2  |
//| - 第3档: 利润达 InpScalingOutTrig3×SL 空间时，平掉 剩余仓位×Ratio3  |
//| - 默认 1×/2×/3×SL 触发，分别平 33% / 剩余50% / 剩余全部             |
//+------------------------------------------------------------------+
input group "=== ★ 分批止盈(独立开关,每档比例可调) ==="
input bool   InpUseScalingOut       = true;    // 启用分批止盈(利润达1/2/3倍止损空间分批平仓)
input double InpScalingOutTrig1     = 1.0;    // 第1档触发: 利润达此倍止损空间
input double InpScalingOutRatio1    = 0.33;   // 第1档平仓比例(占总仓位): 0.25=1/4, 0.33=1/3, 0.50=1/2
input double InpScalingOutTrig2     = 2.0;    // 第2档触发: 利润达此倍止损空间
input double InpScalingOutRatio2    = 0.5;    // 第2档平仓比例(占剩余仓位)
input double InpScalingOutTrig3     = 3.0;    // 第3档触发: 利润达此倍止损空间
input double InpScalingOutRatio3    = 1.0;    // 第3档平仓比例(剩余全部, 默认1.0)

//+------------------------------------------------------------------+
//| 输入参数：同K线禁止重复交易                                         |
//| - 同一根K线上已开过仓（无论是否平仓）则禁止再次开仓                  |
//| - 同一根K线上刚平仓，则决不允许再开仓入场交易                       |
//+------------------------------------------------------------------+
input group "=== 同K线禁止重复交易 ==="
input bool   InpSameBarNoReopen    = true;    // 同一根K线已开仓则禁止再开
input bool   InpSameBarNoAfterClose = true;   // 同一根K线刚平仓则禁止再开

//+------------------------------------------------------------------+
//| 输入参数：收盘强平 + 禁开仓（不持仓过夜）                            |
//| - 距交易结束时间 ≤ InpCloseAllMinsBeforeEnd → 强平全部持仓，不论盈亏 |
//| - 距交易结束时间 ≤ InpNoEntryMinsBeforeEnd  → 禁止开新仓              |
//| - 总开关 InpUseEndCloseAll=false 时全部失效                          |
//+------------------------------------------------------------------+
input group "=== 收盘强平 + 禁开仓(不持仓过夜) ==="
input bool   InpUseEndCloseAll         = true;   // 总开关
input int    InpCloseAllMinsBeforeEnd  = 2;      // 强平提前量(分钟): 距交易结束≤N分钟强平所有持仓,不论盈亏
input int    InpNoEntryMinsBeforeEnd   = 30;     // 禁开仓提前量(分钟): 距交易结束≤N分钟禁止开新仓

//+------------------------------------------------------------------+
//| 输入参数：最小持仓时间（仅延迟启用追踪止损，SL/TP 始终正常触发）      |
//| - 语义：持仓未满 InpMinHoldMinutes 分钟时，追踪(A/B/C)完全不动作     |
//| - 若期间价格打掉 SL 或 TP，属正常平仓，本保护不干预                 |
//| - 收盘强平不受影响（不持仓过夜是独立硬约束）                       |
//| - 服务端 SL/TP 由经纪商执行，EA 无法阻止                             |
//+------------------------------------------------------------------+
input group "=== 最小持仓时间 ==="
input bool   InpUseMinHoldTime    = true;    // 启用最小持仓时间保护
input int    InpMinHoldMinutes    = 20;      // 最小持仓分钟数: 未满此时长不启用追踪

//+------------------------------------------------------------------+
//| 通用交易模块类                                                      |
//+------------------------------------------------------------------+
class CCommonTradingModule
{
private:
   CTrade      m_trade;              // 交易对象
   CPositionInfo m_positionInfo;     // 持仓信息
   COrderInfo  m_orderInfo;          // 订单信息

   datetime    m_lastTradeDay;       // 最后交易日（用于日亏损重置）
   double      m_dailyLoss;          // 当日累计亏损（正值）
   int         m_consecutiveLoss;    // 连续亏损次数
   datetime    m_pauseUntil;         // 暂停到期时间
   datetime    m_lastHistoryCheck;   // 上次历史订单检查时间

   ulong       m_magic;              // 本 EA 的 Magic Number（v4.09：按 magic 统计持仓数）
   bool        m_anyTier1Triggered;  // v4.10：是否有本 EA 仓位已触发过第1档分批止盈
                                       //         用于 effectiveMaxPos 双重保护门（金刚经 v1.17/v1.18）

   //--- 【BUG #5 修复】持久化追踪索引
   // 容量 100（v4.03 之前的旧代码只有 10，第 11 单起永远静默失败）
   // 每次查找前先清理已平仓订单的槽位
   // 触发条件满足但 SL 不需要修改时打印诊断日志
   static const int TRAIL_SLOT_COUNT = 100;
   ulong       m_trailTickets[TRAIL_SLOT_COUNT];
   bool        m_trailSlotUsed[TRAIL_SLOT_COUNT];
   int         m_trailNextIdx;       // 下一个可写入的槽位

   //--- 同K线禁止重复交易（v4.06）
   datetime    m_lastOpenBarTime;    // 最近一次开仓所在的K线开始时间（0=从未开过）
   datetime    m_lastCloseBarTime;   // 最近一次平仓所在的K线开始时间（0=从未平过）

   //--- 最小持仓时间（v4.17）：拦截日志 60 秒节流，避免每 tick 刷屏
   datetime    m_lastMinHoldLogTime; // 上次打印最小持仓时间拦截日志的时间

   //--- 内部辅助函数
   bool        IsNewTradingDay();
   void        UpdateConsecutiveLossFromHistory();
   bool        PositionSelectByTicket(ulong ticket);
   bool        IsTrailingAEnabled();
   bool        IsTrailingBEnabled();
   bool        IsTrailingCEnabled();
   bool        SafeModifyPosition(ulong ticket, double sl, double tp, string context);
   int         FindOrCreateTrailSlot(ulong ticket, bool& outCreated);
   void        PruneClosedTrailSlots();
   bool        IsSameBarReopenAllowed();
   datetime    GetCurrentBarTime();
   int         CountPositionsByMagic();     // v4.09：统计本 EA（按 magic）的持仓数
   int         MinutesToEndOfTrading();     // v4.13：当前距交易结束时间的分钟数（处理跨日）
   void        CloseAllBeforeEndOfTrading(); // v4.13：收盘强平所有本EA持仓
   bool        IsMinHoldTimeSatisfied(ulong ticket); // v4.17：最小持仓时间是否已满足
   void        LogMinHoldBlocked(ulong ticket, string action, int heldMinutes, int needMinutes);

public:
   //--- 初始化与事件
   bool        Init(ulong magicNumber, string tradeComment);
   void        OnTick();
   void        OnTrade();
   void        OnTimer();

   //--- 交易前置检查
   bool        IsTradeTimeAllowed();
   bool        IsTradingAllowed();
   bool        CheckSpreadLimit();
   bool        CheckDailyLossLimit();
   bool        CheckConsecutiveLossPause();

   //--- 仓位与开仓
   double      CalculateLotSize(double slPoints, ENUM_ORDER_TYPE orderType);
   bool        OpenPosition(ENUM_ORDER_TYPE orderType, double price, double slPoints, double tpPoints, string comment);
   bool        OpenPosition(ENUM_ORDER_TYPE orderType, double price, double slPoints, double tpPoints);

   //--- 持仓管理
   void        ApplyStopLossTakeProfit(ulong ticket);
   void        ApplyTrailingStop(ulong ticket);  // 追踪 A：渐进式
   void        ApplyTrailingB(ulong ticket);     // 追踪 B：一次性保本
   void        ApplyTrailingC(ulong ticket);     // 追踪 C：形态追踪（支撑/压力位）
   void        ApplyScalingOut(ulong ticket);     // v4.08：分批止盈（按利润水平）
   void        ManageAllPositions();

   //--- 最小持仓时间（v4.17，供 EA 自有平仓逻辑调用）
   bool        CheckMinHoldTime(ulong ticket) { return IsMinHoldTimeSatisfied(ticket); }
   int         GetHeldMinutes(ulong ticket);

   //--- 状态信息
   double      GetDailyLoss()        const { return m_dailyLoss; }
   int         GetConsecutiveLoss()  const { return m_consecutiveLoss; }
   datetime    GetPauseUntil()       const { return m_pauseUntil; }
};

//+------------------------------------------------------------------+
//| 初始化                                                              |
//+------------------------------------------------------------------+
bool CCommonTradingModule::Init(ulong magicNumber, string tradeComment)
{
   m_magic = magicNumber;   // v4.09：保存 magic 用于按 EA 统计持仓数
   m_trade.SetExpertMagicNumber(magicNumber);
   m_trade.SetDeviationInPoints((ulong)InpMaxSpreadPoints);
   if(tradeComment != "")
      m_trade.SetComment(tradeComment);
   else
      m_trade.SetComment("CommonModule");

   m_trade.LogLevel(LOG_LEVEL_ERRORS);
   m_trade.SetAsyncMode(false);

   m_lastTradeDay = TimeCurrent();
   m_dailyLoss = 0;
   m_consecutiveLoss = 0;
   m_pauseUntil = 0;
   m_lastHistoryCheck = 0;

   // 初始化持久化追踪索引（【BUG #5 修复】容量 100，旧代码 10 不够）
   for(int i = 0; i < TRAIL_SLOT_COUNT; i++)
   {
      m_trailTickets[i] = 0;
      m_trailSlotUsed[i] = false;
      m_trailStage[i] = 0;        // v4.08：分批止盈档位（0=未触发）
   }
   m_trailNextIdx = 0;

   // v4.10：重建 m_anyTier1Triggered（EA 重启后从当前追踪槽位恢复）
   // 扫描本 EA 所有 ticket：只要任何一张仓位处于 stage>=1 即视为"第1档已触发"
   m_anyTier1Triggered = false;
   for(int i = 0; i < TRAIL_SLOT_COUNT; i++)
   {
      if(m_trailSlotUsed[i] && m_trailStage[i] >= 1)
      {
         m_anyTier1Triggered = true;
         break;
      }
   }

   // 同K线禁止重复交易（v4.06）
   m_lastOpenBarTime = 0;
   m_lastCloseBarTime = 0;

   // 最小持仓时间拦截日志节流（v4.17）
   m_lastMinHoldLogTime = 0;

   // 初始化时从历史订单统计当日亏损和连续亏损
   UpdateConsecutiveLossFromHistory();

   // A / B / C 互斥校验（三选一）
   int enabledCount = 0;
   if(InpUseTrailingA) enabledCount++;
   if(InpUseTrailingB) enabledCount++;
   if(InpUseTrailingC) enabledCount++;
   if(enabledCount > 1)
   {
      PrintFormat("CommonModule: 警告 — 追踪 A/B/C 同时勾选了 %d 个，已按优先级 A > B > C 处理", enabledCount);
   }

   // 最小持仓时间参数校验（v4.17，负值视为关闭并提示）
   if(InpUseMinHoldTime && InpMinHoldMinutes < 0)
   {
      PrintFormat("CommonModule: 警告 — 最小持仓分钟数为 %d（负数），已视为关闭", InpMinHoldMinutes);
   }

   return true;
}

//+------------------------------------------------------------------+
//| 追踪 A 启用判断（A 勾选即启用，B/C 勾选无效）                       |
//+------------------------------------------------------------------+
bool CCommonTradingModule::IsTrailingAEnabled()
{
   return InpUseTrailingA && !InpUseTrailingB && !InpUseTrailingC;
}

//+------------------------------------------------------------------+
//| 追踪 B 启用判断（仅当 A 未勾选时 B 勾选才生效）                      |
//+------------------------------------------------------------------+
bool CCommonTradingModule::IsTrailingBEnabled()
{
   return InpUseTrailingB && !InpUseTrailingA && !InpUseTrailingC;
}

//+------------------------------------------------------------------+
//| 追踪 C 启用判断（仅当 A/B 均未勾选时 C 勾选才生效）                  |
//+------------------------------------------------------------------+
bool CCommonTradingModule::IsTrailingCEnabled()
{
   return InpUseTrailingC && !InpUseTrailingA && !InpUseTrailingB;
}

//+------------------------------------------------------------------+
//| 获取当前K线开始时间                                                 |
//+------------------------------------------------------------------+
datetime CCommonTradingModule::GetCurrentBarTime()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == 0)
      t = TimeCurrent();
   return t;
}

//+------------------------------------------------------------------+
//| 同K线禁止重复交易检查（v4.06）                                      |
//| - 同一根K线上已开过仓 → 禁止再开（InpSameBarNoReopen）              |
//| - 同一根K线上刚平仓 → 决不允许再开（InpSameBarNoAfterClose）        |
//| - 两根都关闭则恒返回 true（不限制）                                 |
//+------------------------------------------------------------------+
bool CCommonTradingModule::IsSameBarReopenAllowed()
{
   if(!InpSameBarNoReopen && !InpSameBarNoAfterClose)
      return true;

   datetime curBar = GetCurrentBarTime();

   if(InpSameBarNoReopen && m_lastOpenBarTime == curBar)
      return false;  // 本K线已开过仓

   if(InpSameBarNoAfterClose && m_lastCloseBarTime == curBar)
      return false;  // 本K线刚平仓

   return true;
}

//+------------------------------------------------------------------+
//| 统计本 EA 的持仓数（v4.09，金刚经 v1.17 CountPositions 逻辑）       |
//| - 只统计 magic == m_magic 的持仓（排除其他 EA / 手动单 / 其他品种） |
//| - 关键：分批止盈平掉部分仓位后，该仓位仍是 1 个持仓（ticket 不变），  |
//|   所以仍占 1 个名额，直到完全平仓才释放                               |
//+------------------------------------------------------------------+
int CCommonTradingModule::CountPositionsByMagic()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| 计算当前距交易结束时间的分钟数（v4.13，处理跨日）                     |
//| - 服务器时间 + InpServerHourDiff = 北京时间                          |
//| - 跨日场景（如 7:30 ~ 次日 3:30）：当前是 2:00 时返回 90 分钟         |
//| - 非交易时段返回 -1（不可用）                                       |
//+------------------------------------------------------------------+
int CCommonTradingModule::MinutesToEndOfTrading()
{
   datetime serverTime = TimeCurrent();
   datetime beijingTime = serverTime + InpServerHourDiff * 3600;
   MqlDateTime dt;
   TimeToStruct(beijingTime, dt);

   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes = InpTradeStartHour * 60 + InpTradeStartMinute;
   int endMinutes   = InpTradeEndHour * 60 + InpTradeEndMinute;

   // 跨日（如 7:30 ~ 3:30）：end < start
   if(endMinutes < startMinutes)
   {
      // 当前必须落在两段内：start ~ 24:00 或 00:00 ~ end
      if(currentMinutes >= startMinutes)
      {
         // 第一段（今日）：到次日 endMinutes 还剩 (1440 - current + end) 分钟
         return 1440 - currentMinutes + endMinutes;
      }
      else if(currentMinutes <= endMinutes)
      {
         // 第二段（次日清晨）：距离今日结束还有 (end - current) 分钟
         return endMinutes - currentMinutes;
      }
      return -1;
   }

   // 不跨日：start ~ end
   if(currentMinutes >= startMinutes && currentMinutes <= endMinutes)
      return endMinutes - currentMinutes;

   return -1;
}

//+------------------------------------------------------------------+
//| 收盘强平：平掉所有本 EA 持仓，不论盈亏（v4.13）                      |
//| - 仅当 InpUseEndCloseAll=true 且距结束 ≤ InpCloseAllMinsBeforeEnd   |
//+------------------------------------------------------------------+
void CCommonTradingModule::CloseAllBeforeEndOfTrading()
{
   if(!InpUseEndCloseAll)
      return;

   int minutesLeft = MinutesToEndOfTrading();
   if(minutesLeft < 0)
      return;  // 非交易时段不处理

   if(minutesLeft > InpCloseAllMinsBeforeEnd)
      return;  // 距结束还够久

   // 遍历所有本 EA 持仓，逐一强平
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
         continue;

      double profit = PositionGetDouble(POSITION_PROFIT);
      if(!m_trade.PositionClose(ticket))
      {
         PrintFormat("[EndCloseAll] FAILED ticket=%I64u profit=%.2f retcode=%u (%s)",
                     ticket, profit,
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      }
      else
      {
         PrintFormat("[EndCloseAll] OK ticket=%I64u profit=%.2f (距结束=%d分钟)",
                     ticket, profit, minutesLeft);
      }
   }
}

//+------------------------------------------------------------------+
//| 最小持仓时间：获取某仓位已持仓分钟数（v4.17）                         |
//+------------------------------------------------------------------+
int CCommonTradingModule::GetHeldMinutes(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0;

   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
   if(openTime <= 0)
      return 0;

   int seconds = (int)(TimeCurrent() - openTime);
   if(seconds < 0)
      return 0;

   return seconds / 60;
}

//+------------------------------------------------------------------+
//| 最小持仓时间：判定是否已满足最短持仓时长（v4.17）                    |
//| - InpUseMinHoldTime=false → 恒 true（不限制）                        |
//| - InpMinHoldMinutes<=0 → 恒 true（防呆）                            |
//| - 否则要求：已持仓分钟数 ≥ InpMinHoldMinutes                        |
//+------------------------------------------------------------------+
bool CCommonTradingModule::IsMinHoldTimeSatisfied(ulong ticket)
{
   if(!InpUseMinHoldTime)
      return true;
   if(InpMinHoldMinutes <= 0)
      return true;

   return (GetHeldMinutes(ticket) >= InpMinHoldMinutes);
}

//+------------------------------------------------------------------+
//| 最小持仓时间拦截日志（60 秒节流，避免每 tick 刷屏）                  |
//+------------------------------------------------------------------+
void CCommonTradingModule::LogMinHoldBlocked(ulong ticket, string action, int heldMinutes, int needMinutes)
{
   datetime now = TimeCurrent();
   if(now - m_lastMinHoldLogTime < 60)
      return;
   m_lastMinHoldLogTime = now;

   PrintFormat("[MinHoldTime] BLOCK %s ticket=%I64u 已持仓=%d分钟 < 要求=%d分钟 (继续持仓)",
               action, ticket, heldMinutes, needMinutes);
}

//+------------------------------------------------------------------+
//| 检查是否为新交易日                                                   |
//+------------------------------------------------------------------+
bool CCommonTradingModule::IsNewTradingDay()
{
   MqlDateTime lastDt, currDt;
   TimeToStruct(m_lastTradeDay, lastDt);
   TimeToStruct(TimeCurrent(), currDt);

   if(lastDt.day != currDt.day || lastDt.mon != currDt.mon || lastDt.year != currDt.year)
   {
      m_lastTradeDay = TimeCurrent();
      m_dailyLoss = 0;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 根据订单票号选择持仓                                                 |
//+------------------------------------------------------------------+
bool CCommonTradingModule::PositionSelectByTicket(ulong ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == ticket)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 从历史订单统计连续亏损（启动时或跨日）                               |
//+------------------------------------------------------------------+
void CCommonTradingModule::UpdateConsecutiveLossFromHistory()
{
   if(!InpUseConsecutiveLossPause)
      return;

   datetime startTime = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   datetime endTime = TimeCurrent();

   m_consecutiveLoss = 0;

   HistorySelect(startTime, endTime);
   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY)
         continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double net = profit + swap + commission;

      if(net > 0)
         break;  // 遇到盈利则停止统计连续亏损
      else
         m_consecutiveLoss++;
   }

   m_lastHistoryCheck = TimeCurrent();
}

//+------------------------------------------------------------------+
//| 检查交易时间（北京时间）                                             |
//+------------------------------------------------------------------+
bool CCommonTradingModule::IsTradeTimeAllowed()
{
   datetime serverTime = TimeCurrent();
   // 服务器时间 + 时差 = 北京时间
   datetime beijingTime = serverTime + InpServerHourDiff * 3600;

   MqlDateTime dt;
   TimeToStruct(beijingTime, dt);

   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes = InpTradeStartHour * 60 + InpTradeStartMinute;
   int endMinutes = InpTradeEndHour * 60 + InpTradeEndMinute;

   // 结束时间跨天（例如 7:30 ~ 次日 3:30）
   if(endMinutes < startMinutes)
   {
      // 允许两段：start ~ 24:00 和 00:00 ~ end
      if(currentMinutes >= startMinutes || currentMinutes <= endMinutes)
         return true;
   }
   else
   {
      if(currentMinutes >= startMinutes && currentMinutes <= endMinutes)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| 检查是否允许交易（综合）                                             |
//+------------------------------------------------------------------+
bool CCommonTradingModule::IsTradingAllowed()
{
   if(!IsTradeTimeAllowed())
      return false;

   if(!CheckSpreadLimit())
      return false;

   if(!CheckDailyLossLimit())
      return false;

   if(!CheckConsecutiveLossPause())
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| 检查点差限制                                                         |
//+------------------------------------------------------------------+
bool CCommonTradingModule::CheckSpreadLimit()
{
   if(!InpUseSpreadLimit)
      return true;

   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPts > InpMaxSpreadPoints)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| 检查当日最大亏损限制                                                 |
//+------------------------------------------------------------------+
bool CCommonTradingModule::CheckDailyLossLimit()
{
   if(!InpUseDailyLossLimit)
      return true;

   IsNewTradingDay(); // 跨日重置

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxLoss = balance * InpDailyLossPercent / 100.0;

   if(m_dailyLoss >= maxLoss)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| 检查连续亏损暂停                                                     |
//+------------------------------------------------------------------+
bool CCommonTradingModule::CheckConsecutiveLossPause()
{
   if(!InpUseConsecutiveLossPause)
      return true;

   if(TimeCurrent() < m_pauseUntil)
      return false;

   // 暂停已到期，重置
   if(m_pauseUntil > 0 && TimeCurrent() >= m_pauseUntil)
   {
      m_pauseUntil = 0;
      m_consecutiveLoss = 0;
   }

   if(m_consecutiveLoss >= InpConsecutiveLossCount)
   {
      m_pauseUntil = TimeCurrent() + InpPauseMinutes * 60;
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 计算手数                                                            |
//+------------------------------------------------------------------+
double CCommonTradingModule::CalculateLotSize(double slPoints, ENUM_ORDER_TYPE orderType)
{
   if(InpUseFixedLot)
   {
      double lots = InpFixedLot;
      lots = NormalizeLot(lots);
      return lots;
   }

   // 按风险百分比计算
   if(slPoints <= 0)
   {
      Print("CommonModule: SL points invalid, using min lot");
      return NormalizeLot(InpMinLot);
   }

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLotSym = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickSize <= 0 || tickValue <= 0 || lotStep <= 0)
   {
      Print("CommonModule: Symbol info invalid");
      return NormalizeLot(InpMinLot);
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;

   // 每手在SL点数的亏损 = 止损点数 * 每点价值 / 最小跳动价
   double lossPerLot = slPoints * tickValue / tickSize;
   double lots = riskAmount / lossPerLot;

   // 对齐到合约步长
   lots = MathFloor(lots / lotStep) * lotStep;

   // 限制范围
   lots = MathMax(lots, MathMax(minLot, InpMinLot));
   lots = MathMin(lots, MathMin(maxLotSym, InpMaxLot));

   return NormalizeLot(lots);
}

//+------------------------------------------------------------------+
//| 规范化手数（对齐到 SYMBOL_VOLUME_STEP）                              |
//+------------------------------------------------------------------+
double NormalizeLot(double lots)
{
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lotStep <= 0)
      lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);

   return lots;
}

//+------------------------------------------------------------------+
//| 开仓（带注释）                                                       |
//| 1. 综合风控检查（时间/日亏损/点差/暂停）                            |
//| 2. 收盘禁开仓（v4.13）：距结束 ≤ InpNoEntryMinsBeforeEnd 则拒绝      |
//| 3. 同K线禁止重复交易检查（v4.06）                                  |
//| 4. 最大止损限制（v4.07）：slPoints > InpMaxSLPoints 则拒绝          |
//| 5. 最大持仓双重保护门（v4.11 金刚经 v1.20 修复）：                   |
//|    effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1      |
//|    （去掉 InpUseTieredTP 依赖；每个新仓位独立证明；开仓后清零）      |
//| 6. 盈亏比 TP 自动计算（v4.06）：TP点数 = SL点数 × 盈亏比             |
//| 7. 开仓成功后：记录本K线时间 + 清零 m_anyTier1Triggered             |
+------------------------------------------------------------------+
bool CCommonTradingModule::OpenPosition(ENUM_ORDER_TYPE orderType, double price, double slPoints, double tpPoints, string comment)
{
   if(!IsTradingAllowed())
      return false;

   // 收盘禁开仓（v4.13）：距交易结束 ≤ InpNoEntryMinsBeforeEnd 分钟 → 禁止开新仓
   if(InpUseEndCloseAll && InpNoEntryMinsBeforeEnd > 0)
   {
      int minutesLeft = MinutesToEndOfTrading();
      if(minutesLeft >= 0 && minutesLeft <= InpNoEntryMinsBeforeEnd)
      {
         PrintFormat("CommonModule: 拒绝开仓 — 距交易结束仅 %d 分钟（≤ 禁开仓阈值 %d 分钟）",
                     minutesLeft, InpNoEntryMinsBeforeEnd);
         return false;
      }
   }

   // 同K线禁止重复交易（v4.06）
   if(!IsSameBarReopenAllowed())
   {
      PrintFormat("CommonModule: 拒绝开仓 — 同一根K线已交易过（lastOpen=%I64u lastClose=%I64u 当前bar=%I64u）",
                  m_lastOpenBarTime, m_lastCloseBarTime, GetCurrentBarTime());
      return false;
   }

   // 最大止损限制（v4.07）：止损点数超过上限则拒绝开仓
   if(InpUseMaxSLPoints && slPoints > InpMaxSLPoints)
   {
      PrintFormat("CommonModule: 拒绝开仓 — 止损过大 (%d 点 > 上限 %d 点)", slPoints, InpMaxSLPoints);
      return false;
   }

   // 最大同时持仓数检查（v4.11 金刚经 v1.20 修复：彻底独立于参数开关）
   // effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1
   // v4.20 修复 1：去掉 InpUseScalingOut 依赖（状态本身已足够判断）
   // v4.20 修复 2：OpenPosition 成功后立即清零 m_anyTier1Triggered（每个新仓位独立证明）
   if(InpMaxPositions > 0)
   {
      int myCount = CountPositionsByMagic();
      int effectiveMaxPos = m_anyTier1Triggered ? InpMaxPositions : 1;
      if(myCount >= effectiveMaxPos)
      {
         PrintFormat("CommonModule: 拒绝开仓 — 已达最大持仓 (CountPositions=%d effectiveMaxPos=%d InpMaxPositions=%d Tier1Triggered=%s)",
                     myCount, effectiveMaxPos, InpMaxPositions,
                     m_anyTier1Triggered ? "true" : "false");
         return false;
      }
   }

   double lots = CalculateLotSize(slPoints, orderType);
   if(lots <= 0)
   {
      Print("CommonModule: Lot size is zero");
      return false;
   }

   // 盈亏比自动算止盈（v4.06）：TP点数 = SL点数 × 盈亏比
   if(InpUseRiskRewardRatio && slPoints > 0)
   {
      double ratio = (InpRiskRewardRatio > 0.1) ? InpRiskRewardRatio : 2.0;
      tpPoints = (int)MathRound(slPoints * ratio);
   }

   double sl = 0, tp = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      point = _Point;

   if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP)
   {
      if(InpUseFixedStopLoss && slPoints > 0)
         sl = price - slPoints * point;
      if(InpUseFixedTakeProfit && tpPoints > 0)
         tp = price + tpPoints * point;
   }
   else if(orderType == ORDER_TYPE_SELL || orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP)
   {
      if(InpUseFixedStopLoss && slPoints > 0)
         sl = price + slPoints * point;
      if(InpUseFixedTakeProfit && tpPoints > 0)
         tp = price - tpPoints * point;
   }

   if(comment != "")
      m_trade.SetComment(comment);

   bool result = m_trade.PositionOpen(_Symbol, orderType, lots, price, sl, tp);

   if(!result)
   {
      Print("CommonModule: OpenPosition failed. Retcode: ", m_trade.ResultRetcode());
      return false;
   }

   // 记录本K线已开仓（同K线禁止重复交易）
   m_lastOpenBarTime = GetCurrentBarTime();

   // v4.11（金刚经 v1.20 修复 2）：开仓成功后立即清零 m_anyTier1Triggered
   // 每个新仓位必须独立走出 1× 利润，才能允许下一仓；不能共享上一仓的"已触发"状态
   m_anyTier1Triggered = false;

   PrintFormat("CommonModule: 开仓成功 ticket=%I64u 记录 lastOpenBar=%I64u", m_trade.ResultOrder(), m_lastOpenBarTime);

   return true;
}

//+------------------------------------------------------------------+
//| 开仓（默认注释）                                                       |
//+------------------------------------------------------------------+
bool CCommonTradingModule::OpenPosition(ENUM_ORDER_TYPE orderType, double price, double slPoints, double tpPoints)
{
   return OpenPosition(orderType, price, slPoints, tpPoints, "");
}

//+------------------------------------------------------------------+
//| 应用固定止损止盈（每单独立，未设置则补设）                           |
//+------------------------------------------------------------------+
void CCommonTradingModule::ApplyStopLossTakeProfit(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      point = _Point;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);

   // 若追踪 A/B 已修改过 SL（currentSL 不等于 0），则不再覆盖
   if(currentSL != 0)
      return;

   // 若用户关闭了固定止损/止盈开关，则不补设
   if(!InpUseFixedStopLoss && !InpUseFixedTakeProfit)
      return;

   double newSL = 0, newTP = 0;

   // 盈亏比自动算止盈（v4.06）：TP点数 = SL点数 × 盈亏比
   int effTPPoints = InpFixedTPPoints;
   if(InpUseRiskRewardRatio && InpFixedSLPoints > 0)
   {
      double ratio = (InpRiskRewardRatio > 0.1) ? InpRiskRewardRatio : 2.0;
      effTPPoints = (int)MathRound(InpFixedSLPoints * ratio);
   }

   if(posType == POSITION_TYPE_BUY)
   {
      if(InpUseFixedStopLoss && InpFixedSLPoints > 0)
         newSL = openPrice - InpFixedSLPoints * point;
      if(InpUseFixedTakeProfit && effTPPoints > 0)
         newTP = openPrice + effTPPoints * point;
   }
   else // POSITION_TYPE_SELL
   {
      if(InpUseFixedStopLoss && InpFixedSLPoints > 0)
         newSL = openPrice + InpFixedSLPoints * point;
      if(InpUseFixedTakeProfit && effTPPoints > 0)
         newTP = openPrice - effTPPoints * point;
   }

   if(newSL != 0 || newTP != 0)
      SafeModifyPosition(ticket, newSL, newTP, "ApplyStopLossTakeProfit");
}

//+------------------------------------------------------------------+
//| 追踪止损 A：渐进式（持续追踪SL+保本）                                |
//| - 利润达到 InpTrailingAActivatePts 后开始追踪 SL                    |
//| - 利润达到 InpTrailingABreakEvenPts 后将 SL 移到入场价（保本）       |
//+------------------------------------------------------------------+
void CCommonTradingModule::ApplyTrailingStop(ulong ticket)
{
   if(!IsTrailingAEnabled())
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      point = _Point;

   double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL  = PositionGetDouble(POSITION_SL);
   double currentTP  = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
   // 【BUG #1 修复】使用原始 Bid/Ask 价格差计算点数差，而不是 POSITION_PROFIT
   // 原因：POSITION_PROFIT 是货币盈亏，不含 swap/commission；如果用它反算等效点数，
   //       持仓过夜累积的 swap 会让"价格等价点数"偏低，导致追踪永远触发不到。
   //       改用纯价格差：profitPoints = (currentPrice - openPrice) / point
   //       这就是用户截图里说的"用原始 Bid/Ask 价格差触发"。
   double profitPoints = (posType == POSITION_TYPE_BUY)
                         ? (currentPrice - openPrice) / point
                         : (openPrice - currentPrice) / point;

   //--- 阶段 1：达到保本点数时，将 SL 移至入场价（保本锁）
   if(profitPoints >= InpTrailingABreakEvenPts && InpTrailingABreakEvenPts > 0)
   {
      double beSL = (posType == POSITION_TYPE_BUY) ? openPrice + 2 * point : openPrice - 2 * point;
      beSL = NormalizeDouble(beSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

      // 【BUG #4 修复】统一为 (currentSL==0) 强制分支 + 价格比较
      // 原因：之前 BUY 漏了 (currentSL==0) 判断，理论上当持仓从未设过 SL 时，
      //       若 newSL 恰好在 [0, point] 区间内，BUY 不会触发移动；SELL 因为
      //       显式 || currentSL==0 分支会触发，导致两侧行为不对称。
      bool needMove = false;
      if(posType == POSITION_TYPE_BUY)
      {
         if(currentSL == 0 || currentSL < beSL - point)
            needMove = true;
      }
      else // SELL
      {
         if(currentSL == 0 || currentSL > beSL + point)
            needMove = true;
      }

      if(needMove)
      {
         // 【关键】第三个参数必须传 currentTP，传 0 会清掉 660 点止盈
         SafeModifyPosition(ticket, beSL, currentTP, "ApplyTrailingStop.Phase1.BreakEven");
         return; // 保本已生效，本 tick 不再做持续追踪
      }
   }

   //--- 阶段 2：达到追踪激活点数时，持续追踪 SL（每 1 个点距离）
   if(profitPoints >= InpTrailingAActivatePts && InpTrailingAActivatePts > 0)
   {
      double newSL = 0;
      if(posType == POSITION_TYPE_BUY)
         newSL = currentPrice - 1 * point; // 紧贴当前价 +1 点的回撤容忍
      else
         newSL = currentPrice + 1 * point;

      newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

      // 【BUG #4 修复】同样为 BUY 补上 (currentSL==0) 强制分支
      bool needMove = false;
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

      // 【BUG #5 修复】诊断日志：触发条件已满足但 SL 不需要修改时
      // 附带完整状态（profit / newSL / currentSL）方便排查
      if(!needMove)
      {
         PrintFormat("[TrailingA.Phase2] SKIP ticket=%I64u profit=%.1fpts newSL=%.5f currentSL=%.5f (触发条件已满足但 SL 无需前移)",
                     ticket, profitPoints, newSL, currentSL);
         return;
      }

      SafeModifyPosition(ticket, newSL, currentTP, "ApplyTrailingStop.Phase2.Active");
   }
}

//+------------------------------------------------------------------+
//| 追踪止损 B：一次性保本（触发后锁死）                                |
//| - 利润达到 InpTrailingBTriggerPts 时，将 SL 移到开仓价 ±保护点数     |
//| - 触发一次后即锁定，不再移动                                        |
//+------------------------------------------------------------------+
void CCommonTradingModule::ApplyTrailingB(ulong ticket)
{
   if(!IsTrailingBEnabled())
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      point = _Point;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- 若 SL 已经被移动过（不处于初始 0 或固定 SL 位置），则视为已锁死，不再处理
   // 通过判断 SL 是否已经在入场价 + 保护利润范围内来识别是否已触发
   double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
   // 【BUG #1 修复】使用原始 Bid/Ask 价格差，不用 POSITION_PROFIT 反算（避免 swap 干扰）
   double profitPoints = (posType == POSITION_TYPE_BUY)
                         ? (currentPrice - openPrice) / point
                         : (openPrice - currentPrice) / point;

   // 未达到触发点数：保持原样
   if(profitPoints < InpTrailingBTriggerPts || InpTrailingBTriggerPts <= 0)
      return;

   // 计算目标 SL：开仓价 ± 保护利润点数
   double targetSL = 0;
   if(posType == POSITION_TYPE_BUY)
      targetSL = openPrice + InpTrailingBProtectPts * point;
   else
      targetSL = openPrice - InpTrailingBProtectPts * point;

   targetSL = NormalizeDouble(targetSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   //--- 一次性触发：仅当当前 SL 比目标 SL 更差时才移动
   // BUY：currentSL 小于 targetSL 才移动（保护利润）
   // SELL：currentSL 大于 targetSL 才移动（保护利润）
   // 【BUG #4 修复】为 BUY 补上 (currentSL==0) 强制分支，与 SELL 保持对称
   bool needMove = false;
   if(posType == POSITION_TYPE_BUY)
   {
      if(currentSL == 0 || currentSL < targetSL - point)
         needMove = true;
   }
   else // SELL
   {
      if(currentSL == 0 || currentSL > targetSL + point)
         needMove = true;
   }

   // 【BUG #5 修复】诊断日志：触发条件已满足但 SL 已经在 targetSL 附近
   if(!needMove)
   {
      PrintFormat("[TrailingB.OneShot] SKIP ticket=%I64u profit=%.1fpts targetSL=%.5f currentSL=%.5f (已锁死在保护位或更优位置)",
                  ticket, profitPoints, targetSL, currentSL);
      return;
   }

   if(needMove)
   {
      // 【关键】第三个参数必须传 currentTP，传 0 会清掉 660 点止盈
      SafeModifyPosition(ticket, targetSL, currentTP, "ApplyTrailingB.OneShotBreakEven");
   }
   // 触发后即锁死：下一次 tick 即使价格再上涨也不再移动
}

//+------------------------------------------------------------------+
//| 分批止盈 (v4.08，金刚经策略 v1.16 模式)                            |
//| - 利润达到 InpScalingOutTrigN × 当前止损空间 时触发第 N 档          |
//| - 第 N 档平仓量 = 剩余仓位 × InpScalingOutRatioN                     |
//| - 第1档占总仓位（不是剩余），第2/3档占剩余仓位                      |
//| - 默认 1×/2×/3×SL 触发，分别平 33% / 剩余 50% / 剩余全部           |
//| - 与追踪 A/B/C 互补，仓位部分平仓后 SL 仍由追踪模式管理            |
//+------------------------------------------------------------------+
void CCommonTradingModule::ApplyScalingOut(ulong ticket)
{
   if(!InpUseScalingOut)
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      point = _Point;

   // 查找/创建追踪槽位，获取当前分批档位
   bool created = false;
   int idx = FindOrCreateTrailSlot(ticket, created);
   if(idx < 0)
      return;

   int stage = m_trailStage[idx];
   if(stage >= 3)
      return; // 3档已全部触发或仓位已清空

   // 获取当前止损空间（点数）
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;

   // 【BUG #1 修复】使用原始 Bid/Ask 价格差，不用 POSITION_PROFIT
   double profitPoints = (posType == POSITION_TYPE_BUY)
                         ? (currentPrice - openPrice) / point
                         : (openPrice - currentPrice) / point;

   // 计算当前止损空间（绝对点数）
   double slSpacePoints = 0;
   if(currentSL > 0)
   {
      slSpacePoints = (posType == POSITION_TYPE_BUY)
                      ? (openPrice - currentSL) / point
                      : (currentSL - openPrice) / point;
   }
   if(slSpacePoints <= 0)
   {
      // 未设置 SL，无法计算止损空间 → 跳过
      return;
   }

   // 根据当前 stage 选择对应的 trigger 和 ratio
   double trigger = 0;
   double ratio   = 0;
   if(stage == 0)      { trigger = InpScalingOutTrig1; ratio = InpScalingOutRatio1; }
   else if(stage == 1) { trigger = InpScalingOutTrig2; ratio = InpScalingOutRatio2; }
   else                { trigger = InpScalingOutTrig3; ratio = InpScalingOutRatio3; }

   if(trigger <= 0)
      return; // 该档未配置（无效配置，跳过）

   // 未达到触发条件
   if(profitPoints < trigger * slSpacePoints)
      return;

   // 计算平仓量
   double currentVol = PositionGetDouble(POSITION_VOLUME);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(currentVol <= 0 || lotStep <= 0)
      return;

   double closeLots = NormalizeLot(MathFloor(currentVol * ratio / lotStep) * lotStep);
   closeLots = MathMax(closeLots, minLot);

   // 保护：不允许超过剩余仓位
   if(closeLots >= currentVol)
      closeLots = currentVol;

   // 平仓
   if(!m_trade.PositionClosePartial(ticket, closeLots))
   {
      PrintFormat("[ScalingOut.Stage%d] PositionClosePartial FAILED ticket=%I64u closeLots=%.2f retcode=%u (%s)",
                  stage + 1, ticket, closeLots,
                  m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
      return;
   }

   // 更新 stage
   int nextStage = (closeLots >= currentVol - lotStep * 0.5) ? 3 : (stage + 1);
   m_trailStage[idx] = nextStage;

   // v4.10：第1档触发即设置标志（用于 effectiveMaxPos 双重保护门）
   if(stage == 0)
      m_anyTier1Triggered = true;

   PrintFormat("[ScalingOut.Stage%d] OK ticket=%I64u closeLots=%.2f remaining=%.2f profit=%.1fpts trigger=%.2fxSL=%.1fpts nextStage=%d",
               stage + 1, ticket, closeLots, currentVol - closeLots, profitPoints, trigger, slSpacePoints, nextStage);
}

//+------------------------------------------------------------------+
//| 追踪止损 C：形态追踪止损（三选一，与 A/B 互斥）                     |
//| - 阶段1: 利润 < InpTrailingCTriggerPts(300) → SL 完全不移动        |
//| - 阶段2: 利润 ≥ 300 → SL 移到开仓±保护利润(55)                     |
//| - 阶段3: 之后按形态移动：多头找最近支撑位(摆动低点)下方20点        |
//|                 空头找最近压力位(摆动高点)上方20点                 |
//| - 摆动点检测: strength=2 (左右各2根K线确认极值)                    |
//| - 保留当前 TP（2:1 止盈）不动                                       |
//+------------------------------------------------------------------+
void CCommonTradingModule::ApplyTrailingC(ulong ticket)
{
   if(!IsTrailingCEnabled())
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      point = _Point;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // 用原始 Bid/Ask 价格差计算点数(不受 swap 影响)
   double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
   double profitPoints = (posType == POSITION_TYPE_BUY)
                         ? (currentPrice - openPrice) / point
                         : (openPrice - currentPrice) / point;

   // --- 阶段1: 利润未达触发点, 不动作 ---
   if(!InpTrailingCUsePatternOnly)
   {
      if(profitPoints < InpTrailingCTriggerPts || InpTrailingCTriggerPts <= 0)
         return;
   }

   // --- 阶段2: 保本锁利 SL = 开仓价 ± 保护利润点数 ---
   double targetSL = 0;
   if(posType == POSITION_TYPE_BUY)
      targetSL = openPrice + InpTrailingCProtectPts * point;
   else
      targetSL = openPrice - InpTrailingCProtectPts * point;

   // --- 阶段3: 形态追踪 - 找最近支撑/压力摆动位 ---
   int swingIdx = -1;
   int strength = 2;                    // 简化摆动强度(形态追踪用2根足够)
   int maxIdx   = MathMin(60, Bars(_Symbol, InpTrailingCPatternTF) - strength - 2);
   for(int i = strength + 1; i <= maxIdx; i++)
   {
      bool isSwing = true;
      if(posType == POSITION_TYPE_BUY)  // 支撑位 = 摆动低点
      {
         double low = iLow(_Symbol, InpTrailingCPatternTF, i);
         for(int j = 1; j <= strength; j++)
         {
            if(iLow(_Symbol, InpTrailingCPatternTF, i - j) <= low) { isSwing = false; break; }
            if(iLow(_Symbol, InpTrailingCPatternTF, i + j) <= low) { isSwing = false; break; }
         }
         if(isSwing)
         {
            swingIdx = i;
            break;
         }
      }
      else                              // 压力位 = 摆动高点
      {
         double high = iHigh(_Symbol, InpTrailingCPatternTF, i);
         for(int j = 1; j <= strength; j++)
         {
            if(iHigh(_Symbol, InpTrailingCPatternTF, i - j) >= high) { isSwing = false; break; }
            if(iHigh(_Symbol, InpTrailingCPatternTF, i + j) >= high) { isSwing = false; break; }
         }
         if(isSwing)
         {
            swingIdx = i;
            break;
         }
      }
   }

   // 找到形态位 → SL 放到支撑/压力位外缓冲
   if(swingIdx > 0)
   {
      if(posType == POSITION_TYPE_BUY)
      {
         double swingLow = iLow(_Symbol, InpTrailingCPatternTF, swingIdx);
         double patternSL = swingLow - InpTrailingCSLBufferPts * point;
         if(patternSL > targetSL)          // 只向更有利方向移动
            targetSL = patternSL;
      }
      else
      {
         double swingHigh = iHigh(_Symbol, InpTrailingCPatternTF, swingIdx);
         double patternSL = swingHigh + InpTrailingCSLBufferPts * point;
         if(patternSL < targetSL)          // 只向更有利方向移动
            targetSL = patternSL;
      }
   }

   targetSL = NormalizeDouble(targetSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   // 仅当 SL 比当前更有利时才移动
   bool needMove = false;
   if(posType == POSITION_TYPE_BUY)
   {
      if(currentSL == 0 || targetSL > currentSL + point)
         needMove = true;
   }
   else // SELL
   {
      if(currentSL == 0 || targetSL < currentSL - point)
         needMove = true;
   }

   if(!needMove)
   {
      PrintFormat("[TrailingC.Pattern] SKIP ticket=%I64u profit=%.1fpts targetSL=%.5f currentSL=%.5f (SL已更优)",
                  ticket, profitPoints, targetSL, currentSL);
      return;
   }

   // 【关键】保留当前TP, 不能传0
   SafeModifyPosition(ticket, targetSL, currentTP, "ApplyTrailingC.PatternTrailing");
}

//+------------------------------------------------------------------+
//| 安全的 PositionModify 包装：失败时打印 retcode + 上下文，方便排查   |
//| - 任何返回 false 的内部调用都会触发日志                               |
//| - context 用于定位是哪段追踪/补设逻辑                                |
//+------------------------------------------------------------------+
bool CCommonTradingModule::SafeModifyPosition(ulong ticket, double sl, double tp, string context)
{
   if(ticket == 0)
   {
      PrintFormat("[%s] PositionModify failed: ticket=0", context);
      return false;
   }

   if(!m_trade.PositionModify(ticket, sl, tp))
   {
      PrintFormat("[%s] PositionModify FAILED ticket=%I64u sl=%.5f tp=%.5f retcode=%u (%s) request=%s",
                  context,
                  ticket, sl, tp,
                  m_trade.ResultRetcode(),
                  m_trade.ResultRetcodeDescription(),
                  m_trade.ResultRequestDescription());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| 持久化追踪索引工具 (【BUG #5 修复】)                                |
//| - 容量 100（远超常见 EA 的同时持仓数）                              |
//| - 每次查找前自动清理已平仓订单的槽位（避免"只增不减"）              |
//| - 找不到可用槽位时返回 -1，调用方应处理这种情况                     |
//+------------------------------------------------------------------+
int CCommonTradingModule::FindOrCreateTrailSlot(ulong ticket, bool& outCreated)
{
   outCreated = false;
   if(ticket == 0)
      return -1;

   //--- 步骤 1：先查找（顺便清理已平仓的槽位）
   PruneClosedTrailSlots();

   for(int i = 0; i < TRAIL_SLOT_COUNT; i++)
   {
      if(m_trailSlotUsed[i] && m_trailTickets[i] == ticket)
         return i; // 已存在
   }

   //--- 步骤 2：未找到，找一个空闲槽位（环形查找，从 m_trailNextIdx 开始）
   for(int step = 0; step < TRAIL_SLOT_COUNT; step++)
   {
      int idx = (m_trailNextIdx + step) % TRAIL_SLOT_COUNT;
      if(!m_trailSlotUsed[idx])
      {
         m_trailTickets[idx] = ticket;
         m_trailSlotUsed[idx] = true;
         m_trailStage[idx] = 0;     // v4.08：新槽位分批档位归零
         m_trailNextIdx = (idx + 1) % TRAIL_SLOT_COUNT;
         outCreated = true;
         return idx;
      }
   }

   //--- 步骤 3：100 个槽位都满了（极端情况：同时持仓 100+ 单）
   PrintFormat("[TrailSlot] 索引已满（容量=%d），ticket=%I64u 跳过追踪", TRAIL_SLOT_COUNT, ticket);
   return -1;
}

//+------------------------------------------------------------------+
//| 清理已平仓订单的槽位（【BUG #5 修复】自动清理）                      |
//+------------------------------------------------------------------+
void CCommonTradingModule::PruneClosedTrailSlots()
{
   for(int i = 0; i < TRAIL_SLOT_COUNT; i++)
   {
      if(!m_trailSlotUsed[i])
         continue;

      ulong ticket = m_trailTickets[i];
      if(ticket == 0)
      {
         m_trailSlotUsed[i] = false;
         continue;
      }

      // 检查订单是否还活着
      bool alive = false;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         if(PositionGetTicket(p) == ticket)
         {
            alive = true;
            break;
         }
      }
      if(!alive)
      {
         m_trailTickets[i] = 0;
         m_trailSlotUsed[i] = false;
         m_trailStage[i] = 0;       // v4.08：清理已平仓订单的档位
      }
   }
}

//+------------------------------------------------------------------+
//| 管理所有持仓：止损止盈、追踪止损(A / B / C)                         |
//| 【BUG #2 修复】必须放在 OnTick 第一行，g_Common.OnTick() 之前！      |
//| 本函数不受 IsTradingAllowed 限制                                    |
//| 即使在非交易时间/日亏损/点差超标时，也会执行保本追踪                  |
//| 灾难场景：若先调 IsTradingAllowed() 再 return，已持仓的保本追踪     |
//|          永远不会被触发；下次行情回撤直接穿仓。                     |
//+------------------------------------------------------------------+
void CCommonTradingModule::ManageAllPositions()
{
   // 收盘强平（v4.13）：距交易结束 ≤ InpCloseAllMinsBeforeEnd 时全部强平本 EA 持仓
   // 优先执行：避免追踪/分批止盈在最后两分钟做无意义的调整
   CloseAllBeforeEndOfTrading();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      // 先补设基础 SL/TP（始终执行）
      ApplyStopLossTakeProfit(ticket);

      // 分批止盈（v4.08）：独立于追踪模式，按利润水平分批平仓
      ApplyScalingOut(ticket);

      //--- v4.17 最小持仓时间：仅延迟启用追踪止损 ---
      // 语义：SL/TP 始终由经纪商端正常触发，本保护只拦截"移动 SL"这一动作。
      // 持仓未满 InpMinHoldMinutes 分钟时，追踪(A/B/C)完全不动作；
      // 若期间价格打掉 SL 或 TP，属正常平仓，本保护不干预。
      if(!IsMinHoldTimeSatisfied(ticket))
      {
         LogMinHoldBlocked(ticket, "Trailing", GetHeldMinutes(ticket), InpMinHoldMinutes);
         continue;   // 未满最小持仓时间 → 跳过追踪，继续下一单
      }

      // 再根据模式执行追踪（优先级 A > B > C，三选一）
      if(IsTrailingAEnabled())
         ApplyTrailingStop(ticket);
      else if(IsTrailingBEnabled())
         ApplyTrailingB(ticket);
      else if(IsTrailingCEnabled())
         ApplyTrailingC(ticket);
   }
}

//+------------------------------------------------------------------+
//| OnTick 事件处理：管理持仓                                            |
//+------------------------------------------------------------------+
void CCommonTradingModule::OnTick()
{
   ManageAllPositions();
}

//+------------------------------------------------------------------+
//| OnTrade 事件处理：统计日亏损和连续亏损                                |
//+------------------------------------------------------------------+
void CCommonTradingModule::OnTrade()
{
   IsNewTradingDay(); // 跨日重置

   // 仅每隔一段时间检查历史，避免频繁调用
   if(TimeCurrent() - m_lastHistoryCheck < 1)
      return;

   m_lastHistoryCheck = TimeCurrent();

   datetime startTime = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   datetime endTime = TimeCurrent();

   HistorySelect(startTime, endTime);
   int total = HistoryDealsTotal();

   // 本次只处理最新的平仓交易
   // 注意：OnTrade 可能重复触发，需要通过记录上次处理票号避免重复
   static ulong s_lastProcessedTicket = 0;

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(ticket <= s_lastProcessedTicket)
         continue;

      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY)
         continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double net = profit + swap + commission;

      // 同K线禁止重复交易（v4.12 金刚经 v1.21 双修复）：
      // 修复 1：只认"30 秒内真实发生的本 EA 平仓"——EA 加载时历史平仓单（几天前）不应触发冷却
      // 修复 2：记录 iTime(..., 0) 当前K线时间——bar0 变 bar1 后 sigBarTime==m_lastCloseBarTime，
      //         下一根K线开始时 sigBarTime（新的 bar0） != m_lastCloseBarTime → 正确解除冷却
      ulong dealMagic = (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      bool isRecent = (dealTime > 0 && (TimeCurrent() - dealTime) <= 30);
      if(isRecent && dealMagic == m_magic && dealEntry == DEAL_ENTRY_OUT)
      {
         datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
         if(currentBarTime > m_lastCloseBarTime)
            m_lastCloseBarTime = currentBarTime;
      }

      if(net < 0)
      {
         m_dailyLoss += MathAbs(net);
         m_consecutiveLoss++;

         // 检查是否触发连续亏损暂停
         if(InpUseConsecutiveLossPause && m_consecutiveLoss >= InpConsecutiveLossCount)
            m_pauseUntil = TimeCurrent() + InpPauseMinutes * 60;
      }
      else
      {
         m_consecutiveLoss = 0;
      }

      s_lastProcessedTicket = ticket;
   }
}

//+------------------------------------------------------------------+
//| OnTimer 事件处理：检查暂停到期、跨日重置                               |
//+------------------------------------------------------------------+
void CCommonTradingModule::OnTimer()
{
   IsNewTradingDay();

   if(m_pauseUntil > 0 && TimeCurrent() >= m_pauseUntil)
   {
      m_pauseUntil = 0;
      m_consecutiveLoss = 0;
   }
}

#endif // C_COMMON_TRADING_MODULE_MQH
