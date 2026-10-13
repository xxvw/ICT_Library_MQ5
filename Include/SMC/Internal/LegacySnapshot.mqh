// Internal adapters: detection and terminal acquisition stay outside this layer.
#ifndef __SMC_INTERNAL_LEGACY_SNAPSHOT_MQH__
#define __SMC_INTERNAL_LEGACY_SNAPSHOT_MQH__

#include "../Core/SmcSnapshot.mqh"
#include "../SwingPoints.mqh"
#include "../MarketStructure.mqh"
#include "../OrderBlock.mqh"
#include "../FairValueGap.mqh"
#include "../Liquidity.mqh"
#include "../PremiumDiscount.mqh"
#include "../OptimalTradeEntry.mqh"
#include "../KillZone.mqh"
#include "../BreakerBlock.mqh"

struct SmcLegacyRecordContext
  {
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   datetime asOf;
  };

void SmcSetLegacyStatus(SmcSnapshot &snapshot,const ENUM_SMC_CONCEPT concept,
                       const bool ready,const string reason = "Upstream history unavailable")
  {
   SmcSetModuleStatus(snapshot,concept,ready ? SMC_STATUS_READY : SMC_STATUS_NOT_READY,
                      ready ? snapshot.asOf : 0,false,ready ? "" : reason);
  }

void SmcLegacyZoneRecord(const SmcZone &zone,const ENUM_SMC_CONCEPT concept,
                         const SmcLegacyRecordContext &context,SmcRecord &record)
  {
   record.Init();
   record.concept = concept;
   record.sourceTime = zone.formationTime;
   record.confirmedAt = SmcBarClosedAt(zone.confirmedTime,context.timeframe);
   record.updatedAt = zone.brokenTime > 0 ? SmcBarClosedAt(zone.brokenTime,context.timeframe) : context.asOf;
   record.direction = zone.isBullish ? 1 : -1;
   record.lower = zone.bottomPrice;
   record.upper = zone.topPrice;
   record.active = zone.IsActive();
   record.strength = zone.score;
   if(zone.state == ZONE_BROKEN) record.state = "BROKEN";
   else if(zone.state == ZONE_MITIGATED) record.state = "MITIGATED";
   else if(zone.state == ZONE_TESTED) record.state = "TESTED";
   if(zone.isExpired) record.reason = "expired";
   else if(zone.state == ZONE_BROKEN) record.reason = "close_through";
   if(concept == ICT_BREAKER)
      record.relatedId = SmcRecordId(ICT_ORDER_BLOCK,context.symbol,context.timeframe,zone.sourceFormationTime,-record.direction);
   record.id = SmcRecordId(concept,context.symbol,context.timeframe,record.sourceTime,record.direction,record.relatedId);
  }

void SmcLegacySwingRecord(const SmcSwingPoint &point,const bool highSide,
                         const SmcLegacyRecordContext &context,SmcRecord &record)
  {
   record.Init();
   record.concept = highSide ? ICT_SWING_HIGH : ICT_SWING_LOW;
   record.direction = highSide ? -1 : 1;
   record.sourceTime = point.time;
   record.confirmedAt = SmcBarClosedAt(point.confirmedTime,context.timeframe);
   record.updatedAt = context.asOf;
   record.lower = point.price;
   record.upper = point.price;
   record.strength = point.strength;
   record.state = point.isBroken ? "BROKEN" : "CONFIRMED";
   record.active = point.isValid && !point.isBroken;
   record.id = SmcRecordId(record.concept,context.symbol,context.timeframe,record.sourceTime,record.direction);
  }

void SmcLegacyBreakRecord(const SmcStructureBreak &brk,
                         const SmcLegacyRecordContext &context,SmcRecord &record)
  {
   record.Init();
   record.concept = brk.IsBOS() ? ICT_BOS : ICT_CHOCH;
   record.direction = brk.isBullish ? 1 : -1;
   record.sourceTime = brk.time;
   record.confirmedAt = SmcBarClosedAt(brk.time,context.timeframe);
   record.updatedAt = record.confirmedAt;
   record.lower = MathMin(brk.swingPrice,brk.breakPrice);
   record.upper = MathMax(brk.swingPrice,brk.breakPrice);
   record.referencePrice = brk.swingPrice;
   record.state = "CONFIRMED";
   record.active = false;
   record.relatedId = SmcRecordId(brk.isBullish ? ICT_SWING_HIGH : ICT_SWING_LOW,context.symbol,
      context.timeframe,brk.swingTime,-record.direction);
   record.id = SmcRecordId(record.concept,context.symbol,context.timeframe,record.sourceTime,record.direction,record.relatedId);
  }

