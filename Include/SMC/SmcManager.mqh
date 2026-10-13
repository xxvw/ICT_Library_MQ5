//+------------------------------------------------------------------+
//|                                                   SmcManager.mqh |
//|                         SMC/ICT Concepts Library for MQL5        |
//|                         Copyright 2025-2026, SMC_ICT_Library     |
//+------------------------------------------------------------------+
#property copyright "SMC_ICT_Library"
#property version   "1.00"
#property strict

#ifndef __SMC_MANAGER_MQH__
#define __SMC_MANAGER_MQH__

#include "Core/IctEngine.mqh"
#include "Internal/LegacySnapshot.mqh"
#include "SwingPoints.mqh"
#include "MarketStructure.mqh"
#include "OrderBlock.mqh"
#include "FairValueGap.mqh"
#include "Liquidity.mqh"
#include "PremiumDiscount.mqh"
#include "OptimalTradeEntry.mqh"
#include "KillZone.mqh"
#include "BreakerBlock.mqh"
#include "ConfluenceDetector.mqh"
#include "Analysis/CurrencyStrength.mqh"
#include "Analysis/VIXCalculator.mqh"

//+------------------------------------------------------------------+
//| CSmcManager - 全SMCモジュール統合マネージャー                      |
//|                                                                    |
//| 全モジュールを正しい依存関係順に初期化・更新する。                 |
//| 共通SwingPointsインスタンスを共有し、リソース効率を最適化。       |
//+------------------------------------------------------------------+
class CSmcManager
  {
private:
   //--- モジュール
   CSmcSwingPoints       *m_swing;
   CSmcMarketStructure   *m_structure;
   CSmcOrderBlock        *m_ob;
   CSmcFairValueGap      *m_fvg;
   CSmcLiquidity         *m_liquidity;
   CSmcPremiumDiscount   *m_pd;
   CSmcOptimalTradeEntry *m_ote;
   CSmcKillZone          *m_kz;
   CSmcBreakerBlock      *m_breaker;
   CSmcConfluence        *m_confluence;
   CSmcCurrencyStrength  *m_cs;
   CSmcVIXCalculator     *m_vix;

   //--- 状態
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   bool              m_initialized;
   bool              m_enableDraw;

   //--- モジュール有効化フラグ
   bool              m_enableCS;
   bool              m_enableVIX;

   SmcConfig         m_config;
   SmcSnapshot       m_snapshot;
   bool              m_hasSnapshot;
   bool              m_legacyTime;

   void              ReleaseModules();
   bool              InitModules(const string symbol,const ENUM_TIMEFRAMES timeframe,
                                  const SmcConfig &config,const bool legacyTime);
   bool              CopySynchronized(const string symbol,const ENUM_TIMEFRAMES timeframe,
                                       const datetime start,const datetime end,MqlRates &rates[]);

public:
                     CSmcManager();
                    ~CSmcManager();

   //--- 初期化
   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                          const bool enableDraw = false,
                          const bool enableCS = true,
                          const bool enableVIX = true);
   bool              Init(const string symbol,const ENUM_TIMEFRAMES timeframe,const SmcConfig &config);
   bool              Update();
   bool              GetSnapshot(SmcSnapshot &snapshot) const;
   ENUM_SMC_STATUS   GetStatus() const { return m_snapshot.status; }
   void              Clean();

   //--- モジュールアクセサ
   CSmcSwingPoints       *Swing()      { return m_swing; }
   CSmcMarketStructure   *Structure()  { return m_structure; }
   CSmcOrderBlock        *OB()         { return m_ob; }
   CSmcFairValueGap      *FVG()        { return m_fvg; }
   CSmcLiquidity         *Liquidity()  { return m_liquidity; }
   CSmcPremiumDiscount   *PD()         { return m_pd; }
   CSmcOptimalTradeEntry *OTE()        { return m_ote; }
   CSmcKillZone          *KZ()         { return m_kz; }
   CSmcBreakerBlock      *Breaker()    { return m_breaker; }
   CSmcConfluence        *Confluence() { return m_confluence; }
   CSmcCurrencyStrength  *CurrStr()    { return m_cs; }
   CSmcVIXCalculator     *VIX()        { return m_vix; }

   //--- ショートカット
   ENUM_SMC_TREND        GetTrend()     const;
   ENUM_ENTRY_SIGNAL     GetSignal()    const;
   bool                  IsBullish()    const;
   bool                  IsBearish()    const;
   bool                  IsInitialized() const { return m_initialized; }
  };

