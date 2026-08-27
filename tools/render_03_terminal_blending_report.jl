#!/usr/bin/env julia
# Offline/CI-friendly report generator for
# notebooks/03_terminal_blending_soft_sensor.jl. See
# tools/render_01_lpg_rvp_report.jl for the rationale (Pluto's built-in
# "Export as PDF" needs CDN access this sandbox doesn't have); this script
# reproduces the notebook's computation at its default operating point and
# renders a self-contained, offline-safe HTML report that `render_pdf.sh`
# converts to PDF.
#
# Usage: julia --project=. tools/render_03_terminal_blending_report.jl
# Output: pdf/03_terminal_blending_soft_sensor.html

using Clapeyron
using Plots
using Markdown
using Base64

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_HTML = joinpath(REPO_ROOT, "pdf", "03_terminal_blending_soft_sensor.html")
const OUT_PNG = joinpath(REPO_ROOT, "pdf", ".03_terminal_blending_soft_sensor_plot.png")

components = ["propane", "butane", "isobutane", "pentane"]
model = PR(components)

z_A = [0.85, 0.10, 0.04, 0.01]
z_B = [0.05, 0.70, 0.20, 0.05]
z_C = [0.02, 0.08, 0.10, 0.80]

q_A, q_B, q_C = 40.0, 35.0, 15.0
Tblend_C = 25.0
Pblend_bar = 10.0

Tblend = Tblend_C + 273.15
Pblend = Pblend_bar * 1e5

v_A = volume(model, Pblend, Tblend, z_A; phase=:liquid)
v_B = volume(model, Pblend, Tblend, z_B; phase=:liquid)
v_C = volume(model, Pblend, Tblend, z_C; phase=:liquid)

n_A = q_A / v_A
n_B = q_B / v_B
n_C = q_C / v_C

n_component = n_A .* z_A .+ n_B .* z_B .+ n_C .* z_C
z_blend = n_component ./ sum(n_component)

p_bubble, vl, vv, y = bubble_pressure(model, Tblend, z_blend)
p_bubble_kpa = p_bubble / 1000

q_total = q_A + q_B + q_C
share_range = 0.0:0.02:1.0
rvp_curve = map(share_range) do share_A
    qa = share_A * q_total
    remaining = q_total - qa
    frac_B = q_B / (q_B + q_C + eps())
    qb = remaining * frac_B
    qc = remaining * (1 - frac_B)

    na = qa / v_A
    nb = qb / v_B
    nc = qc / v_C
    ncomp = na .* z_A .+ nb .* z_B .+ nc .* z_C
    zb = ncomp ./ sum(ncomp)

    pb, _, _, _ = bubble_pressure(model, Tblend, zb)
    pb / 1000
end

plt = plot(100 .* collect(share_range), rvp_curve;
    xlabel="Stream A share of total flow (%)",
    ylabel="Blend bubble-point pressure (kPa)",
    title="Soft-sensor response at $(round(Tblend_C, digits=1)) °C",
    legend=false, lw=2, marker=:circle, markersize=3,
    size=(700, 420))
savefig(plt, OUT_PNG)
plot_b64 = base64encode(read(OUT_PNG))
rm(OUT_PNG)

md_to_html(s) = sprint(io -> show(io, MIME"text/html"(), Markdown.parse(s)))

intro_md = md_to_html("""
**Goal.** At an NGL/LPG blending terminal, continuously infer the blended
tank's RVP-like volatility from each incoming stream's *periodic* lab
assay and *continuous* flow rate — without an online analyzer on the
blended output.

Terminals routinely blend several incoming NGL streams (e.g. a
propane-rich stream, a butane-rich stream, a natural-gasoline/pentanes-plus
stream) into a single blended product tank. Custody-transfer flow meters
on each incoming line are cheap, continuous, and already there for
inventory/billing. Each stream's composition, by contrast, usually comes
from an infrequent lab GC sample — it is *not* continuously measured. A
soft sensor can still track the blended product's volatility continuously
by combining the last known per-stream assays with the live flow ratios,
instead of waiting on (or paying for) a continuous analyzer on the blend
itself.

**Measurements assumed available:** each incoming stream's composition
(zₐ, z_b, z_c — periodic lab assay, held constant between updates) and
each stream's volumetric flow rate (continuous, from custody-transfer
meters), plus blend temperature (continuous).
**Inferred / computed by this soft sensor:** the blended stream's
composition (flow-weighted, on a molar basis) and its bubble-point
pressure (RVP proxy).
**Tier:** A — direct calculation, given that each input stream's
composition is known (even if only periodically) (`docs/measurement_tiers.md`).
If even the per-stream assays become unavailable, blending ratios would
have to be inferred from historical correlations instead — Tier C.

This report reuses the same Clapeyron.jl Peng-Robinson bubble-point
calculation as `01_lpg_rvp_soft_sensor.jl`, applied to the *blended*
composition rather than a single measured stream. The one new piece of
physics: flow meters read volume, not moles, so each stream's volumetric
flow has to be converted to a molar flow (via its liquid molar volume from
the EOS) before the streams can be combined into a blended mole fraction.

> Teaching/demo report with representative, not terminal-specific, data,
> evaluated at a fixed operating point (the interactive notebook version
> lets you adjust flows and temperature with sliders).
""")

