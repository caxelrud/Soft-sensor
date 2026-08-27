#!/usr/bin/env julia
# Offline/CI-friendly report generator for
# notebooks/02_separator_flash_soft_sensor.jl. See
# tools/render_01_lpg_rvp_report.jl for the rationale (Pluto's built-in
# "Export as PDF" needs CDN access this sandbox doesn't have); this script
# reproduces the notebook's computation at its default operating point and
# renders a self-contained, offline-safe HTML report that `render_pdf.sh`
# converts to PDF.
#
# Usage: julia --project=. tools/render_02_separator_report.jl
# Output: pdf/02_separator_flash_soft_sensor.html

using Clapeyron
using Plots
using Markdown
using Base64

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_HTML = joinpath(REPO_ROOT, "pdf", "02_separator_flash_soft_sensor.html")
const OUT_PNG = joinpath(REPO_ROOT, "pdf", ".02_separator_flash_soft_sensor_plot.png")

components = ["methane", "ethane", "propane", "butane", "pentane", "hexane"]
model = PR(components)

z_c1, z_c2, z_c3, z_c4, z_c5, z_c6 = 0.45, 0.15, 0.15, 0.10, 0.08, 0.07
Tsep_C = 40.0
Psep_bar = 20.0

zraw = [z_c1, z_c2, z_c3, z_c4, z_c5, z_c6]
z = zraw ./ sum(zraw)
Tsep = Tsep_C + 273.15
Psep = Psep_bar * 1e5

xphase, nphase, G = tp_flash(model, Psep, Tsep, z, RRTPFlash())
vols = [volume(model, Psep, Tsep, xphase[i, :]) for i in 1:size(xphase, 1)]
vap_idx = argmax(vols)
liq_idx = vap_idx == 1 ? 2 : 1
gas_comp = xphase[vap_idx, :]
liq_comp = xphase[liq_idx, :]
vapor_fraction = sum(nphase[vap_idx, :]) / sum(nphase)

p_range_bar = 5.0:1.0:60.0
vf_curve = map(p_range_bar) do pb
    xph, nph, _ = tp_flash(model, pb * 1e5, Tsep, z, RRTPFlash())
    vls = [volume(model, pb * 1e5, Tsep, xph[i, :]) for i in 1:size(xph, 1)]
    vi = argmax(vls)
    sum(nph[vi, :]) / sum(nph)
end

plt = plot(collect(p_range_bar), 100 .* vf_curve;
    xlabel="Separator pressure (bar)",
    ylabel="Vapor fraction (mol%)",
    title="Soft-sensor response at $(round(Tsep_C, digits=1)) °C",
    legend=false, lw=2, marker=:circle, markersize=3,
    size=(700, 420))
savefig(plt, OUT_PNG)
plot_b64 = base64encode(read(OUT_PNG))
rm(OUT_PNG)

md_to_html(s) = sprint(io -> show(io, MIME"text/html"(), Markdown.parse(s)))

intro_md = md_to_html("""
**Goal.** Continuously infer a gas-oil separator's vapor fraction (a
GOR-like proxy) and gas/liquid product compositions from cheap, continuous
measurements (temperature, pressure), instead of requiring a continuous
composition analyzer on every separator.

A production/gas-oil separator splits a wellstream into gas and liquid at
its operating temperature and pressure. Given the feed composition, the
split (vapor fraction) and both product compositions are fully determined
by vapor-liquid equilibrium — a PT flash. In the field, separator T and P
are cheap, continuous, reliable measurements; feed (wellstream) composition
usually is **not** continuously measured — it comes from an infrequent
well test or lab GC sample. This notebook's soft sensor evaluates the
flash continuously from live T/P, using the last known feed composition,
so it tracks changes in operating conditions between well tests instead of
going stale.

**Measurements assumed available:** feed composition (z, from a periodic
well test / lab GC — not continuous), separator temperature (T) and
pressure (P), both continuous.
**Inferred / computed by this soft sensor:** vapor fraction, gas
composition, liquid composition.
**Tier:** A — direct PT-flash calculation (`docs/measurement_tiers.md`),
given that *some* feed composition is known (even if only periodically).
If feed composition is not available at all, the flash is underdetermined
and this drops to Tier C — you'd need a broader well/reservoir model or
historical correlation to fill in the missing boundary condition.

This report uses [Clapeyron.jl](https://github.com/ClapeyronThermo/Clapeyron.jl)'s
Peng-Robinson EOS and multicomponent PT-flash solver for a representative
wellstream (methane / ethane / propane / n-butane / n-pentane / n-hexane),
evaluated at a fixed operating point (the interactive notebook version
lets you adjust feed composition, temperature and pressure with sliders).
""")

section2_md = md_to_html("""
## 2. Operating point used in this printout

Feed composition (normalized): $(round.(z, digits=3))

Separator temperature: **$(round(Tsep_C, digits=1)) °C**, pressure:
**$(round(Psep_bar, digits=1)) bar**
""")