//+------------------------------------------------------------------+
CSmcManager::CSmcManager()
   : m_swing(NULL)
   , m_structure(NULL)
   , m_ob(NULL)
   , m_fvg(NULL)
   , m_liquidity(NULL)
   , m_pd(NULL)
   , m_ote(NULL)
   , m_kz(NULL)
   , m_breaker(NULL)
   , m_confluence(NULL)
   , m_cs(NULL)
   , m_vix(NULL)
   , m_symbol("")
   , m_timeframe(PERIOD_CURRENT)
   , m_initialized(false)
   , m_enableDraw(false)
   , m_enableCS(true)
   , m_enableVIX(true)
   , m_hasSnapshot(false)
   , m_legacyTime(true)
  {
   m_config.SetDefaults();
   m_snapshot.Reset();
  }

//+------------------------------------------------------------------+
CSmcManager::~CSmcManager()
  {
   ReleaseModules();
  }

//+------------------------------------------------------------------+
void CSmcManager::ReleaseModules()
  {
   Clean();

   if(m_confluence != NULL) { delete m_confluence; m_confluence = NULL; }
   if(m_breaker != NULL)    { delete m_breaker;    m_breaker = NULL; }
   if(m_kz != NULL)         { delete m_kz;         m_kz = NULL; }
   if(m_ote != NULL)        { delete m_ote;        m_ote = NULL; }
   if(m_pd != NULL)         { delete m_pd;         m_pd = NULL; }
   if(m_liquidity != NULL)  { delete m_liquidity;  m_liquidity = NULL; }
   if(m_fvg != NULL)        { delete m_fvg;        m_fvg = NULL; }
   if(m_ob != NULL)         { delete m_ob;         m_ob = NULL; }
   if(m_structure != NULL)  { delete m_structure;  m_structure = NULL; }
   if(m_swing != NULL)      { delete m_swing;      m_swing = NULL; }
   if(m_cs != NULL)         { delete m_cs;         m_cs = NULL; }
   if(m_vix != NULL)        { delete m_vix;        m_vix = NULL; }

   m_initialized = false;
  }

//+------------------------------------------------------------------+
bool CSmcManager::Init(const string symbol,const ENUM_TIMEFRAMES timeframe,
                       const bool enableDraw,const bool enableCS,const bool enableVIX)
  {
   SmcConfig config;
   config.SetDefaults();
   config.enableDraw = enableDraw;
   config.enableCS = enableCS;
   config.enableVIX = enableVIX;
   // Preserve the legacy overload's enabled modules and GMT session behavior.
   config.enableCalendar = false;
   config.enableSMT = false;
   config.enablePO3 = false;
   config.enableDisplacement = false;
   config.enableMSS = false;
   config.enableIFVG = false;
   config.enableBPR = false;
   return InitModules(symbol,timeframe,config,true);
  }

bool CSmcManager::Init(const string symbol,const ENUM_TIMEFRAMES timeframe,const SmcConfig &config)
  {
   return InitModules(symbol,timeframe,config,false);
  }

