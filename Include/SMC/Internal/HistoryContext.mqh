// Internal terminal acquisition; callers supply a validated config and timeframe.
#ifndef __SMC_INTERNAL_HISTORY_CONTEXT_MQH__
#define __SMC_INTERNAL_HISTORY_CONTEXT_MQH__

#include "../Core/SmcSnapshot.mqh"

struct SmcHistoryContext
  {
   MqlRates shared[];    // Chronological, with the forming sentinel at the end.
   MqlRates closed[];    // Chronological, confirmed primary candles only.
   MqlRates daily[];     // Calendar arrays may include the current period open.
   MqlRates weekly[];
   MqlRates minutes[];
   MqlRates companion[];
   datetime asOf;
   datetime minuteStart;
   bool minutesOK;
   double tick;
   double point;
   int digits;
   double pip;
   double companionTick;

   void Reset()
     {
      ArrayFree(shared); ArraySetAsSeries(shared,false);
      ArrayFree(closed); ArraySetAsSeries(closed,false);
      ArrayFree(daily); ArraySetAsSeries(daily,false);
      ArrayFree(weekly); ArraySetAsSeries(weekly,false);
      ArrayFree(minutes); ArraySetAsSeries(minutes,false);
      ArrayFree(companion); ArraySetAsSeries(companion,false);
      asOf = 0;
      minuteStart = 0;
      minutesOK = false;
      tick = 0;
      point = 0;
      digits = 0;
      pip = 0;
      companionTick = 0;
     }
  };

bool SmcCopySynchronized(const string symbol,const ENUM_TIMEFRAMES timeframe,
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

// A false result means primary acquisition failed. Optional history failures
// stay in the context so the evaluator can report per-concept readiness.
bool SmcAcquireHistory(const string symbol,const ENUM_TIMEFRAMES timeframe,
                       const SmcConfig &config,SmcHistoryContext &context)
  {
   context.Reset();
   int requested = config.lookbackBars+MathMax(config.WarmupBars(),23)+1;
   if(config.enablePO3)
      requested = MathMax(requested,(int)MathCeil(172800.0/PeriodSeconds(timeframe))+config.WarmupBars()+1);
   ArraySetAsSeries(context.shared,false);
   if(CopyRates(symbol,timeframe,0,requested,context.shared) != requested ||
      !SeriesInfoInteger(symbol,timeframe,SERIES_SYNCHRONIZED))
     {
      context.Reset();
      return false;
     }
   ArrayCopy(context.closed,context.shared,0,0,requested-1);
   context.asOf = SmcBarClosedAt(context.closed[requested-2].time,timeframe);
   MqlDateTime parts;
   TimeToStruct(context.closed[0].time,parts);
   parts.hour = 0; parts.min = 0; parts.sec = 0;
   context.minuteStart = StructToTime(parts)-86400;
   context.minutesOK = SmcCopySynchronized(symbol,PERIOD_M1,context.minuteStart,context.asOf-1,context.minutes);
   if(config.enableCalendar)
     {
      SmcCopySynchronized(symbol,PERIOD_D1,context.minuteStart-14*86400,context.asOf,context.daily);
      SmcCopySynchronized(symbol,PERIOD_W1,context.minuteStart-14*86400,context.asOf,context.weekly);
     }
   context.tick = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   context.point = SymbolInfoDouble(symbol,SYMBOL_POINT);
   context.digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   context.pip = context.point*((context.digits == 2 || context.digits == 4) ? 1.0 : 10.0);
   context.companionTick = context.tick;
   if(config.IsSMTEnabled())
     {
      context.companionTick = SymbolInfoDouble(config.smtSymbol,SYMBOL_TRADE_TICK_SIZE);
      if(SymbolSelect(config.smtSymbol,true))
        {
         SmcCopySynchronized(config.smtSymbol,timeframe,context.closed[0].time,context.asOf-1,context.companion);
         context.companionTick = SymbolInfoDouble(config.smtSymbol,SYMBOL_TRADE_TICK_SIZE);
        }
     }
   return true;
  }

#endif
