# Roadmap notes

## Why petro-chemical / O&G / refinery first

- Rich literature and well-understood thermodynamics (cubic EOS, activity
  models) that Clapeyron.jl already implements, so soft sensors can be
  grounded in physics rather than pure regression.
- Common, high-value use cases: online analyzers (GC, RVP analyzers) are
  slow, expensive, and maintenance-heavy — a model-based inferential
  estimate that runs every scan interval is a classic, well-justified
  soft-sensor application.
- Clear evaluation path: compare inferential estimate against periodic lab
  results.

## Candidate soft sensors (in rough build order)

Each is tagged with its **measurement tier** (see
[`measurement_tiers.md`](measurement_tiers.md)) — how much of the state is
actually assumed measured vs. reconstructed by simulation/estimation. Tier
should be confirmed against a real unit's instrumentation list before a
notebook is built, not assumed for convenience.

1. ✅ **LPG/NGL bubble-point & RVP-like proxy** — from stream composition and
   temperature via a cubic EOS. *(Tier A — direct calculation. First
   notebook, built to establish the thermodynamics layer; a real
   deployment is usually Tier B since composition is the missing
   measurement.)* — `notebooks/01_lpg_rvp_soft_sensor.jl`
2. ✅ **Flash drum / separator soft sensor** — vapor fraction and gas/liquid
   composition from feed composition, T, P via a PT flash. *(Tier A given a
   periodically-updated feed composition — separator T/P are continuous,
   feed composition typically comes from an infrequent well test; drops to
   Tier C with no feed composition at all.)* —
   `notebooks/02_separator_flash_soft_sensor.jl`
3. ✅ **Midstream terminal blending soft sensor** — blended-tank RVP proxy
   from each incoming stream's periodic lab assay plus continuous
   custody-transfer flow rates, no analyzer on the blend itself. *(Tier A
   given per-stream assays, even if only periodic; drops to Tier C if
   those assays are unavailable and blend ratios must be inferred from
   historical correlations instead.)* —
   `notebooks/03_terminal_blending_soft_sensor.jl`
4. ✅ **Distillation tray temperature → composition inference** — classic
   refinery application (depropanizer, binary propane/n-butane key
   components). *(Tier B — the canonical "infer composition from T/P"
   problem, solved by numerically inverting `bubble_temperature`; breaks
   down toward Tier C if non-key components are non-trivial.)* —
   `notebooks/04_tray_temperature_composition_soft_sensor.jl`
5. **Stabilizer column RVP control** — combine EOS-based property estimate
   with a simple data-driven bias/trim correction against lab samples.
   *(Tier B or C depending on how many internal temperatures are
   available; start Tier B, note where a full column simulation becomes
   necessary.)*
6. **Crude/naphtha cut-point estimation** — TBP-curve-based inferential
   properties from column T/P profile. *(Tier C — typically only a handful
   of boundary/draw temperatures are measured on a real crude unit; needs
   a reduced-order column simulation reconciled against those.)*
7. **Water dew-point / hydrate risk soft sensor** (gas pipeline) — infer
   water condensation/hydrate risk along a pipeline from a P/T profile and
   a periodic gas composition/water-content assay. *(Tier A/B — reuses the
   EOS layer for a dew-point calculation instead of bubble point; accurate
   water+hydrocarbon VLE typically needs an associating model, e.g.
   CPA, rather than a plain cubic EOS.)*
8. **Virtual flow metering** (wellhead/gathering line, no multiphase meter)
   — back out oil/water/gas rates from wellhead P, choke position, and a
   mechanistic multiphase flow correlation calibrated against periodic well
   tests. *(Tier C — the biggest lift on this list: needs a multiphase flow
   model in addition to the thermodynamics layer, not just an EOS.)*

## Modeling approach

- Use Clapeyron.jl cubic EOS (PR, SRK) as the default first-principles
  layer — cheap to evaluate, good for hydrocarbon systems, well documented
  component database.
- Where composition isn't directly available (Tier B), pair the EOS layer
  with a local inversion (e.g. back out composition from a tray
  temperature and pressure) rather than assuming composition is known.
- Where even T/P coverage is sparse (Tier C), the EOS layer sits inside a
  larger process/unit simulation with state estimation (data
  reconciliation, moving-horizon estimation, or a Kalman/particle filter)
  doing the work of filling in unmeasured states — the EOS alone isn't
  the soft sensor at that point, the simulation is.
- Keep a naive/data-driven baseline (e.g. linear correlation) alongside
  each EOS-based estimate for comparison.
- Consider PC-SAFT or activity-coefficient models (NRTL, UNIQUAC via
  Clapeyron) for systems with strong non-idealities later on.

## Notebook / PDF workflow

- One Pluto notebook per soft sensor / concept, in `notebooks/`.
- Use `@bind` (PlutoUI) sliders for interactive exploration of operating
  conditions.
- Export finished notebooks to PDF via Pluto's built-in exporter and keep
  the PDF in `pdf/` for easy sharing/review without requiring Julia.