section1_md = md_to_html("""
## 1. Incoming stream assays (periodic lab data, held fixed here)

| Component | Stream A (propane-rich) | Stream B (butane-rich) | Stream C (natural gasoline) |
|---|---|---|---|
| Propane   | $(z_A[1]) | $(z_B[1]) | $(z_C[1]) |
| Butane    | $(z_A[2]) | $(z_B[2]) | $(z_C[2]) |
| Isobutane | $(z_A[3]) | $(z_B[3]) | $(z_C[3]) |
| Pentane   | $(z_A[4]) | $(z_B[4]) | $(z_C[4]) |
""")

section2_md = md_to_html("""
## 2. Operating point used in this printout

Flows: Stream A $(q_A) m³/h, Stream B $(q_B) m³/h, Stream C $(q_C) m³/h.
Blend temperature: **$(round(Tblend_C, digits=1)) °C**, pressure:
**$(round(Pblend_bar, digits=1)) bar**.

Molar flows: Stream A ≈ $(round(n_A/1000, digits=1)) kmol/h,
Stream B ≈ $(round(n_B/1000, digits=1)) kmol/h,
Stream C ≈ $(round(n_C/1000, digits=1)) kmol/h.
""")

result_md = md_to_html("""
## 3. Soft sensor output: blended composition & RVP proxy

**Blended composition (mol fractions):**
propane $(round(z_blend[1], digits=3)),
butane $(round(z_blend[2], digits=3)),
isobutane $(round(z_blend[3], digits=3)),
pentane $(round(z_blend[4], digits=3)).

**Inferred blend bubble-point pressure (RVP proxy, soft-sensor output) at
$(round(Tblend_C, digits=1)) °C:**
**$(round(p_bubble_kpa, digits=1)) kPa** ($(round(p_bubble_kpa/6.895, digits=1)) psi)

No analyzer touched the blended tank to get this number — it comes
entirely from the three (periodic) stream assays and the three
(continuous) flow meters.
""")

sweep_md = md_to_html("""
## 5. Sensitivity: blend RVP proxy vs Stream A flow share

Sweep Stream A's flow (renormalizing B and C proportionally to keep total
throughput fixed) at fixed temperature, to see how the blend's inferred
RVP proxy responds to shifting more of the light, propane-rich stream into
the blend. A soft sensor should move smoothly and monotonically here —
more of the volatile stream should raise the blend's bubble-point
pressure.
""")

next_md = md_to_html("""
## 6. Next steps toward a deployable soft sensor

- Replace the fixed stream assays with values pulled from the plant
  historian / LIMS, refreshed whenever a new lab sample lands, while flow
  rate and temperature update every scan.
- Validate the inferred blend RVP against periodic tank-sample lab results;
  add a bias/trim term if a consistent offset appears.
- Track how much the inferred blend drifts from reality as time since the
  last per-stream assay grows — that bounds how long this Tier A treatment
  stays valid before a stream's composition should be treated as
  effectively unmeasured (Tier B/C) and estimated some other way (e.g. from
  upstream unit conditions).
- Extend to a live mass/energy balance across the blend tank (holdup,
  fill/draw dynamics) rather than an instantaneous flow-ratio blend, for
  terminals with significant tank residence time.
""")

code1 = """v_A = volume(model, Pblend, Tblend, z_A; phase=:liquid)
n_A = q_A / v_A   # volumetric flow -> molar flow"""

code2 = """n_component = n_A .* z_A .+ n_B .* z_B .+ n_C .* z_C
z_blend = n_component ./ sum(n_component)
p_bubble, vl, vv, y = bubble_pressure(model, Tblend, z_blend)"""

html = """<!doctype html>
<html><head><meta charset="utf-8">
<title>Terminal Blending Soft Sensor - Notebook Printout</title>
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
<h1>Soft sensor: terminal blending RVP from component flows and assays</h1>
$intro_md
$section1_md
$section2_md
<pre>$code1</pre>
$result_md
<pre>$code2</pre>
<div class="result">Blend bubble-point pressure ≈ $(round(p_bubble_kpa, digits=1)) kPa ($(round(p_bubble_kpa/6.895, digits=1)) psi) at $(round(Tblend_C, digits=1)) °C</div>
$sweep_md
<img src="data:image/png;base64,$plot_b64" alt="Soft-sensor sensitivity plot">
$next_md
<div class="footer">Generated from notebooks/03_terminal_blending_soft_sensor.jl (Clapeyron.jl PR EOS) &mdash; caxelrud/Soft-sensor</div>
</body></html>
"""

mkpath(dirname(OUT_HTML))
open(OUT_HTML, "w") do io
    write(io, html)
end
println("Report written to ", OUT_HTML, " (blend RVP proxy = ", round(p_bubble_kpa, digits=1), " kPa)")