void SmcLegacyLiquidityRecord(const SmcLiquidityLevel &level,const datetime confirmedTime,
                         const SmcLegacyRecordContext &context,SmcRecord &record)
  {
   record.Init();
   record.concept = ICT_LIQUIDITY;
   record.sourceTime = level.firstTime;
   record.confirmedAt = SmcBarClosedAt(confirmedTime,context.timeframe);
   record.updatedAt = level.isSweep ? SmcBarClosedAt(level.sweepTime,context.timeframe) : context.asOf;
   record.direction = level.IsHighSide() ? -1 : 1;
   record.lower = level.price;
   record.upper = level.price;
   record.strength = level.touchCount;
   record.state = level.isSweep ? "SWEPT" : "ACTIVE";
   record.active = level.isValid && !level.isSweep;
   record.id = SmcRecordId(ICT_LIQUIDITY,context.symbol,context.timeframe,record.sourceTime,record.direction);
  }

void SmcLegacyRangeRecord(const SmcSwingPoint &high,const SmcSwingPoint &low,
                         const double lower,const double upper,const double equilibrium,
                         const SmcLegacyRecordContext &context,SmcRecord &record)
  {
   record.Init();
   record.concept = ICT_PREMIUM_DISCOUNT;
   record.sourceTime = (datetime)MathMax((long)high.time,(long)low.time);
   record.confirmedAt = SmcBarClosedAt((datetime)MathMax((long)high.confirmedTime,(long)low.confirmedTime),context.timeframe);
   record.updatedAt = context.asOf;
   record.lower = lower;
   record.upper = upper;
   record.referencePrice = equilibrium;
   record.state = "ACTIVE";
   record.relatedId = SmcRecordId(ICT_SWING_HIGH,context.symbol,context.timeframe,high.time,-1);
   record.secondaryId = SmcRecordId(ICT_SWING_LOW,context.symbol,context.timeframe,low.time,1);
   record.id = SmcRecordId(ICT_PREMIUM_DISCOUNT,context.symbol,context.timeframe,record.sourceTime,0,
      record.relatedId+"|"+record.secondaryId);
  }

void SmcLegacyOTERecord(const SmcRecord &range,const SmcOTEZone &ote,
                         const SmcLegacyRecordContext &context,SmcRecord &record)
  {
   record = range;
   record.concept = ICT_OTE;
   record.direction = ote.isBullish ? 1 : -1;
   record.lower = MathMin(ote.fibLevel618,ote.fibLevel786);
   record.upper = MathMax(ote.fibLevel618,ote.fibLevel786);
   record.referencePrice = ote.fibLevel705;
   record.id = SmcRecordId(ICT_OTE,context.symbol,context.timeframe,record.sourceTime,record.direction,
      record.relatedId+"|"+record.secondaryId);
  }

void SmcLegacySessionRecord(const SmcSessionInfo &session,const datetime start,const datetime end,const string name,
                         const SmcLegacyRecordContext &context,SmcRecord &record)
  {
   record.Init();
   record.concept = ICT_KILL_ZONE;
   record.sourceTime = start;
   record.periodStart = start;
   record.periodEnd = end;
   record.confirmedAt = end <= context.asOf ? end : start+60;
   record.updatedAt = (datetime)MathMin((long)end,(long)context.asOf);
   record.lower = session.sessionLow;
   record.upper = session.sessionHigh;
   record.referencePrice = session.sessionOpen;
   record.state = session.isActive ? "FORMING" : "COMPLETE";
   record.active = session.isActive;
   record.id = SmcRecordId(ICT_KILL_ZONE,context.symbol,context.timeframe,start,0,name);
  }

