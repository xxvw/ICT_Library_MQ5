#property strict
#include "TestHarness.mqh"
#include <SMC/Internal/HistoryContext.mqh>

bool HistoryWait(const string symbol,const SmcConfig &config,SmcHistoryContext &context,
                 const bool requireCompanion = false)
  {
   for(int attempt=0;attempt<20;attempt++)
     {
      if(SmcAcquireHistory(symbol,PERIOD_M1,config,context) && context.minutesOK &&
         (!requireCompanion || ArraySize(context.companion)>0)) return true;
      Sleep(50);
     }
   return false;
  }

void OnStart()
  {
   TestBegin("history-context");
   string symbol="SMC_HISTORY_FIXTURE",companion="SMC_HISTORY_COMPANION";
   TestAssert(CustomSymbolCreate(symbol,"SMCTests","EURUSD"),"create primary custom symbol");
   TestAssert(CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.01),"primary point metadata");
   TestAssert(CustomSymbolSetDouble(symbol,SYMBOL_TRADE_TICK_SIZE,0.01),"primary tick metadata");
   TestAssert(CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,2),"primary digit metadata");
   TestAssert(SymbolSelect(symbol,true),"select primary fixture");
   SmcConfig config;
   config.SetDefaults(); config.enableCalendar=false; config.enablePO3=false;
   SmcHistoryContext context;
   TestAssert(!SmcAcquireHistory(symbol,PERIOD_M1,config,context),"missing primary fails acquisition");
   TestAssert(context.asOf==0 && ArraySize(context.shared)==0 && ArraySize(context.closed)==0 && !context.minutesOK,
              "failed acquisition exposes no evaluation context");
   MqlRates rates[];
   ArrayResize(rates,4320); ZeroMemory(rates);
   for(int i=0;i<ArraySize(rates);i++)
     {
      rates[i].time=D'2026.01.05 00:00'+60*i;
      rates[i].open=100; rates[i].close=101; rates[i].high=102; rates[i].low=99;
      rates[i].tick_volume=10;
     }
   TestEqual(CustomRatesUpdate(symbol,rates),4320,"install complete synthetic M1 history");
   TestAssert(HistoryWait(symbol,config,context),"synchronized primary and M1 acquire");
   int sharedCount=ArraySize(context.shared),closedCount=ArraySize(context.closed);
   TestAssert(sharedCount>config.lookbackBars && closedCount==sharedCount-1,"warmup plus one forming sentinel");
   TestAssert(!ArrayGetAsSeries(context.shared) && !ArrayGetAsSeries(context.closed) &&
              !ArrayGetAsSeries(context.minutes),"all evaluation arrays chronological");
   if(closedCount>0 && sharedCount>0)
     {
      TestEqual(context.shared[sharedCount-1].time,rates[4319].time,"shared context includes forming candle");
      TestEqual(context.closed[closedCount-1].time,rates[4318].time,"closed context excludes forming candle");
      TestEqual(context.asOf,rates[4319].time,"watermark closes latest confirmed candle");
      TestEqual(context.shared[0].time,context.closed[0].time,"both primary views share start");
     }
   TestAssert(context.minutesOK && context.minuteStart<context.asOf,"M1 coverage available");
   int minuteCount=ArraySize(context.minutes);
   if(minuteCount>0)
     {
      TestEqual(context.minutes[0].time,context.minuteStart,"M1 coverage begins at requested day boundary");
      TestEqual(context.minutes[minuteCount-1].time+60,context.asOf,"M1 coverage ends at watermark");
     }
   TestAssert(ArraySize(context.daily)==0 && ArraySize(context.weekly)==0 && ArraySize(context.companion)==0,
              "disabled optional requests have empty arrays");
   TestAssert(context.tick==0.01 && context.point==0.01 && context.digits==2 && context.pip==0.01 &&
              context.companionTick==context.tick,"captured price increments retain legacy pip convention");
   datetime originalAsOf=context.asOf;
   MqlRates forming[];
   ArrayResize(forming,1); forming[0]=rates[4319]; forming[0].high=999; forming[0].close=888;
   TestEqual(CustomRatesUpdate(symbol,forming),1,"change forming price only");
   TestAssert(HistoryWait(symbol,config,context),"forming change reacquires");
   TestEqual(context.asOf,originalAsOf,"forming change retains watermark");
   if(ArraySize(context.closed)>0)
      TestAssert(context.closed[ArraySize(context.closed)-1].close==101,"forming change cannot enter closed context");

   config.enablePO3=true;
   TestAssert(SmcAcquireHistory(symbol,PERIOD_M1,config,context),"PO3 primary horizon acquires");
   TestAssert(!context.minutesOK && ArraySize(context.minutes)==0,
              "PO3 extended horizon exposes insufficient M1 coverage separately");
   if(ArraySize(context.closed)>0)
      TestAssert(context.asOf-context.closed[0].time>=172800,"PO3 includes at least two days of primary context");
   config.enablePO3=false;
   config.enableCalendar=true;
   TestAssert(HistoryWait(symbol,config,context),"calendar shortage does not fail primary acquisition");
   TestAssert(ArraySize(context.daily)==0 && ArraySize(context.weekly)==0,"incomplete calendar coverage discarded");
   config.enableCalendar=false;
   config.smtSymbol="SMC_HISTORY_ABSENT";
   TestAssert(HistoryWait(symbol,config,context),"absent comparison leaves primary usable");
   TestEqual(ArraySize(context.companion),0,"absent comparison cannot retain bars");

   TestAssert(CustomSymbolCreate(companion,"SMCTests","EURUSD"),"create comparison fixture");
   TestAssert(CustomSymbolSetDouble(companion,SYMBOL_TRADE_TICK_SIZE,0.02),"comparison has distinct tick size");
   TestAssert(SymbolSelect(companion,true),"select comparison fixture");
   TestEqual(CustomRatesUpdate(companion,rates),4320,"install comparison history");
   config.smtSymbol=companion;
   TestAssert(HistoryWait(symbol,config,context,true),"comparison synchronized with closed primary");
   TestAssert(context.companionTick==0.02,"comparison uses its own tick metadata");
   int comparisonCount=ArraySize(context.companion);
   if(comparisonCount>0 && ArraySize(context.closed)>0)
     {
      TestEqual(context.companion[0].time,context.closed[0].time,"comparison starts at primary start");
      TestAssert(context.companion[comparisonCount-1].time<context.asOf,"comparison excludes forming candle");
     }
   config.smtSymbol="";
   TestAssert(HistoryWait(symbol,config,context),"context reused with comparison disabled");
   TestEqual(ArraySize(context.companion),0,"disabling comparison clears previous history");
   TestAssert(context.companionTick==context.tick,"disabling comparison restores primary tick default");

   MqlRates synchronized[];
   ArrayResize(synchronized,1); synchronized[0]=rates[0]; ArraySetAsSeries(synchronized,true);
   TestAssert(!SmcCopySynchronized(symbol,PERIOD_M1,originalAsOf,originalAsOf-1,synchronized),"reversed time range rejected");
   TestAssert(ArraySize(synchronized)==0 && !ArrayGetAsSeries(synchronized),"failed range resets caller array");
   TestAssert(CustomRatesDelete(symbol,0,D'2030.01.01')>0,"remove successful primary history");
   TestAssert(!SmcAcquireHistory(symbol,PERIOD_M1,config,context),"lost primary fails reused context");
   TestAssert(ArraySize(context.shared)==0 && ArraySize(context.closed)==0 && ArraySize(context.minutes)==0 &&
              ArraySize(context.companion)==0 && context.asOf==0 && context.tick==0 && !context.minutesOK,
              "lost primary clears all previous acquisition state");
   TestFinish();
  }
