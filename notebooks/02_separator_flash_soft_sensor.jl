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

# ╔═╡ 12187e44-a255-11f1-af99-314138c577e8
md"""
# Soft sensor: separator vapor fraction & product composition

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
**Tier:** A — direct PT-flash calculation
([`docs/measurement_tiers.md`](../docs/measurement_tiers.md)), given that
*some* feed composition is known (even if only periodically). If feed
composition is not available *at all*, the flash is underdetermined and
this drops to Tier C — you'd need a broader well/reservoir model or
historical correlation to fill in the missing boundary condition.

This notebook uses [Clapeyron.jl](https://github.com/ClapeyronThermo/Clapeyron.jl)'s
Peng-Robinson EOS and its multicomponent PT-flash solver (`tp_flash`) for a
representative wellstream (methane / ethane / propane / n-butane /
n-pentane / n-hexane).

> Teaching/demo notebook with representative, not well-specific, data.
"""

# ╔═╡ 12187f2a-a255-11f1-8f0c-6958860c1707
using Clapeyron

# ╔═╡ 12187f34-a255-11f1-a71b-01b3649e59bd
using PlutoUI

# ╔═╡ 12187f3e-a255-11f1-9152-570159d4ebfd
using Plots

# ╔═╡ 12187f5c-a255-11f1-b832-b5e1929f23db
md"## 1. Define the feed and model"

# ╔═╡ 12187f66-a255-11f1-8109-a9ca7bc27bfb
components = ["methane", "ethane", "propane", "butane", "pentane", "hexane"]

# ╔═╡ 12187f70-a255-11f1-930d-61f9b3ae047a
model = PR(components)

# ╔═╡ 12187f70-a255-11f1-bc90-9d4c8f08b6e4
md"""
## 2. Interactive operating point

Adjust the (periodically-updated) feed composition and the live separator
temperature/pressure.
"""

# ╔═╡ 12187f7a-a255-11f1-8eab-29843554ff04
md"Methane: $(@bind z_c1 Slider(0.0:0.01:0.9, default=0.45, show_value=true))"

# ╔═╡ 12187f82-a255-11f1-b423-c90cbe2d22ad
md"Ethane: $(@bind z_c2 Slider(0.0:0.01:0.5, default=0.15, show_value=true))"

# ╔═╡ 12187f8e-a255-11f1-a709-eb3d00b915ae
md"Propane: $(@bind z_c3 Slider(0.0:0.01:0.5, default=0.15, show_value=true))"

# ╔═╡ 12187fc0-a255-11f1-8eb7-7d73eec3460f
md"n-Butane: $(@bind z_c4 Slider(0.0:0.01:0.5, default=0.10, show_value=true))"

# ╔═╡ 12187fc0-a255-11f1-8926-61c81e03ff0d
md"n-Pentane: $(@bind z_c5 Slider(0.0:0.01:0.5, default=0.08, show_value=true))"

# ╔═╡ 12187fca-a255-11f1-903b-39077f5c3107
md"n-Hexane: $(@bind z_c6 Slider(0.0:0.01:0.5, default=0.07, show_value=true))"

# ╔═╡ 12187fd4-a255-11f1-91a5-a92bcfb3e15b
md"Separator temperature (°C): $(@bind Tsep_C Slider(10.0:1.0:80.0, default=40.0, show_value=true))"

# ╔═╡ 12187fe8-a255-11f1-9a16-930ca6b3349e
md"Separator pressure (bar): $(@bind Psep_bar Slider(5.0:1.0:60.0, default=20.0, show_value=true))"

# ╔═╡ 12187ff2-a255-11f1-85fa-9b5d827c06d6
begin
	zraw = [z_c1, z_c2, z_c3, z_c4, z_c5, z_c6]
	z = zraw ./ sum(zraw)   # normalize to a valid feed composition
	Tsep = Tsep_C + 273.15   # °C -> K
	Psep = Psep_bar * 1e5    # bar -> Pa
	(z, Tsep, Psep)
end

# ╔═╡ 12187ffc-a255-11f1-91d0-13b8b8fd6ef3
md"## 3. Soft sensor output: PT flash (vapor fraction \& product composition)"

