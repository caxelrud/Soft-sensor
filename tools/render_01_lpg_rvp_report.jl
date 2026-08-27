#!/usr/bin/env julia
# Offline/CI-friendly report generator for notebooks/01_lpg_rvp_soft_sensor.jl.
#
# The interactive Pluto notebook is the primary artifact and should be
# explored in Pluto (`julia --project=. -e 'using Pluto; Pluto.run()'`),
# where you can use its built-in "Export as PDF" once you have internet
# access to Pluto's frontend assets. This script is a self-contained
# fallback that reproduces the notebook's computation at its default
# operating point and renders a static, offline-safe HTML report (no CDN
# dependency) that `render_pdf.sh` then converts to PDF with headless
# Chromium. Useful in sandboxed/CI environments without outbound access
# to Pluto's asset CDN.
#
# Usage: julia --project=. tools/render_01_lpg_rvp_report.jl
# Output: pdf/01_lpg_rvp_soft_sensor.html (open pdf/render_pdf.sh next, or
# print it with any headless browser)

using Clapeyron
using Plots
using Markdown
using Base64

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_HTML = joinpath(REPO_ROOT, "pdf", "01_lpg_rvp_soft_sensor.html")
const OUT_PNG = joinpath(REPO_ROOT, "pdf", ".01_lpg_rvp_soft_sensor_plot.png")

components = ["propane", "butane", "isobutane", "pentane"]
model = PR(components)

x_propane, x_butane, x_isobutane, x_pentane = 0.40, 0.35, 0.15, 0.10
T_C = 40.0

xraw = [x_propane, x_butane, x_isobutane, x_pentane]
x = xraw ./ sum(xraw)
T = T_C + 273.15

p_bubble, vl, vv, y = bubble_pressure(model, T, x)
p_bubble_kpa = p_bubble / 1000

T_sweep = 40.0 + 273.15
base = [x_butane, x_isobutane, x_pentane]
base_norm = base ./ sum(base)
propane_range = 0.05:0.02:0.85
pressures_kpa = map(propane_range) do xp
    rest = base_norm .* (1 - xp)
    xi = [xp; rest]
    p, _, _, _ = bubble_pressure(model, T_sweep, xi)
    p / 1000
end

plt = plot(collect(propane_range), pressures_kpa;
    xlabel="Propane mole fraction",
    ylabel="Bubble-point pressure (kPa)",
    title="Soft-sensor response at 40 °C",
    legend=false, lw=2, marker=:circle, markersize=3,
    size=(700, 420))
savefig(plt, OUT_PNG)
plot_b64 = base64encode(read(OUT_PNG))
rm(OUT_PNG)

md_to_html(s) = sprint(io -> show(io, MIME"text/html"(), Markdown.parse(s)))

intro_md = md_to_html("""
**Goal.** Replace (or back up) a slow, maintenance-heavy analyzer with an
online, model-based estimate of a hydrocarbon stream's volatility.

A common refinery/LPG-plant problem: an **RVP (Reid Vapor Pressure) analyzer**
or gas chromatograph measures stream composition/volatility every few
minutes at best, is expensive to maintain, and can fail or drift. If we
already measure **temperature** continuously and can estimate or infer the
stream **composition** (from a GC, a material balance, or an upstream
soft sensor), we can compute the stream's **bubble-point pressure** at
process/storage conditions using an equation of state (EOS). This tracks
volatility in the same direction as RVP and can run every scan interval,
with zero analyzer downtime.

This notebook builds that estimator using
[Clapeyron.jl](https://github.com/ClapeyronThermo/Clapeyron.jl) with a
cubic (Peng-Robinson) equation of state for a typical LPG mixture
(propane / n-butane / isobutane / n-pentane).

> This is a teaching/demo report with representative, not plant-specific,
> data, evaluated at a fixed operating point (the interactive notebook
> version lets you adjust composition and temperature with sliders).
""")

section2_md = md_to_html("""
## 2. Operating point used in this printout

| Component  | Mole fraction |
|---|---|
| Propane    | $(round(x[1], digits=3)) |
| n-Butane   | $(round(x[2], digits=3)) |
| Isobutane  | $(round(x[3], digits=3)) |
| n-Pentane  | $(round(x[4], digits=3)) |

Temperature: **$(round(T_C, digits=1)) °C**
""")

result_md = md_to_html("""
## 3. Soft sensor output: inferred bubble-point pressure

**Inferred bubble-point pressure (soft-sensor output):**
**$(round(p_bubble_kpa, digits=1)) kPa** ($(round(p_bubble_kpa/6.895, digits=1)) psi)

Higher bubble-point pressure at a given temperature ⇒ more volatile
stream (more propane/butane) ⇒ higher RVP. In a real deployment this
value would be trended against the periodic lab RVP result and, if
needed, corrected with a simple bias/trim term.
""")

sweep_md = md_to_html("""
## 4. Sensitivity: how the soft sensor responds to composition

Sweep the propane fraction (renormalizing the rest proportionally) at a
fixed temperature to see how the inferred bubble-point pressure — our RVP
proxy — responds. A soft sensor should move monotonically and smoothly
with the property it's inferring; this kind of check is a basic sanity
test before trusting it against plant data.
""")

next_md = md_to_html("""
## 5. Next steps toward a deployable soft sensor

- Replace the interactive sliders with a live/historized composition feed
  (GC, material balance, or an upstream inferential estimate) and
  temperature tag from the plant historian.
- Validate the EOS-based estimate against periodic lab RVP samples over a
  representative operating range; fit a simple bias/trim correction if a
  consistent offset appears.
- Consider switching the EOS (e.g. SRK, or an activity-coefficient model
  via Clapeyron) if validation shows the cubic EOS underperforms for this
  specific stream.
- Package the estimator as a function in `src/` so it can be called from a
  scheduled job or OPC/historian integration, independent of the notebook.
""")

code1 = """components = ["propane", "butane", "isobutane", "pentane"]
model = PR(components)"""

code2 = """p_bubble, vl, vv, y = bubble_pressure(model, T, x)
p_bubble_kpa = p_bubble / 1000"""

html = """<!doctype html>
<html><head><meta charset="utf-8">
<title>LPG RVP Soft Sensor - Notebook Printout</title>
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
<h1>Soft sensor: LPG bubble point / RVP-like proxy</h1>
$intro_md
$section2_md
<pre>$code1</pre>
$result_md
<pre>$code2</pre>
<div class="result">Bubble-point pressure ≈ $(round(p_bubble_kpa, digits=1)) kPa ($(round(p_bubble_kpa/6.895, digits=1)) psi) at $(round(T_C, digits=1)) °C</div>
$sweep_md
<img src="data:image/png;base64,$plot_b64" alt="Soft-sensor sensitivity plot">
$next_md
<div class="footer">Generated from notebooks/01_lpg_rvp_soft_sensor.jl (Clapeyron.jl PR EOS) &mdash; caxelrud/Soft-sensor</div>
</body></html>
"""

mkpath(dirname(OUT_HTML))
open(OUT_HTML, "w") do io
    write(io, html)
end
println("Report written to ", OUT_HTML, " (bubble pressure = ", round(p_bubble_kpa, digits=1), " kPa)")
