# MQL5 core architecture

[Documentation](README.md) · [Snapshot API](SNAPSHOT_API.md) · [Development](DEVELOPMENT.md)

This English guide is authoritative for the manager's current internal structure. The [retained Japanese architecture guide](ARCHITECTURE.md) describes the original module hierarchy.

## Public contract and ownership

`CSmcManager` remains the integration facade. Both `Init()` overloads, `Update()`, `Clean()`, snapshot/status access, module getters, and signal/trend shortcuts keep their existing signatures and include paths. `SmcConfig`, typed snapshots, JSON, and CSV contracts are unchanged. Headers under `Include/SMC/Internal/` support the implementation and are not an additional supported integration API.

The manager owns all module instances. Swing points are shared with structure, liquidity, premium/discount, and OTE; structure feeds order blocks; order blocks and structure feed breaker blocks. Confluence references the relevant existing instances. Getter-returned pointers are borrowed: callers must not delete them or retain them across another `Init()` or manager destruction.

Initialization first releases the previous graph, normalizes the symbol/timeframe, validates configuration, and resets the snapshot watermark. It then creates and initializes legacy modules in dependency order, connects Confluence, creates enabled analysis modules, and applies evaluation limits and session settings. A creation/initialization failure returns through one release path. Legacy initialization failures retain the existing error diagnostic; optional analysis initialization failures retain their previous status behavior.

The boolean `Init()` overload preserves its legacy enabled modules and GMT session behavior. The typed configuration overload applies configured broker-time sessions. Refactoring these paths does not change either overload's defaults.

| Operation | Owned module instances | Snapshot access |
| --- | --- | --- |
| Construction | None | `GetSnapshot()` returns false |
| `Init()` attempt | Previous instances released; new instances retained only on success | Watermark reset; `GetSnapshot()` returns false until an update attempt |
| `Update()` attempt | Existing instances retained | Current successful or unavailable snapshot becomes observable |
| `Clean()` | Calls module cleanup without deleting instances or resetting manager initialization | Last snapshot remains observable; further updates are supported |
| Destruction | Cleans and deletes owned instances, dependents before shared dependencies | Manager lifetime ends |

## Update data flow

```text
SmcAcquireHistory -> SmcHistoryContext
    -> EvaluateICT: deterministic ICT evaluation of closed candles
    -> UpdateLegacyModules: shared rates and dependency-ordered execution
    -> UpdateAnalysisModules: enabled currency-strength and VIX updates
    -> SmcAppendLegacySnapshot: legacy records and availability
    -> SmcCompleteManagerSnapshot: final limits, ordering, status, diagnostics
    -> signal gating and Update() readiness result
```

`Internal/HistoryContext.mqh` contains terminal acquisition. `shared` is chronological and includes the final forming sentinel expected by legacy shift-zero APIs; `closed` excludes it. Calendar D1/W1 arrays may contain the current period's open. M1 and companion arrays exclude forming candles. The context also carries the evaluation watermark, M1 coverage start/success, and primary/companion price increments.

Acquisition retains the existing lookback, warmup, PO3 horizon, and synchronization rules. A primary-history failure clears the context and produces an unavailable manager snapshot. Missing optional inputs remain separately observable so the evaluator can report per-concept readiness. Acquisition resets the context on every call and introduces no cache.

`Internal/UpdateResult.mqh` holds named execution outcomes. Update dependencies still use short-circuit evaluation: for example, structure requires swings and order blocks require structure. Confluence runs only when all required legacy modules succeed. Optional analysis runs afterward, in its original order.

`Internal/LegacySnapshot.mqh` maps already detected data into records. Individual conversions receive an explicit symbol/timeframe/watermark context and perform no terminal history acquisition. The collector retains getter traversal order and readiness guards. Conversion preserves stable IDs, relationship IDs, geometry, strength, lifecycle, and source/confirmation/update times.

Finalization runs after all detectors and legacy adapters, preserving derived detections before output limits. It trims historical output, sorts records, applies per-concept caps, and aggregates availability. Failed Confluence or analysis downgrades an otherwise ready snapshot to `PARTIAL`; analysis diagnostics take precedence over Confluence diagnostics. `Update()` returns true only for `READY`. Confluence signals are invalidated at the start of every update attempt and again whenever the final snapshot is not ready, including direct access through `Confluence()`.

## Regression boundaries

- `TestManager` uses fixed synthetic history and compares all typed fields across repeated updates, cleanup, reinitialization, and overload switching. Its expected serialized snapshot was captured before this refactor and must not be regenerated merely to make a regression pass.
- `TestLegacySnapshot` exercises conversions without terminal history, including zone lifecycles, relationship IDs, confirmation times, OTE inheritance, session bounds, and unavailable module collection.
- `TestHistoryContext` uses isolated custom symbols to verify candle framing, synchronization/coverage, optional shortages, price increments, and clearing reused acquisition state.
- `TestEngine` covers finalization and manager status/diagnostic precedence. Existing detector, exporter, and reader tests continue to guard the surrounding contracts.

Run the complete local commit gate described in [Development](DEVELOPMENT.md). Focused runtime tests and static checks help during development; they do not replace complete MetaEditor compilation, all detector runtime tests, or the six external readers against actual MT5 exports.