# ╔═╡ 12187ffc-a255-11f1-a4b3-dfa7c13c17b1
begin
	xphase, nphase, G = tp_flash(model, Psep, Tsep, z, RRTPFlash())
	# Identify the vapor phase as the one with the larger molar volume
	vols = [volume(model, Psep, Tsep, xphase[i, :]) for i in 1:size(xphase, 1)]
	vap_idx = argmax(vols)
	liq_idx = vap_idx == 1 ? 2 : 1

	gas_comp = xphase[vap_idx, :]
	liq_comp = xphase[liq_idx, :]
	vapor_fraction = sum(nphase[vap_idx, :]) / sum(nphase)

	md"""
	**Vapor fraction (soft-sensor output):** **$(round(100vapor_fraction, digits=1)) mol%** of the feed
	leaves as gas at $(round(Tsep_C, digits=1)) °C / $(round(Psep_bar, digits=1)) bar.

	| Component | Feed z | Gas y | Liquid x |
	|---|---|---|---|
	| Methane   | $(round(z[1], digits=3)) | $(round(gas_comp[1], digits=3)) | $(round(liq_comp[1], digits=3)) |
	| Ethane    | $(round(z[2], digits=3)) | $(round(gas_comp[2], digits=3)) | $(round(liq_comp[2], digits=3)) |
	| Propane   | $(round(z[3], digits=3)) | $(round(gas_comp[3], digits=3)) | $(round(liq_comp[3], digits=3)) |
	| n-Butane  | $(round(z[4], digits=3)) | $(round(gas_comp[4], digits=3)) | $(round(liq_comp[4], digits=3)) |
	| n-Pentane | $(round(z[5], digits=3)) | $(round(gas_comp[5], digits=3)) | $(round(liq_comp[5], digits=3)) |
	| n-Hexane  | $(round(z[6], digits=3)) | $(round(gas_comp[6], digits=3)) | $(round(liq_comp[6], digits=3)) |

	In a real deployment, `z` would be refreshed from each well test / lab
	sample while this cell re-evaluates continuously from the live T/P scan,
	so gas and liquid product quality track operating changes between tests.
	"""
end

# ╔═╡ 12188026-a255-11f1-b73d-997b4789aa4f
md"""
## 4. Sensitivity: vapor fraction vs separator pressure

Sweep separator pressure at fixed temperature and feed composition — the
classic separator-pressure-optimization curve. A soft sensor should move
smoothly and monotonically here; this is a basic sanity check before
trusting it against plant data.
"""

# ╔═╡ 1218802e-a255-11f1-9f34-7928635e03c2
begin
	p_range_bar = 5.0:1.0:60.0
	vf_curve = map(p_range_bar) do pb
		xph, nph, _ = tp_flash(model, pb * 1e5, Tsep, z, RRTPFlash())
		vls = [volume(model, pb * 1e5, Tsep, xph[i, :]) for i in 1:size(xph, 1)]
		vi = argmax(vls)
		sum(nph[vi, :]) / sum(nph)
	end

	plot(collect(p_range_bar), 100 .* vf_curve;
		xlabel="Separator pressure (bar)",
		ylabel="Vapor fraction (mol%)",
		title="Soft-sensor response at $(round(Tsep_C, digits=1)) °C",
		legend=false, lw=2, marker=:circle, markersize=3)
end

# ╔═╡ 12188038-a255-11f1-9a6b-ef41aad0f250
md"""
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
"""

# ╔═╡ Cell order:
# ╟─12187e44-a255-11f1-af99-314138c577e8
# ╠═12187f2a-a255-11f1-8f0c-6958860c1707
# ╠═12187f34-a255-11f1-a71b-01b3649e59bd
# ╠═12187f3e-a255-11f1-9152-570159d4ebfd
# ╟─12187f5c-a255-11f1-b832-b5e1929f23db
# ╠═12187f66-a255-11f1-8109-a9ca7bc27bfb
# ╠═12187f70-a255-11f1-930d-61f9b3ae047a
# ╟─12187f70-a255-11f1-bc90-9d4c8f08b6e4
# ╟─12187f7a-a255-11f1-8eab-29843554ff04
# ╟─12187f82-a255-11f1-b423-c90cbe2d22ad
# ╟─12187f8e-a255-11f1-a709-eb3d00b915ae
# ╟─12187fc0-a255-11f1-8eb7-7d73eec3460f
# ╟─12187fc0-a255-11f1-8926-61c81e03ff0d
# ╟─12187fca-a255-11f1-903b-39077f5c3107
# ╟─12187fd4-a255-11f1-91a5-a92bcfb3e15b
# ╟─12187fe8-a255-11f1-9a16-930ca6b3349e
# ╠═12187ff2-a255-11f1-85fa-9b5d827c06d6
# ╟─12187ffc-a255-11f1-91d0-13b8b8fd6ef3
# ╠═12187ffc-a255-11f1-a4b3-dfa7c13c17b1
# ╟─12188026-a255-11f1-b73d-997b4789aa4f
# ╠═1218802e-a255-11f1-9f34-7928635e03c2
# ╟─12188038-a255-11f1-9a6b-ef41aad0f250