bool CSmcManager::InitModules(const string symbol,const ENUM_TIMEFRAMES timeframe,
                              const SmcConfig &config,const bool legacyTime)
  {
   ReleaseModules();
   m_hasSnapshot = false;
   m_symbol = (symbol == "" || symbol == "0") ? _Symbol : symbol;
   m_timeframe = timeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : timeframe;
   m_config = config;
   m_legacyTime = legacyTime;
   m_enableDraw = config.enableDraw;
   m_enableCS = config.enableCS;
   m_enableVIX = config.enableVIX;
   string reason;
   if(!config.Validate(reason) || PeriodSeconds(m_timeframe) <= 0)
     {
      if(reason == "") reason = "Invalid timeframe";
      SmcUnavailableSnapshot(m_snapshot,config,m_symbol,m_timeframe,SMC_STATUS_ERROR,reason,true);
      return false;
     }
   SmcUnavailableSnapshot(m_snapshot,config,m_symbol,m_timeframe,SMC_STATUS_NOT_READY,"Update has not run",true);
   const bool enableDraw = config.enableDraw;
   // Legacy OB/FVG probability baselines consume 20 preceding candles.
   const int window = config.lookbackBars+MathMax(config.WarmupBars(),23);

//--- 1. SwingPoints (基盤 - 全モジュールが共有)
   m_swing = new CSmcSwingPoints();
   if(!m_swing.Init(m_symbol, m_timeframe, enableDraw,config.swingStrength,2*window,window))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 2. MarketStructure (SwingPointsを共有)
   m_structure = new CSmcMarketStructure();
   if(!m_structure.Init(m_symbol, m_timeframe, enableDraw, m_swing))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 3. OrderBlock (MarketStructureを共有)
   m_ob = new CSmcOrderBlock();
   if(!m_ob.Init(m_symbol, m_timeframe, enableDraw, m_structure))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 4. FairValueGap (独立)
   m_fvg = new CSmcFairValueGap();
   if(!m_fvg.Init(m_symbol, m_timeframe, enableDraw))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 5. Liquidity (SwingPointsを共有)
   m_liquidity = new CSmcLiquidity();
   if(!m_liquidity.Init(m_symbol, m_timeframe, enableDraw, m_swing))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 6. PremiumDiscount (SwingPointsを共有)
   m_pd = new CSmcPremiumDiscount();
   if(!m_pd.Init(m_symbol, m_timeframe, enableDraw, m_swing))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 7. OptimalTradeEntry (SwingPointsを共有)
   m_ote = new CSmcOptimalTradeEntry();
   if(!m_ote.Init(m_symbol, m_timeframe, enableDraw, m_swing))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 8. KillZone (独立)
   m_kz = new CSmcKillZone();
   if(!m_kz.Init(m_symbol, m_timeframe, enableDraw))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 9. BreakerBlock (OrderBlock/MarketStructureを共有)
   m_breaker = new CSmcBreakerBlock();
   if(!m_breaker.Init(m_symbol, m_timeframe, enableDraw, m_ob, m_structure))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }

//--- 10. Confluence (全モジュール参照)
   m_confluence = new CSmcConfluence();
   if(!m_confluence.Init(m_symbol, m_timeframe, enableDraw))
     {
      ReleaseModules();
      m_snapshot.status = SMC_STATUS_ERROR;
      m_snapshot.message = "Legacy module initialization failed";
      return false;
     }
   m_confluence.SetStructure(m_structure);
   m_confluence.SetOrderBlock(m_ob);
   m_confluence.SetFVG(m_fvg);
   m_confluence.SetLiquidity(m_liquidity);
   m_confluence.SetOTE(m_ote);
   m_confluence.SetKillZone(m_kz);
   m_confluence.SetBreaker(m_breaker);

//--- 11. CurrencyStrength (オプション)
   if(m_enableCS)
     {
      m_cs = new CSmcCurrencyStrength();
      if(!m_cs.Init(m_symbol, m_timeframe, false))
        {
         ReleaseModules();
         return false;
        }
     }

//--- 12. VIXCalculator (オプション)
   if(m_enableVIX)
     {
      m_vix = new CSmcVIXCalculator();
      if(!m_vix.Init(m_symbol, m_timeframe, false))
        {
         ReleaseModules();
         return false;
        }
     }

   m_ob.SetEvaluationLimits(window,2*window);
   m_fvg.SetEvaluationLimits(window,2*window);
   m_structure.SetMaxBreaks(2*window);
   m_liquidity.SetMaxLevels(2*window);
   m_breaker.SetMaxBlocks(2*window);
   m_breaker.SetMaxAge(config.maxZoneAge);
   m_ob.SetMaxAge(config.maxZoneAge);
   m_fvg.SetMaxAge(config.maxZoneAge);
   m_fvg.SetMinSizePips(config.minFvgPips);
   if(!legacyTime)
     {
      m_kz.UseBrokerTime();
      m_kz.SetOverlapEnabled(false);
      for(int i = 0; i < 3; i++)
         m_kz.SetSessionTime((ENUM_SMC_SESSION)(i+1),config.sessions[i].startMinute/60,
                             config.sessions[i].startMinute%60,config.sessions[i].endMinute/60,
                             config.sessions[i].endMinute%60);
     }
   m_initialized = true;
   Print("[SMC Manager] Initialized for ", m_symbol, " ", EnumToString(m_timeframe));
   return true;
  }

