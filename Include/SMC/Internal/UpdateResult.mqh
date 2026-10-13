// Internal execution results; no module ownership or terminal acquisition.
#ifndef __SMC_INTERNAL_UPDATE_RESULT_MQH__
#define __SMC_INTERNAL_UPDATE_RESULT_MQH__

#include "../Core/IctEngine.mqh"

struct SmcModuleUpdateResult
  {
   bool swingOK;
   bool structureOK;
   bool obOK;
   bool fvgOK;
   bool liquidityOK;
   bool pdOK;
   bool oteOK;
   bool kzOK;
   bool breakerOK;
   bool confluenceOK;
   bool analysisOK;
   string analysisMessage;

   void Reset()
     {
      swingOK = false;
      structureOK = false;
      obOK = false;
      fvgOK = false;
      liquidityOK = false;
      pdOK = false;
      oteOK = false;
      kzOK = false;
      breakerOK = false;
      confluenceOK = false;
      analysisOK = true;
      analysisMessage = "";
     }

   bool AllLegacyReady() const
     {
      return swingOK && structureOK && obOK && fvgOK && liquidityOK &&
             pdOK && oteOK && kzOK && breakerOK;
     }
  };

// Preserve finalization order and diagnostic precedence. The manager gates
// direct Confluence access after this function has determined readiness.
void SmcCompleteManagerSnapshot(SmcSnapshot &snapshot,const MqlRates &closed[],
                                const SmcModuleUpdateResult &result)
  {
   SmcFinalizeSnapshot(snapshot,closed);
   if((!result.confluenceOK || !result.analysisOK) && snapshot.status == SMC_STATUS_READY)
      snapshot.status = SMC_STATUS_PARTIAL;
   if(!result.analysisOK) snapshot.message = result.analysisMessage;
   else if(!result.confluenceOK) snapshot.message = "Confluence requires all legacy modules to be available";
  }

#endif
