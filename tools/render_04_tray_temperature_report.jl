#!/usr/bin/env julia
# Offline/CI-friendly report generator for
# notebooks/04_tray_temperature_composition_soft_sensor.jl. See
# tools/render_01_lpg_rvp_report.jl for the rationale (Pluto's built-in
# "Export as PDF" needs CDN access this sandbox doesn't have); this script
# reproduces the notebook's computation at its default operating point and
# renders a self-contained, offline-safe HTML report that `render_pdf.sh`
# converts to PDF.
#
# Usage: julia --project=. tools/render_04_tray_temperature_report.jl
# Output: pdf/04_tray_temperature_composition_soft_sensor.html

using Clapeyron
using Plots
using Markdown
using Base64

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_HTML = joinpath(REPO_ROOT, "pdf", "04_tray_temperature_composition_soft_sensor.html")
const OUT_PNG = joinpath(REPO_ROOT, "pdf", ".04_tray_temperature_composition_soft_sensor_plot.png")

components = ["propane", "butane"]
model = PR(components)

function infer_light_key_fraction(model, P, T_target; tol=1e-4, maxiter=60)
    lo, hi = 1e-4, 1 - 1e-4
    Tlo, = bubble_temperature(model, P, [lo, 1 - lo])
    Thi, = bubble_temperature(model, P, [hi, 1 - hi])

    Tclamped = clamp(T_target, Thi, Tlo)
    out_of_range = Tclamped != T_target

    flo = Tlo - Tclamped
    fhi = Thi - Tclamped
    x1 = (lo + hi) / 2
    for _ in 1:maxiter
        x1 = (lo + hi) / 2
        Tmid, = bubble_temperature(model, P, [x1, 1 - x1])
        fmid = Tmid - Tclamped
        abs(fmid) < tol && break
        if sign(fmid) == sign(flo)
            lo, flo = x1, fmid
        else
            hi, fhi = x1, fmid
        end
    end
    return x1, out_of_range
end

Ttray_C = 38.0
Pcol_bar = 8.0
Ttray = Ttray_C + 273.15
Pcol = Pcol_bar * 1e5

x_propane, out_of_range = infer_light_key_fraction(model, Pcol, Ttray)

T_range_C = 15.0:1.0:65.0
x_curve = map(T_range_C) do Tc
    xp, _ = infer_light_key_fraction(model, Pcol, Tc + 273.15)
    xp
end

plt = plot(collect(T_range_C), x_curve;
    xlabel="Tray temperature (°C)",
    ylabel="Inferred propane mole fraction",
    title="Soft-sensor response at $(round(Pcol_bar, digits=1)) bar",
    legend=false, lw=2, marker=:circle, markersize=3,
    size=(700, 420))
savefig(plt, OUT_PNG)
plot_b64 = base64encode(read(OUT_PNG))
rm(OUT_PNG)

md_to_html(s) = sprint(io -> show(io, MIME"text/html"(), Markdown.parse(s)))

intro_md = md_to_html("""
**Goal.** Infer a distillation tray's liquid composition from its
temperature and the column pressure alone — no tray-level GC — by
inverting the vapor-liquid equilibrium relationship.

Most distillation columns have a temperature (and often pressure)
transmitter on many trays; almost none have a composition analyzer on
every tray — at best there's a GC on the overhead/bottoms product, if
that. This is the canonical **Tier B** soft-sensor problem
(`docs/measurement_tiers.md`): T and P are measured, composition is not,
so composition has to be backed out by *inverting* the same equilibrium
relationship notebooks 1–3 evaluated *directly*.

**The catch, and why this is genuinely Tier B and not Tier A in disguise:**
a tray temperature and pressure alone only pin down composition if the
system effectively has one composition degree of freedom — i.e. it's
(pseudo-)binary. Here we model a depropanizer tray as a binary
propane/n-butane "key component" system (a standard simplification when
one light key and one heavy key dominate and everything else is a minor
impurity). Given T and P, there is exactly one liquid composition
consistent with the tray being at its bubble point, and we solve for it
by bisection.

**Measurements assumed available:** tray temperature (T), column pressure
(P), both continuous.
**Inferred / computed by this soft sensor:** tray liquid composition
(propane mole fraction), by inverting the bubble-point relationship.
**Tier:** B — local inversion, not a direct calculation. If more than two
components are present in non-trivial amounts, T and P no longer pin down
a unique composition on their own and this degrades toward Tier C — you'd
need either a fixed assumed profile for the non-key components or
additional measurements.

This report reuses Clapeyron.jl's `bubble_temperature` (the forward
direction) and inverts it numerically for composition by bisection, since
Clapeyron doesn't offer that inverse directly for a general system,
evaluated at a fixed operating point (the interactive notebook version
lets you adjust tray T and column P with sliders).
""")

