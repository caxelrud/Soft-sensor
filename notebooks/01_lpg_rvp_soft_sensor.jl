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

# ╔═╡ 9ff8177e-a241-11f1-b4c6-d3d4e95eb0da
md"""
# Soft sensor: LPG bubble point / RVP-like proxy

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

> This is a teaching/demo notebook with representative, not plant-specific,
> data. Swap in real composition/temperature data (see `data/`) to turn
> this into a deployable soft sensor.
"""

# ╔═╡ 9ff81846-a241-11f1-9bf9-89ba77f9c99d
using Clapeyron

# ╔═╡ 9ff81850-a241-11f1-baff-97a7e8288da3
using PlutoUI

# ╔═╡ 9ff8185a-a241-11f1-a6da-793dc4220db9
using Plots

# ╔═╡ 9ff81866-a241-11f1-9ad5-47d595f921a2
md"## 1. Define the stream (EOS model)"

# ╔═╡ 9ff8188c-a241-11f1-a75a-152229e0a991
components = ["propane", "butane", "isobutane", "pentane"]

# ╔═╡ 9ff81898-a241-11f1-8747-7f55af245fcc
model = PR(components)

# ╔═╡ 9ff81898-a241-11f1-a3bc-cb3fc36f3413
md"""
## 2. Interactive operating point

Adjust the composition (mole fractions, auto-normalized to sum to 1) and
the stream temperature to see the inferred bubble-point pressure update —
this is the "soft sensor" output.
"""

# ╔═╡ 9ff818a0-a241-11f1-893a-dd54e0da41b4
md"Propane: $(@bind x_propane Slider(0.0:0.01:1.0, default=0.40, show_value=true))"

# ╔═╡ 9ff818aa-a241-11f1-bc9d-5199ac6b0cc6
md"n-Butane: $(@bind x_butane Slider(0.0:0.01:1.0, default=0.35, show_value=true))"

# ╔═╡ 9ff818b4-a241-11f1-9157-efe1c0ef9be4
md"Isobutane: $(@bind x_isobutane Slider(0.0:0.01:1.0, default=0.15, show_value=true))"

# ╔═╡ 9ff818b4-a241-11f1-9b3e-e9d9e76fbe63
md"n-Pentane: $(@bind x_pentane Slider(0.0:0.01:1.0, default=0.10, show_value=true))"

# ╔═╡ 9ff818be-a241-11f1-8270-511923b08937
md"Stream temperature (°C): $(@bind T_C Slider(0.0:1.0:60.0, default=40.0, show_value=true))"

# ╔═╡ 9ff818be-a241-11f1-b2a4-b70caebae9ee
begin
	xraw = [x_propane, x_butane, x_isobutane, x_pentane]
	x = xraw ./ sum(xraw)  # normalize to a valid composition
	T = T_C + 273.15        # °C -> K
	(x, T)
end

# ╔═╡ 9ff818c6-a241-11f1-8182-81e94f774f9c
md"## 3. Soft sensor output: inferred bubble-point pressure"

# ╔═╡ 9ff818c6-a241-11f1-a341-7b11e6f9eecf
begin
	p_bubble, vl, vv, y = bubble_pressure(model, T, x)
	p_bubble_kpa = p_bubble / 1000
	md"""
	**Normalized composition** (propane, n-butane, isobutane, n-pentane):
	`$(round.(x, digits=3))`

	**Temperature:** $(round(T_C, digits=1)) °C

	**Inferred bubble-point pressure (soft-sensor output):**
	**$(round(p_bubble_kpa, digits=1)) kPa** ($(round(p_bubble_kpa/6.895, digits=1)) psi)

	Higher bubble-point pressure at a given temperature ⇒ more volatile
	stream (more propane/butane) ⇒ higher RVP. In a real deployment this
	value would be trended against the periodic lab RVP result and, if
	needed, corrected with a simple bias/trim term.
	"""
end

# ╔═╡ 9ff818dc-a241-11f1-9dd3-e3a01a9cf517
md"""
## 4. Sensitivity: how the soft sensor responds to composition

Sweep the propane fraction (renormalizing the rest proportionally) at a
fixed temperature to see how the inferred bubble-point pressure — our RVP
proxy — responds. A soft sensor should move monotonically and smoothly
with the property it's inferring; this kind of check is a basic sanity
test before trusting it against plant data.
"""

# ╔═╡ 9ff818e6-a241-11f1-ba91-ddfa827e20b5
begin
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

	plot(collect(propane_range), pressures_kpa;
		xlabel="Propane mole fraction",
		ylabel="Bubble-point pressure (kPa)",
		title="Soft-sensor response at 40 °C",
		legend=false, lw=2, marker=:circle, markersize=3)
end

# ╔═╡ 9ff818f8-a241-11f1-a97a-ff201606d473
md"""
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
"""

# ╔═╡ Cell order:
# ╟─9ff8177e-a241-11f1-b4c6-d3d4e95eb0da
# ╠═9ff81846-a241-11f1-9bf9-89ba77f9c99d
# ╠═9ff81850-a241-11f1-baff-97a7e8288da3
# ╠═9ff8185a-a241-11f1-a6da-793dc4220db9
# ╟─9ff81866-a241-11f1-9ad5-47d595f921a2
# ╠═9ff8188c-a241-11f1-a75a-152229e0a991
# ╠═9ff81898-a241-11f1-8747-7f55af245fcc
# ╟─9ff81898-a241-11f1-a3bc-cb3fc36f3413
# ╟─9ff818a0-a241-11f1-893a-dd54e0da41b4
# ╟─9ff818aa-a241-11f1-bc9d-5199ac6b0cc6
# ╟─9ff818b4-a241-11f1-9157-efe1c0ef9be4
# ╟─9ff818b4-a241-11f1-9b3e-e9d9e76fbe63
# ╟─9ff818be-a241-11f1-8270-511923b08937
# ╠═9ff818be-a241-11f1-b2a4-b70caebae9ee
# ╟─9ff818c6-a241-11f1-8182-81e94f774f9c
# ╠═9ff818c6-a241-11f1-a341-7b11e6f9eecf
# ╟─9ff818dc-a241-11f1-9dd3-e3a01a9cf517
# ╠═9ff818e6-a241-11f1-ba91-ddfa827e20b5
# ╟─9ff818f8-a241-11f1-a97a-ff201606d473