//+------------------------------------------------------------------+
//| 全モジュールを正しい依存関係順に更新                               |
//+------------------------------------------------------------------+
bool CSmcManager::CopySynchronized(const string symbol,const ENUM_TIMEFRAMES timeframe,
                                    const datetime start,const datetime end,MqlRates &rates[])
  {
   ArrayResize(rates,0);
   ArraySetAsSeries(rates,false);
   if(end < start || CopyRates(symbol,timeframe,start,end,rates) < 1 ||
      !SeriesInfoInteger(symbol,timeframe,SERIES_SYNCHRONIZED) ||
      (SeriesInfoInteger(symbol,timeframe,SERIES_FIRSTDATE) <= 0 ||
       SeriesInfoInteger(symbol,timeframe,SERIES_FIRSTDATE) > start) ||
      SmcBarClosedAt((datetime)SeriesInfoInteger(symbol,timeframe,SERIES_LASTBAR_DATE),timeframe) < end)
     {
      ArrayResize(rates,0);
      return false;
     }
   return true;
  }

bool CSmcManager::GetSnapshot(SmcSnapshot &snapshot) const
  {
   if(!m_hasSnapshot) return false;
   snapshot = m_snapshot;
   return true;
  }

bool CSmcManager::Update()
  {
   m_hasSnapshot = true;
   // Callers can also access Confluence() directly. Never leave its cached
   // decisions available when an early history/validation failure skips Update.
   if(m_confluence != NULL) m_confluence.InvalidateSignals();
   if(!m_initialized)
     {
      SmcUnavailableSnapshot(m_snapshot,m_config,m_symbol,m_timeframe,SMC_STATUS_ERROR,"Manager is not initialized",true);
      return false;
     }
   int requested = m_config.lookbackBars+MathMax(m_config.WarmupBars(),23)+1;
   if(m_config.enablePO3)
      requested = MathMax(requested,(int)MathCeil(172800.0/PeriodSeconds(m_timeframe))+m_config.WarmupBars()+1);
   MqlRates shared[],closed[],daily[],weekly[],minutes[],companion[];
   ArraySetAsSeries(shared,false);
   if(CopyRates(m_symbol,m_timeframe,0,requested,shared) != requested ||
      !SeriesInfoInteger(m_symbol,m_timeframe,SERIES_SYNCHRONIZED))
     {
      SmcUnavailableSnapshot(m_snapshot,m_config,m_symbol,m_timeframe,SMC_STATUS_NOT_READY,
                             "Primary history is unavailable, unsynchronized or shorter than lookback plus warmup",true);
      return false;
     }
   ArrayCopy(closed,shared,0,0,requested-1);
   datetime asOf = SmcBarClosedAt(closed[requested-2].time,m_timeframe);
   MqlDateTime parts;
   TimeToStruct(closed[0].time,parts);
   parts.hour = 0; parts.min = 0; parts.sec = 0;
   datetime minuteStart = StructToTime(parts)-86400;
   bool minutesOK = CopySynchronized(m_symbol,PERIOD_M1,minuteStart,asOf-1,minutes);
   if(m_config.enableCalendar)
     {
      CopySynchronized(m_symbol,PERIOD_D1,minuteStart-14*86400,asOf,daily);
      CopySynchronized(m_symbol,PERIOD_W1,minuteStart-14*86400,asOf,weekly);
     }
   double tick = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
   double pip = point*((digits == 2 || digits == 4) ? 1.0 : 10.0);
   double companionTick = tick;
   if(m_config.IsSMTEnabled())
     {
      companionTick = SymbolInfoDouble(m_config.smtSymbol,SYMBOL_TRADE_TICK_SIZE);
      if(SymbolSelect(m_config.smtSymbol,true))
        {
         CopySynchronized(m_config.smtSymbol,m_timeframe,closed[0].time,asOf-1,companion);
         companionTick = SymbolInfoDouble(m_config.smtSymbol,SYMBOL_TRADE_TICK_SIZE);
        }
     }
   SmcEvaluateICT(closed,daily,weekly,minutes,companion,m_config,m_symbol,m_timeframe,
                   tick,pip,companionTick,m_snapshot,minutesOK ? minuteStart : 0,minutesOK ? asOf : 0);
   if(m_snapshot.status == SMC_STATUS_ERROR || m_snapshot.asOf == 0)
     {
      for(int i = 0; i <= (int)ICT_BREAKER; i++)
         SmcSetModuleStatus(m_snapshot,(ENUM_SMC_CONCEPT)i,SMC_STATUS_NOT_READY,0,false,"Snapshot evaluation is unavailable");
      return false;
     }

   // Every primary-timeframe module sees the same bars, including the forming
   // sentinel that old APIs address at shift zero. Detector loops exclude it.
   m_swing.SetRates(shared);
   m_structure.SetRates(shared);
   m_ob.SetRates(shared);
   m_fvg.SetRates(shared);
   m_liquidity.SetRates(shared);
   m_pd.SetRates(shared);
   m_ote.SetRates(shared);
   m_kz.SetRates(shared);
   m_breaker.SetRates(shared);
   m_confluence.SetRates(shared);
   m_kz.SetEvaluationTime(asOf);
   bool minuteContext = m_kz.SetMinuteRates(minutes,minutesOK ? minuteStart : 0,minutesOK ? asOf : 0);
   bool swingOK = m_swing.Update();
   bool structureOK = swingOK && m_structure.Update();
   bool obOK = structureOK && m_ob.Update();
   bool fvgOK = m_fvg.Update();
   bool liquidityOK = swingOK && m_liquidity.Update();
   bool pdOK = swingOK && m_pd.Update();
   bool oteOK = swingOK && m_ote.Update();
   bool kzOK = minuteContext && m_kz.Update();
   bool breakerOK = obOK && structureOK && m_breaker.Update();
   bool allLegacy = swingOK && structureOK && obOK && fvgOK && liquidityOK && pdOK && oteOK && kzOK && breakerOK;
   bool confluenceOK = allLegacy && m_confluence.Update();
   bool analysisOK = true;
   string analysisMessage = "";
   if(m_cs != NULL)
     {
      m_cs.SetRates(shared);
      if(!m_cs.Update())
        {
         analysisOK = false;
         analysisMessage = "Currency strength history is unavailable";
        }
     }
   if(m_vix != NULL)
     {
      m_vix.SetRates(shared);
      if(!m_vix.Update())
        {
         analysisOK = false;
         if(analysisMessage != "") analysisMessage += "; ";
         analysisMessage += "VIX calculation is unavailable";
        }
     }
   SmcAppendLegacySnapshot(m_snapshot,m_legacyTime,m_swing,m_structure,m_ob,m_fvg,m_liquidity,
                           m_pd,m_ote,m_kz,m_breaker,swingOK,structureOK,obOK,fvgOK,
                           liquidityOK,pdOK,oteOK,kzOK,breakerOK);
   SmcFinalizeSnapshot(m_snapshot,closed);
   if((!confluenceOK || !analysisOK) && m_snapshot.status == SMC_STATUS_READY)
      m_snapshot.status = SMC_STATUS_PARTIAL;
   if(!analysisOK) m_snapshot.message = analysisMessage;
   else if(!confluenceOK) m_snapshot.message = "Confluence requires all legacy modules to be available";
   if(m_snapshot.status != SMC_STATUS_READY) m_confluence.InvalidateSignals();
   return m_snapshot.status == SMC_STATUS_READY;
  }