void SmcAppendLegacySnapshot(SmcSnapshot &snapshot,const bool legacyTime,
                             CSmcSwingPoints *swing,CSmcMarketStructure *structure,
                             CSmcOrderBlock *ob,CSmcFairValueGap *fvg,CSmcLiquidity *liquidity,
                             CSmcPremiumDiscount *pd,CSmcOptimalTradeEntry *ote,
                             CSmcKillZone *kz,CSmcBreakerBlock *breaker,
                             const bool swingOK,const bool structureOK,const bool obOK,
                             const bool fvgOK,const bool liquidityOK,const bool pdOK,
                             const bool oteOK,const bool kzOK,const bool breakerOK)
  {
   SmcLegacyRecordContext context;
   context.symbol = snapshot.symbol;
   context.timeframe = snapshot.timeframe;
   context.asOf = snapshot.asOf;
   SmcSetLegacyStatus(snapshot,ICT_SWING_HIGH,swingOK);
   SmcSetLegacyStatus(snapshot,ICT_SWING_LOW,swingOK);
   if(swingOK)
      for(int side = 0; side < 2; side++)
        {
         int count = side == 0 ? swing.GetHighCount() : swing.GetLowCount();
         for(int i = 0; i < count; i++)
           {
            SmcSwingPoint point;
            bool valid = side == 0 ? swing.GetSwingHigh(i,point) : swing.GetSwingLow(i,point);
            if(!valid) continue;
            SmcRecord record;
            SmcLegacySwingRecord(point,side == 0,context,record);
            SmcAppendRecord(snapshot,record);
           }
        }
   SmcSetLegacyStatus(snapshot,ICT_BOS,structureOK);
   SmcSetLegacyStatus(snapshot,ICT_CHOCH,structureOK);
   if(structureOK)
      for(int i = 0; i < structure.GetBreakCount(); i++)
        {
         SmcStructureBreak brk;
         if(!structure.GetBreak(i,brk) || !brk.isValid) continue;
         SmcRecord record;
         SmcLegacyBreakRecord(brk,context,record);
         SmcAppendRecord(snapshot,record);
        }
   SmcSetLegacyStatus(snapshot,ICT_ORDER_BLOCK,obOK);
   SmcSetLegacyStatus(snapshot,ICT_FVG,fvgOK);
   for(int kind = 0; kind < 2; kind++)
     {
      if((kind == 0 && !obOK) || (kind == 1 && !fvgOK)) continue;
      for(int side = 0; side < 2; side++)
        {
         int count = kind == 0 ? (side == 0 ? ob.GetBullishCount() : ob.GetBearishCount()) :
                                  (side == 0 ? fvg.GetBullishCount() : fvg.GetBearishCount());
         for(int i = 0; i < count; i++)
           {
            SmcZone zone;
            bool valid = kind == 0 ? (side == 0 ? ob.GetBullishOB(i,zone) : ob.GetBearishOB(i,zone)) :
                                     (side == 0 ? fvg.GetBullishFVG(i,zone) : fvg.GetBearishFVG(i,zone));
            if(valid)
              {
               SmcRecord record;
               SmcLegacyZoneRecord(zone,kind == 0 ? ICT_ORDER_BLOCK : ICT_FVG,context,record);
               SmcAppendRecord(snapshot,record);
              }
           }
        }
     }
   SmcSetLegacyStatus(snapshot,ICT_BREAKER,breakerOK);
   if(breakerOK)
      for(int i = 0; i < breaker.GetBreakerCount(); i++)
        {
         SmcZone zone;
         if(breaker.GetBreakerBlock(i,zone))
           {
            SmcRecord record;
            SmcLegacyZoneRecord(zone,ICT_BREAKER,context,record);
            SmcAppendRecord(snapshot,record);
           }
        }
   SmcSetLegacyStatus(snapshot,ICT_LIQUIDITY,liquidityOK);
   if(liquidityOK)
      for(int i = 0; i < liquidity.GetLevelCount(); i++)
        {
         SmcLiquidityLevel level;
         if(!liquidity.GetLevel(i,level)) continue;
         SmcRecord record;
         SmcLegacyLiquidityRecord(level,liquidity.GetLevelConfirmedTime(i),context,record);
         SmcAppendRecord(snapshot,record);
        }
   SmcSwingPoint high,low;
   bool rangeOK = swingOK && swing.GetSwingHigh(0,high) && swing.GetSwingLow(0,low) && high.price > low.price;
   SmcSetLegacyStatus(snapshot,ICT_PREMIUM_DISCOUNT,pdOK && rangeOK,"Confirmed high and low are required");
   SmcSetLegacyStatus(snapshot,ICT_OTE,oteOK && rangeOK,"Confirmed high and low are required");
   if(rangeOK)
     {
      SmcRecord record;
      SmcLegacyRangeRecord(high,low,pd.GetSwingLow(),pd.GetSwingHigh(),pd.GetEquilibrium(),context,record);
      if(pdOK) SmcAppendRecord(snapshot,record);
      SmcOTEZone oteZone;
      if(oteOK && ote.GetOTEZone(oteZone))
        {
         SmcRecord range = record;
         SmcLegacyOTERecord(range,oteZone,context,record);
         SmcAppendRecord(snapshot,record);
        }
     }
   SmcSetLegacyStatus(snapshot,ICT_KILL_ZONE,kzOK);
   if(kzOK)
      for(int i = 1; i <= 3; i++)
        {
         SmcSessionInfo session;
         datetime start,end;
         ENUM_SMC_SESSION kind = (ENUM_SMC_SESSION)i;
         if(!kz.GetSessionInfo(kind,session) || !kz.GetSessionBounds(kind,start,end)) continue;
         string name = legacyTime ? kz.GetSessionName(kind) : snapshot.config.sessions[i-1].name;
         SmcRecord record;
         SmcLegacySessionRecord(session,start,end,name,context,record);
         SmcAppendRecord(snapshot,record);
        }
  }

#endif
