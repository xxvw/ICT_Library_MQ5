#property strict
#include "TestHarness.mqh"
#include <SMC/Internal/LegacySnapshot.mqh>

void OnStart()
  {
   TestBegin("legacy-snapshot-adapter");
   SmcLegacyRecordContext context;
   context.symbol="FIXTURE|symbol";
   context.timeframe=PERIOD_M5;
   context.asOf=D'2026.01.05 12:00';
   SmcRecord record;
   SmcZone zone;
   zone.Init();
   zone.formationTime=D'2026.01.05 09:00';
   zone.confirmedTime=D'2026.01.05 09:10';
   zone.topPrice=105; zone.bottomPrice=100;
   zone.isBullish=true; zone.isValid=true; zone.score=0.75;
   SmcLegacyZoneRecord(zone,ICT_ORDER_BLOCK,context,record);
   TestAssert(record.state=="FRESH" && record.active,"fresh zone lifecycle");
   TestEqual(record.confirmedAt,D'2026.01.05 09:15',"zone confirmation closes M5 candle");
   TestEqual(record.updatedAt,context.asOf,"active zone uses evaluation watermark");
   TestAssert(record.lower==100 && record.upper==105 && record.strength==0.75,"zone geometry and score");
   string originalId=record.id;
   zone.state=ZONE_TESTED;
   SmcLegacyZoneRecord(zone,ICT_ORDER_BLOCK,context,record);
   TestAssert(record.state=="TESTED" && record.id==originalId,"testing retains zone identity");
   zone.state=ZONE_MITIGATED;
   SmcLegacyZoneRecord(zone,ICT_ORDER_BLOCK,context,record);
   TestAssert(record.state=="MITIGATED" && record.active,"mitigated active zone");
   zone.state=ZONE_BROKEN; zone.brokenTime=D'2026.01.05 10:00';
   SmcLegacyZoneRecord(zone,ICT_ORDER_BLOCK,context,record);
   TestAssert(record.state=="BROKEN" && !record.active && record.reason=="close_through","broken zone lifecycle");
   TestEqual(record.updatedAt,D'2026.01.05 10:05',"break update closes M5 candle");
   TestAssert(record.id==originalId,"break retains zone identity");
   zone.isExpired=true;
   SmcLegacyZoneRecord(zone,ICT_ORDER_BLOCK,context,record);
   TestAssert(record.reason=="expired","expiry reason precedes price break");
   zone.sourceFormationTime=D'2026.01.05 08:00';
   zone.isBullish=false;
   SmcLegacyZoneRecord(zone,ICT_BREAKER,context,record);
   TestAssert(record.relatedId==SmcRecordId(ICT_ORDER_BLOCK,context.symbol,PERIOD_M5,zone.sourceFormationTime,1),
              "breaker relates to opposite-direction parent OB");
   TestAssert(record.id==SmcRecordId(ICT_BREAKER,context.symbol,PERIOD_M5,zone.formationTime,-1,record.relatedId),
              "breaker identity includes parent");
   SmcLegacyZoneRecord(zone,ICT_FVG,context,record);
   TestAssert(record.relatedId=="" && record.secondaryId=="" && record.periodStart==0 && record.comparisonPrice==0,
              "reused output resets unrelated fields");

   SmcSwingPoint high,low;
   high.Init(); low.Init();
   high.time=D'2026.01.05 09:00'; high.confirmedTime=D'2026.01.05 09:25';
   high.price=110; high.strength=5; high.isValid=true;
   low.time=D'2026.01.05 09:10'; low.confirmedTime=D'2026.01.05 09:35';
   low.price=90; low.strength=5; low.isValid=true;
   SmcLegacySwingRecord(high,true,context,record);
   TestAssert(record.concept==ICT_SWING_HIGH && record.direction==-1 && record.state=="CONFIRMED" && record.active,
              "confirmed high direction and lifecycle");
   TestEqual(record.confirmedAt,D'2026.01.05 09:30',"swing closes confirmation candle");
   high.isBroken=true;
   SmcLegacySwingRecord(high,true,context,record);
   TestAssert(record.state=="BROKEN" && !record.active,"broken swing inactive");
   SmcLegacySwingRecord(low,false,context,record);
   TestAssert(record.concept==ICT_SWING_LOW && record.direction==1 && record.lower==90 && record.upper==90,
              "low is a bullish point record");

   SmcStructureBreak brk;
   brk.Init(); brk.type=STRUCT_BOS; brk.isBullish=true;
   brk.time=D'2026.01.05 10:00'; brk.swingTime=high.time;
   brk.swingPrice=110; brk.breakPrice=112;
   SmcLegacyBreakRecord(brk,context,record);
   TestAssert(record.concept==ICT_BOS && record.direction==1 && !record.active && record.state=="CONFIRMED",
              "BOS event record");
   TestAssert(record.lower==110 && record.upper==112 && record.referencePrice==110,"break geometry");
   TestEqual(record.updatedAt,D'2026.01.05 10:05',"break update equals confirmation");
   TestAssert(record.relatedId==SmcRecordId(ICT_SWING_HIGH,context.symbol,PERIOD_M5,high.time,-1),"bullish BOS parent");
   brk.type=STRUCT_CHOCH; brk.isBullish=false; brk.swingPrice=90; brk.breakPrice=88; brk.swingTime=low.time;
   SmcLegacyBreakRecord(brk,context,record);
   TestAssert(record.concept==ICT_CHOCH && record.lower==88 && record.upper==90,"bearish CHoCH geometry");
   TestAssert(record.relatedId==SmcRecordId(ICT_SWING_LOW,context.symbol,PERIOD_M5,low.time,1),"bearish CHoCH parent");

   SmcLiquidityLevel level;
   level.Init(); level.firstTime=high.time; level.price=110; level.touchCount=3; level.isValid=true;
   SmcLegacyLiquidityRecord(level,high.confirmedTime,context,record);
   TestAssert(record.state=="ACTIVE" && record.active && record.direction==-1 && record.strength==3,"high-side liquidity");
   TestEqual(record.updatedAt,context.asOf,"unswept liquidity uses watermark");
   level.isSweep=true; level.sweepTime=brk.time; level.type=LIQ_SWEEP_LOW;
   SmcLegacyLiquidityRecord(level,low.confirmedTime,context,record);
   TestAssert(record.state=="SWEPT" && !record.active && record.direction==1,"low-side sweep");
   TestEqual(record.updatedAt,D'2026.01.05 10:05',"sweep candle close timestamp");

   SmcLegacyRangeRecord(high,low,90,110,100,context,record);
   TestAssert(record.concept==ICT_PREMIUM_DISCOUNT && record.direction==0 && record.state=="ACTIVE","range lifecycle");
   TestEqual(record.sourceTime,low.time,"range source is later pivot");
   TestEqual(record.confirmedAt,D'2026.01.05 09:40',"range closes later confirmation candle");
   TestAssert(record.referencePrice==100 && record.relatedId!="" && record.secondaryId!="","range equilibrium and parents");
   SmcRecord range=record;
   SmcOTEZone ote;
   ote.Init(); ote.isBullish=false;
   ote.fibLevel618=105; ote.fibLevel786=103; ote.fibLevel705=104;
   SmcLegacyOTERecord(range,ote,context,record);
   TestAssert(record.concept==ICT_OTE && record.direction==-1 && record.lower==103 && record.upper==105 &&
              record.referencePrice==104,"OTE normalizes reversed fib prices");
   TestAssert(record.relatedId==range.relatedId && record.secondaryId==range.secondaryId &&
              record.confirmedAt==range.confirmedAt && record.updatedAt==range.updatedAt,"OTE retains range context");
   TestAssert(range.concept==ICT_PREMIUM_DISCOUNT && range.referencePrice==100,"OTE does not mutate input range");

   SmcSessionInfo session;
   session.Init(); session.sessionLow=90; session.sessionHigh=110; session.sessionOpen=100; session.isActive=true;
   datetime start=D'2026.01.05 11:00',end=D'2026.01.05 13:00';
   SmcLegacySessionRecord(session,start,end,"custom-session",context,record);
   TestAssert(record.state=="FORMING" && record.active && record.periodStart==start && record.periodEnd==end,"forming session bounds");
   TestEqual(record.confirmedAt,start+60,"forming session confirms first minute");
   TestEqual(record.updatedAt,context.asOf,"forming session watermark");
   session.isActive=false; context.asOf=end+60;
   SmcLegacySessionRecord(session,start,end,"custom-session",context,record);
   TestAssert(record.state=="COMPLETE" && !record.active && record.referencePrice==100,"completed session");
   TestEqual(record.confirmedAt,end,"completed session confirms at end");
   TestEqual(record.updatedAt,end,"completed session updates at end");
   TestAssert(record.id==SmcRecordId(ICT_KILL_ZONE,context.symbol,PERIOD_M5,start,0,"custom-session"),"session name in identity");

   SmcSnapshot snapshot;
   snapshot.Reset(); snapshot.asOf=context.asOf;
   SmcSetLegacyStatus(snapshot,ICT_FVG,false);
   TestAssert(snapshot.modules[0].status==SMC_STATUS_NOT_READY && snapshot.modules[0].asOf==0 &&
              snapshot.modules[0].message=="Upstream history unavailable","default unavailable diagnostic");
   SmcSetLegacyStatus(snapshot,ICT_FVG,true);
   TestAssert(snapshot.modules[0].status==SMC_STATUS_READY && snapshot.modules[0].asOf==context.asOf &&
              snapshot.modules[0].message=="","ready clears diagnostic");
   snapshot.Reset(); snapshot.asOf=context.asOf;
   SmcModuleUpdateResult unavailable;
   unavailable.Reset();
   SmcAppendLegacySnapshot(snapshot,false,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,unavailable);
   TestEqual(ArraySize(snapshot.records),0,"unavailable execution cannot emit legacy records");
   TestEqual(ArraySize(snapshot.modules),(int)ICT_BREAKER+1,"every legacy concept gets availability");
   for(int i=0;i<ArraySize(snapshot.modules);i++)
      TestAssert(snapshot.modules[i].status==SMC_STATUS_NOT_READY && snapshot.modules[i].asOf==0,
                 "unavailable execution cannot publish ready module watermark");
   TestFinish();
  }