//+------------------------------------------------------------------+
void CSmcManager::Clean()
  {
   if(m_swing != NULL)      m_swing.Clean();
   if(m_structure != NULL)  m_structure.Clean();
   if(m_ob != NULL)         m_ob.Clean();
   if(m_fvg != NULL)        m_fvg.Clean();
   if(m_liquidity != NULL)  m_liquidity.Clean();
   if(m_pd != NULL)         m_pd.Clean();
   if(m_ote != NULL)        m_ote.Clean();
   if(m_kz != NULL)         m_kz.Clean();
   if(m_breaker != NULL)    m_breaker.Clean();
   if(m_confluence != NULL) m_confluence.Clean();
   if(m_cs != NULL)         m_cs.Clean();
   if(m_vix != NULL)        m_vix.Clean();
  }

//+------------------------------------------------------------------+
ENUM_SMC_TREND CSmcManager::GetTrend() const
  {
   if(m_structure != NULL)
      return m_structure.GetTrend();
   return SMC_TREND_RANGING;
  }

ENUM_ENTRY_SIGNAL CSmcManager::GetSignal() const
  {
   if(m_hasSnapshot && m_snapshot.status == SMC_STATUS_READY && m_confluence != NULL)
      return m_confluence.GetEntrySignal();
   return SIGNAL_WAIT;
  }

bool CSmcManager::IsBullish() const
  {
   return GetTrend() == SMC_TREND_BULLISH;
  }

bool CSmcManager::IsBearish() const
  {
   return GetTrend() == SMC_TREND_BEARISH;
  }

#endif // __SMC_MANAGER_MQH__
//+------------------------------------------------------------------+