result_md = md_to_html("""
## 3. Soft sensor output: PT flash (vapor fraction & product composition)

**Vapor fraction (soft-sensor output):** **$(round(100vapor_fraction, digits=1)) mol%**
of the feed leaves as gas at $(round(Tsep_C, digits=1)) °C / $(round(Psep_bar, digits=1)) bar.

| Component | Feed z | Gas y | Liquid x |
|---|---|---|---|
| Methane   | $(round(z[1], digits=3)) | $(round(gas_comp[1], digits=3)) | $(round(liq_comp[1], digits=3)) |
| Ethane    | $(round(z[2], digits=3)) | $(round(gas_comp[2], digits=3)) | $(round(liq_comp[2], digits=3)) |
| Propane   | $(round(z[3], digits=3)) | $(round(gas_comp[3], digits=3)) | $(round(liq_comp[3], digits=3)) |
| n-Butane  | $(round(z[4], digits=3)) | $(round(gas_comp[4], digits=3)) | $(round(liq_comp[4], digits=3)) |
| n-Pentane | $(round(z[5], digits=3)) | $(round(gas_comp[5], digits=3)) | $(round(liq_comp[5], digits=3)) |
| n-Hexane  | $(round(z[6], digits=3)) | $(round(gas_comp[6], digits=3)) | $(round(liq_comp[6], digits=3)) |

In a real deployment, `z` would be refreshed from each well test / lab
sample while this calculation re-evaluates continuously from the live T/P
scan, so gas and liquid product quality track operating changes between
tests.
""")

sweep_md = md_to_html("""
## 4. Sensitivity: vapor fraction vs separator pressure

Sweep separator pressure at fixed temperature and feed composition — the
classic separator-pressure-optimization curve. A soft sensor should move
smoothly and monotonically here; this is a basic sanity check before
trusting it against plant data.
""")

next_md = md_to_html("""
## 5. Next steps toward a deployable soft sensor

- Feed this soft sensor from the plant historian: live separator T/P every
  scan, feed composition `z` refreshed on each well test / lab GC sample
  (held constant between updates).
- Validate vapor fraction and gas/liquid compositions against any
  available continuous gas flow meter or periodic lab analysis; add a
  bias/trim term if a consistent offset appears.
- Track how much accuracy degrades between well tests as the real
  wellstream composition drifts — this bounds how long a Tier A treatment
  stays valid before it should be re-classified as Tier B/C (composition
  effectively unmeasured) and paired with a well/reservoir decline model.
- Extend to three-phase flash (add free water) for wellstreams with
  produced water, and to slug/transient behavior if the separator sees
  significant flow variability.
""")

code1 = """components = ["methane", "ethane", "propane", "butane", "pentane", "hexane"]
model = PR(components)"""

code2 = """xphase, nphase, G = tp_flash(model, Psep, Tsep, z, RRTPFlash())
vapor_fraction = sum(nphase[vap_idx, :]) / sum(nphase)"""

html = """<!doctype html>
<html><head><meta charset="utf-8">
<title>Separator Flash Soft Sensor - Notebook Printout</title>
<style>
  body { font-family: -apple-system, Segoe UI, Helvetica, Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; color: #1a1a1a; line-height: 1.5; }
  h1 { border-bottom: 2px solid #2a5; padding-bottom: 8px; }
  h2 { margin-top: 2em; color: #245; }
  pre { background: #f4f4f4; border: 1px solid #ddd; border-radius: 6px; padding: 12px 16px; overflow-x: auto; font-size: 13px; }
  table { border-collapse: collapse; margin: 1em 0; }
  th, td { border: 1px solid #ccc; padding: 6px 12px; text-align: right; }
  th:first-child, td:first-child { text-align: left; }
  img { max-width: 100%; border: 1px solid #ddd; border-radius: 6px; margin: 1em 0; }
  .result { background: #eef8ee; border-left: 4px solid #2a5; padding: 8px 16px; }
  .footer { margin-top: 3em; font-size: 12px; color: #888; border-top: 1px solid #ddd; padding-top: 1em; }
</style>
</head>
<body>
<h1>Soft sensor: separator vapor fraction &amp; product composition</h1>
$intro_md
$section2_md
<pre>$code1</pre>
$result_md
<pre>$code2</pre>
<div class="result">Vapor fraction ≈ $(round(100vapor_fraction, digits=1)) mol% at $(round(Tsep_C, digits=1)) °C / $(round(Psep_bar, digits=1)) bar</div>
$sweep_md
<img src="data:image/png;base64,$plot_b64" alt="Soft-sensor sensitivity plot">
$next_md
<div class="footer">Generated from notebooks/02_separator_flash_soft_sensor.jl (Clapeyron.jl PR EOS, RRTPFlash) &mdash; caxelrud/Soft-sensor</div>
</body></html>
"""

mkpath(dirname(OUT_HTML))
open(OUT_HTML, "w") do io
    write(io, html)
end
println("Report written to ", OUT_HTML, " (vapor fraction = ", round(100vapor_fraction, digits=1), " mol%)")