result_md = md_to_html("""
## 3. Soft sensor output: inferred tray composition

Tray temperature: **$(round(Ttray_C, digits=1)) °C**, column pressure:
**$(round(Pcol_bar, digits=1)) bar**.

**Inferred tray liquid composition (soft-sensor output):**
propane ≈ **$(round(x_propane, digits=3))**, butane ≈ **$(round(1 - x_propane, digits=3))**
(mole fractions), consistent with a bubble point of $(round(Ttray_C, digits=1)) °C
at $(round(Pcol_bar, digits=1)) bar.

No GC touched this tray — the composition comes entirely from inverting
the same thermodynamics notebook 1 used in the forward direction.
""")

sweep_md = md_to_html("""
## 4. Sensitivity: inferred composition vs tray temperature

Sweep tray temperature at fixed column pressure and plot the inferred
propane fraction — this is the soft sensor's whole operating curve. It
should be smooth and monotonic (lower tray temperature ⇒ more of the
lighter, more volatile propane); a kink or discontinuity here would flag a
numerical problem with the inversion, not a physical one.
""")

next_md = md_to_html("""
## 5. Next steps toward a deployable soft sensor

- Validate the binary key-component assumption against an occasional
  multi-component tray sample (spot GC or manual sample) — if non-key
  components turn out to be significant, the inferred composition will be
  biased even though the inversion itself is exact for the assumed system.
- Apply the same inversion at every instrumented tray to build a full
  composition profile, and cross-check consistency (profile should be
  monotonic tray-to-tray in a well-behaved column) as a soft sanity check
  on both the model and the tray instrumentation.
- If a real tray has meaningful amounts of a third component, either fold
  it into the "heavy key" lump (as done here) and periodically re-validate
  that lump's effective properties, or add a second measurement to resolve
  the extra degree of freedom — otherwise this is a Tier C problem, not
  Tier B.
- Package `infer_light_key_fraction` into `src/` once a second Tier B
  notebook needs the same inversion pattern.
""")

code1 = """function infer_light_key_fraction(model, P, T_target; tol=1e-4, maxiter=60)
    # bisection: T(x_propane) is monotonic decreasing, so this is well-posed
    ...
end"""

html = """<!doctype html>
<html><head><meta charset="utf-8">
<title>Tray Temperature Soft Sensor - Notebook Printout</title>
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
<h1>Soft sensor: tray temperature &rarr; composition inference (Tier B)</h1>
$intro_md
<pre>$code1</pre>
$result_md
<div class="result">Inferred propane mole fraction ≈ $(round(x_propane, digits=3)) at $(round(Ttray_C, digits=1)) °C / $(round(Pcol_bar, digits=1)) bar</div>
$sweep_md
<img src="data:image/png;base64,$plot_b64" alt="Soft-sensor sensitivity plot">
$next_md
<div class="footer">Generated from notebooks/04_tray_temperature_composition_soft_sensor.jl (Clapeyron.jl PR EOS) &mdash; caxelrud/Soft-sensor</div>
</body></html>
"""

mkpath(dirname(OUT_HTML))
open(OUT_HTML, "w") do io
    write(io, html)
end
println("Report written to ", OUT_HTML, " (inferred propane x = ", round(x_propane, digits=3), ")")
