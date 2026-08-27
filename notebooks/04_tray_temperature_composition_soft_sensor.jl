### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 5b88cada-a268-11f1-b4dc-2f317c610593
md"""
# Soft sensor: tray temperature → composition inference (Tier B)

**Goal.** Infer a distillation tray's liquid composition from its
temperature and the column pressure alone — no tray-level GC — by
inverting the vapor-liquid equilibrium relationship.

Most distillation columns have a temperature (and often pressure)
transmitter on many trays; almost none have a composition analyzer on
every tray — at best there's a GC on the overhead/bottoms product, if
that. This is the canonical **Tier B** soft-sensor problem
([`docs/measurement_tiers.md`](../docs/measurement_tiers.md)): T and P are
measured, composition is not, so composition has to be backed out by
*inverting* the same equilibrium relationship notebooks 1–2 evaluated
*directly*.

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
a unique composition on their own (the binary assumption breaks down) and
this degrades toward Tier C — you'd need either a fixed assumed profile
for the non-key components or additional measurements (e.g. a
periodic multi-tray GC survey to check/recalibrate the key-component
assumption).

This notebook reuses [Clapeyron.jl](https://github.com/ClapeyronThermo/Clapeyron.jl)'s
`bubble_temperature` (the forward direction, T from composition — exactly
what notebooks 1–3 used in the composition-known direction) and inverts it
numerically for composition, since Clapeyron doesn't offer that inverse
directly for a general system.

> Teaching/demo notebook with representative, not column-specific, data.
"""

# ╔═╡ 5b88cb52-a268-11f1-8f0d-694599439b2b
using Clapeyron

# ╔═╡ 5b88cb66-a268-11f1-b146-cb7ca42301f4
using PlutoUI

# ╔═╡ 5b88cb72-a268-11f1-bde3-8ba9d4189f9b
using Plots

# ╔═╡ 5b88cb7a-a268-11f1-a562-e9a84bdf2847
md"## 1. Define the binary key-component system"

# ╔═╡ 5b88ccb0-a268-11f1-a2c5-09333206dc36
components = ["propane", "butane"]  # light key, heavy key

# ╔═╡ 5b88ccc4-a268-11f1-afa0-6b7d55ab56af
model = PR(components)

# ╔═╡ 5b88ccce-a268-11f1-9c01-73f30fa5c6a3
md"## 2. Interactive operating point: measured tray T and column P"

# ╔═╡ 5b88ce68-a268-11f1-8db2-f95feeb98d82
md"Tray temperature (°C): $(@bind Ttray_C Slider(15.0:1.0:65.0, default=38.0, show_value=true))"

# ╔═╡ 5b88ce74-a268-11f1-b514-d7185b006fdf
md"Column pressure (bar): $(@bind Pcol_bar Slider(5.0:0.5:12.0, default=8.0, show_value=true))"

# ╔═╡ 5b88ce7c-a268-11f1-a1ab-07c827ea8dd6
begin
	Ttray = Ttray_C + 273.15
	Pcol = Pcol_bar * 1e5
	(Ttray, Pcol)
end

# ╔═╡ 5b88ce86-a268-11f1-99d1-bdb6f1693756
md"## 3. Soft sensor: invert bubble-point equilibrium to infer tray composition"

# ╔═╡ 5b88ce90-a268-11f1-9a46-c538cb12ce2e
function infer_light_key_fraction(model, P, T_target; tol=1e-4, maxiter=60)
	lo, hi = 1e-4, 1 - 1e-4  # avoid the pure-component edges
	Tlo, = bubble_temperature(model, P, [lo, 1 - lo])   # ~pure heavy key: highest T
	Thi, = bubble_temperature(model, P, [hi, 1 - hi])   # ~pure light key: lowest T

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

