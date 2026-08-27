# Soft-sensor

Soft sensors (inferential/virtual sensors) for industrial process applications,
starting with **petro-chemical, oil & gas, and refinery** processes.

A soft sensor estimates a hard-to-measure or expensive-to-measure quantity
(e.g. a lab property like RVP, sulfur content, or a distillation cut point)
from cheaper, faster, continuously-available measurements (temperatures,
pressures, flows, compositions), often combined with a first-principles
thermodynamic model or a data-driven correlation. The goal here is to build
these estimators on solid thermodynamics rather than pure black-box
regression, using [Clapeyron.jl](https://github.com/ClapeyronThermo/Clapeyron.jl)
for equations of state / phase equilibrium calculations, blended with
statistical or ML correction models where useful.

## Scope (initial focus)

- Petro-chemical, O&G, and refinery unit operations: distillation/fractionation,
  flash drums, separators, LPG/naphtha stabilization, gas processing.
- Typical soft-sensor targets: bubble/dew point, Reid Vapor Pressure (RVP)
  proxies, K-values, product composition/cut points, tray temperature-to-
  composition inference.
- Extend to other industrial domains (power, water treatment, food & beverage,
  pulp & paper, etc.) once the petro-chemical patterns are established.

## Design principle: scope by measurement availability

What a soft sensor can do is set by what's actually instrumented on the
real unit, not by what's convenient to assume. The fewer states are
directly measured (composition especially), the more the soft sensor has
to simulate/estimate rather than just evaluate a property from known
conditions. Every notebook is scoped against this explicitly — see
[`docs/measurement_tiers.md`](docs/measurement_tiers.md) for the tier
definitions (A: direct calculation, B: local inversion, C: full process
simulation/state estimation) and [`docs/roadmap.md`](docs/roadmap.md) for
how each planned soft sensor is tagged.

## Tech stack

- **Julia** for all modeling code.
- **[Clapeyron.jl](https://github.com/ClapeyronThermo/Clapeyron.jl)** for
  equations of state (PR, SRK, PC-SAFT, ...), phase equilibria, and
  thermophysical properties.
- **[Pluto.jl](https://plutojl.org/)** reactive notebooks for exploration,
  documentation, and interactive demos (sliders/widgets via PlutoUI.jl).
- Notebooks are exported to **PDF** (via Pluto's built-in "Export to PDF")
  as static, shareable reports/documentation — see `pdf/`.

## Repository layout

```
notebooks/   Pluto notebooks (one soft sensor / concept per notebook)
src/         Reusable Julia code (models, correlations, utilities)
data/        Sample/synthetic process data used by notebooks
docs/        Design notes, references, roadmap
pdf/         PDF exports of notebooks (generated, see workflow below)
Project.toml Julia environment / dependencies
```

## Getting started

Requires Julia (1.10+; install via [juliaup](https://github.com/JuliaLang/juliaup)).

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using Pluto; Pluto.run()'
```

Then open a notebook from `notebooks/` in the Pluto browser UI.

### Exporting a notebook to PDF

**Preferred (interactive):** open the notebook in Pluto and use the
notebook menu (top right, "..." / export icon) → **Export as PDF**. Save
the result into `pdf/` with the same base filename as the notebook. This
needs outbound access to Pluto's frontend asset CDN.

**Offline / CI fallback:** for environments without CDN access (e.g. a
sandboxed session), each notebook can have a companion `tools/render_*.jl`
script that recomputes its results at a representative operating point and
renders a self-contained (no external resources) HTML report, which
`tools/render_pdf.sh` then converts to PDF with headless Chromium:

```bash
julia --project=. tools/render_01_lpg_rvp_report.jl   # -> pdf/01_lpg_rvp_soft_sensor.html
tools/render_pdf.sh pdf/01_lpg_rvp_soft_sensor.html pdf/01_lpg_rvp_soft_sensor.pdf
```

## Notebooks

| Notebook | Description |
|---|---|
| [`01_lpg_rvp_soft_sensor.jl`](notebooks/01_lpg_rvp_soft_sensor.jl) | Inferring an LPG stream's bubble-point pressure (an RVP-like proxy) from composition and temperature using a cubic EOS, as a stand-in for an online analyzer. *(Tier A)* |
| [`02_separator_flash_soft_sensor.jl`](notebooks/02_separator_flash_soft_sensor.jl) | Inferring a gas-oil separator's vapor fraction and gas/liquid product compositions from continuous T/P plus a periodically-updated feed composition, via a PT flash. *(Tier A, degrades to Tier C without any feed composition.)* |

## Roadmap

- [x] Flash-drum / separator soft sensor (vapor fraction, gas/liquid composition from T/P + periodic feed composition)
- [ ] Distillation tray-temperature-to-composition inferential estimator
- [ ] Naphtha/LPG stabilizer RVP soft sensor with plant-representative data
- [ ] Compare EOS-based estimates against data-driven (regression/ML) baselines
- [ ] Package reusable soft-sensor building blocks into `src/`

## License

See [LICENSE](LICENSE).
