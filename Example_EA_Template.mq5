//+------------------------------------------------------------------+
//| 示例 EA：EMA55MA233SuperTrend 共振吞没入场模板 (v4.20)              |
//| 说明：本 EA 演示如何调用 CCommonTradingModule 通用模块             |
//|       通用模块已含三套追踪止损(追踪A/B/C)，参数面板完整呈现         |
//|                                                                    |
//| ★ 部署位置（决定能否 F5 调试）★                                    |
//|   MetaEditor 的调试由 metatester64.exe 完成，它只会在 MT5 终端     |
//|   自己的数据目录里定位 EA：                                        |
//|       <终端数据目录>\MQL5\Experts\本文件.mq5                       |
//|   放在外部项目目录（如 F:\...\EA系列\）→ F7 能编译、F5 静默失败。  |
//|   本文件用 #include <...>，对应布局：.mqh 放到 MQL5\Include\       |
//|   （注意是 Include，单数，MT5 里没有 Includes 目录）。             |
//|   若把 .mqh 与本文件放同一目录，请改用 #include "..."。            |
//|   一键部署：                                                       |
//|     python scripts/deploy_to_terminal.py --expert <本文件>         |
//|            --include <MT5_EA_Common_Trading_Module.mqh> --terminal all
//|   详细说明见 references/deployment.md                              |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""
#property version   "4.20"
#property strict

// .mqh 位于 MQL5\Include\ 时用尖括号；与 .mq5 同目录时改用引号 "MT5_EA_Common_Trading_Module.mqh"
#include <MT5_EA_Common_Trading_Module.mqh>

//+------------------------------------------------------------------+
//| 策略输入参数（示例，可按需扩展）                                    |
//+------------------------------------------------------------------+
input group "=== 策略参数(示例) ==="
input int    InpEMAFastPeriod   = 55;      // EMA 快速周期
input int    InpMASlowPeriod    = 233;     // MA 慢速周期
input int    InpSuperTrendPeriod = 10;     // SuperTrend 周期
input double InpSuperTrendMultiplier = 3.0; // SuperTrend 倍数
input int    InpSignalMagic     = 20250709; // EA Magic Number
input string InpSignalComment   = "EMA55ST"; // 订单注释

//+------------------------------------------------------------------+
//| 全局变量                                                            |
//+------------------------------------------------------------------+
CCommonTradingModule g_Common;
int    g_HandleEMA = INVALID_HANDLE;
int    g_HandleMA  = INVALID_HANDLE;
int    g_HandleST  = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| 初始化函数                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_Common.Init(InpSignalMagic, InpSignalComment))
   {
      Print("Init common module failed");
      return INIT_FAILED;
   }

   // 创建指标句柄（示例：可根据真实指标调整）
   g_HandleEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleMA  = iMA(_Symbol, PERIOD_CURRENT, InpMASlowPeriod, 0, MODE_SMA, PRICE_CLOSE);
   // g_HandleST  = iCustom(_Symbol, PERIOD_CURRENT, "SuperTrend", InpSuperTrendPeriod, InpSuperTrendMultiplier);

   if(g_HandleEMA == INVALID_HANDLE || g_HandleMA == INVALID_HANDLE)
   {
      Print("Indicator init failed");
      return INIT_FAILED;
   }

   EventSetTimer(60);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| 去初始化函数                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(g_HandleEMA);
   IndicatorRelease(g_HandleMA);
   if(g_HandleST != INVALID_HANDLE)
      IndicatorRelease(g_HandleST);
}

//+------------------------------------------------------------------+
//| 报价函数                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. 【最优先】保本追踪：必须在任何风控检查之前执行
   //    即使处于非交易时间 / 日亏损 / 点差超标时段，追踪依然要工作
   //    —— 否则会出现"已经盈利 300 点了但因为非交易时间 SL 没移到位
   //       然后行情回撤 350 点被止损"的灾难
   g_Common.OnTick();

   // 2. 风控检查（仅用于控制"是否开新仓"）
   if(!g_Common.IsTradingAllowed())
      return;

   // 3. 策略入场逻辑（示例占位，请替换为真实共振/吞没逻辑）
   ENUM_ORDER_TYPE signal = CheckEntrySignal();
   if(signal == ORDER_TYPE_BUY || signal == ORDER_TYPE_SELL)
   {
      // 持仓上限由通用模块统一管理：OpenPosition() 内部按 magic 只统计本 EA 的持仓，
      // 并用 InpMaxPositions + effectiveMaxPos 双重保护门控制（默认 1，第 1 档止盈后可放行第 2 仓）。
      // ⚠️ 不要用全局 PositionsTotal() 判断——它会把其他 EA / 手动单一起算进来，导致本 EA 永不开仓。

      double price = (signal == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // 使用通用模块开仓：自动计算手数、设置止损止盈
      // 之后 A/B 追踪模式由 InpUseTrailingA / InpUseTrailingB 自动接管
      g_Common.OpenPosition(signal, price, InpFixedSLPoints, InpFixedTPPoints);
   }
}

//+------------------------------------------------------------------+
//| 交易事件函数                                                         |
//+------------------------------------------------------------------+
void OnTrade()
{
   g_Common.OnTrade();
}

//+------------------------------------------------------------------+
//| 定时器函数                                                           |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_Common.OnTimer();
}

//+------------------------------------------------------------------+
//| 策略入场信号（示例占位）                                             |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE CheckEntrySignal()
{
   double ema[1], ma[1];
   if(CopyBuffer(g_HandleEMA, 0, 1, 1, ema) <= 0) return WRONG_VALUE;
   if(CopyBuffer(g_HandleMA,  0, 1, 1, ma)  <= 0) return WRONG_VALUE;

   double close[3];
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 3, close) <= 0) return WRONG_VALUE;

   // 示例：EMA 上穿 MA + 吞没 K 线（真实逻辑请自行完善）
   bool emaBullish = ema[0] > ma[0];
   bool emaBearish = ema[0] < ma[0];

   // 简化吞没判断：当前K线完全包含前一根K线（仅示例）
   bool bullishEngulfing = (close[2] > close[1]) && (close[0] > close[2]);
   bool bearishEngulfing = (close[2] < close[1]) && (close[0] < close[2]);

   if(emaBullish && bullishEngulfing)
      return ORDER_TYPE_BUY;
   if(emaBearish && bearishEngulfing)
      return ORDER_TYPE_SELL;

   return WRONG_VALUE;
}