# ╔═╡ 5b88ce9a-a268-11f1-b1f3-b953aa932f9e
begin
	x_propane, out_of_range = infer_light_key_fraction(model, Pcol, Ttray)

	range_note = out_of_range ? "\n\n⚠️ Requested temperature is outside the achievable range for this binary system at this pressure — result clamped to the nearest feasible composition." : ""

	md"""
	**Inferred tray liquid composition (soft-sensor output):**
	propane ≈ **$(round(x_propane, digits=3))**, butane ≈ **$(round(1 - x_propane, digits=3))**
	(mole fractions), consistent with a bubble point of $(round(Ttray_C, digits=1)) °C
	at $(round(Pcol_bar, digits=1)) bar.$(range_note)

	No GC touched this tray — the composition comes entirely from inverting
	the same thermodynamics notebook 1 used in the forward direction.
	"""
end

# ╔═╡ 5b88cea2-a268-11f1-970d-fd4072ba70f4
md"""
## 4. Sensitivity: inferred composition vs tray temperature

Sweep tray temperature at fixed column pressure and plot the inferred
propane fraction — this is the soft sensor's whole operating curve. It
should be smooth and monotonic (lower tray temperature ⇒ more of the
lighter, more volatile propane); a kink or discontinuity here would flag a
numerical problem with the inversion, not a physical one.
"""

# ╔═╡ 5b88ceae-a268-11f1-86e3-3f0335d91f55
begin
	T_range_C = 15.0:1.0:65.0
	x_curve = map(T_range_C) do Tc
		xp, _ = infer_light_key_fraction(model, Pcol, Tc + 273.15)
		xp
	end

	plot(collect(T_range_C), x_curve;
		xlabel="Tray temperature (°C)",
		ylabel="Inferred propane mole fraction",
		title="Soft-sensor response at $(round(Pcol_bar, digits=1)) bar",
		legend=false, lw=2, marker=:circle, markersize=3)
end

# ╔═╡ 5b88cec2-a268-11f1-a673-c71e99bec529
md"""
## 5. Next steps toward a deployable soft sensor

- Validate the binary key-component assumption against an occasional
  multi-component tray sample (spot GC or manual sample) — if non-key
  components turn out to be significant, the inferred composition will be
  biased even though the inversion itself is exact for the assumed system.
- Apply the same inversion at every instrumented tray to build a full
  composition profile, and cross-check consistency (profile should be
  monotonic tray-to-tray in a well-behaved column) as a soft sanity check
  on both the model and the tray instrumentation.
- If a real tray has meaningful amounts of a third component (e.g.
  isobutane in a depropanizer), either fold it into the "heavy key" lump
  (as done here) and periodically re-validate that lump's effective
  properties, or add a second measurement (e.g. tray pressure *and* an
  occasional composition anchor) to resolve the extra degree of freedom —
  otherwise this is a Tier C problem, not Tier B.
- Package `infer_light_key_fraction` into `src/` once a second Tier B
  notebook needs the same inversion pattern.
"""

# ╔═╡ Cell order:
# ╟─5b88cada-a268-11f1-b4dc-2f317c610593
# ╠═5b88cb52-a268-11f1-8f0d-694599439b2b
# ╠═5b88cb66-a268-11f1-b146-cb7ca42301f4
# ╠═5b88cb72-a268-11f1-bde3-8ba9d4189f9b
# ╟─5b88cb7a-a268-11f1-a562-e9a84bdf2847
# ╠═5b88ccb0-a268-11f1-a2c5-09333206dc36
# ╠═5b88ccc4-a268-11f1-afa0-6b7d55ab56af
# ╟─5b88ccce-a268-11f1-9c01-73f30fa5c6a3
# ╟─5b88ce68-a268-11f1-8db2-f95feeb98d82
# ╟─5b88ce74-a268-11f1-b514-d7185b006fdf
# ╠═5b88ce7c-a268-11f1-a1ab-07c827ea8dd6
# ╟─5b88ce86-a268-11f1-99d1-bdb6f1693756
# ╠═5b88ce90-a268-11f1-9a46-c538cb12ce2e
# ╠═5b88ce9a-a268-11f1-b1f3-b953aa932f9e
# ╟─5b88cea2-a268-11f1-970d-fd4072ba70f4
# ╠═5b88ceae-a268-11f1-86e3-3f0335d91f55
# ╟─5b88cec2-a268-11f1-a673-c71e99bec529
