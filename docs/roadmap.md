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

1. **LPG/NGL bubble-point & RVP-like proxy** — from stream composition and
   temperature via a cubic EOS. (First notebook.)
2. **Flash drum / separator soft sensor** — vapor fraction and K-values from
   feed composition, T, P.
3. **Distillation tray temperature → composition inference** — classic
   refinery application (e.g. debutanizer, depropanizer).
4. **Stabilizer column RVP control** — combine EOS-based property estimate
   with a simple data-driven bias/trim correction against lab samples.
5. **Crude/naphtha cut-point estimation** — TBP-curve-based inferential
   properties from column T/P profile.

## Modeling approach

- Use Clapeyron.jl cubic EOS (PR, SRK) as the default first-principles
  layer — cheap to evaluate, good for hydrocarbon systems, well documented
  component database.
- Where composition isn't directly available, pair the EOS layer with a
  simple estimator (e.g. from tray temperatures) to back out composition,
  then feed that into the EOS-based property calculation.
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
