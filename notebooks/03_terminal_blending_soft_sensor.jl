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

# ╔═╡ a2578e0a-a25f-11f1-912a-a7548e2945bd
md"""
# Soft sensor: terminal blending RVP from component flows and assays

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
**Tier:** A — direct calculation, given that each *input* stream's
composition is known (even if only periodically) —see
[`docs/measurement_tiers.md`](../docs/measurement_tiers.md). If even the
per-stream assays become unavailable, blending ratios would have to be
inferred from historical correlations instead — Tier C.

This notebook reuses the same [Clapeyron.jl](https://github.com/ClapeyronThermo/Clapeyron.jl)
Peng-Robinson bubble-point calculation as
[`01_lpg_rvp_soft_sensor.jl`](01_lpg_rvp_soft_sensor.jl), applied to the
*blended* composition rather than a single measured stream. The one new
piece of physics: flow meters read volume (or mass), not moles, so each
stream's volumetric flow has to be converted to a molar flow (via its
liquid molar volume from the EOS) before the streams can be combined into
a blended mole fraction.

> Teaching/demo notebook with representative, not terminal-specific, data.
"""

# ╔═╡ a2578e8c-a25f-11f1-aed3-2909b1692d1a
using Clapeyron

# ╔═╡ a2578e96-a25f-11f1-a343-01595997ac9a
using PlutoUI

# ╔═╡ a2578ea0-a25f-11f1-aea6-ebf1fab08c70
using Plots

# ╔═╡ a2578ea0-a25f-11f1-9898-ad9b6121781d
md"## 1. Define components and incoming stream assays"

# ╔═╡ a2578ea8-a25f-11f1-b68c-47304d34bbe5
components = ["propane", "butane", "isobutane", "pentane"]

# ╔═╡ a2578eb4-a25f-11f1-ac10-191cd683d5f3
model = PR(components)

# ╔═╡ a2578eb4-a25f-11f1-9684-277af3b809cc
md"""
Representative periodic lab assays for the three incoming streams (held
fixed here — in a real deployment these update whenever a new lab sample
comes in, independently of this calculation):

| Component | Stream A (propane-rich) | Stream B (butane-rich) | Stream C (natural gasoline) |
|---|---|---|---|
| Propane   | 0.85 | 0.05 | 0.02 |
| Butane    | 0.10 | 0.70 | 0.08 |
| Isobutane | 0.04 | 0.20 | 0.10 |
| Pentane   | 0.01 | 0.05 | 0.80 |
"""

# ╔═╡ a2579044-a25f-11f1-ba55-d533cb9b6a0c
begin
	z_A = [0.85, 0.10, 0.04, 0.01]
	z_B = [0.05, 0.70, 0.20, 0.05]
	z_C = [0.02, 0.08, 0.10, 0.80]
end

# ╔═╡ a257904e-a25f-11f1-83e7-3dcec25a39a8
md"## 2. Interactive operating point: live flow rates \& temperature"

# ╔═╡ a2579058-a25f-11f1-b570-fb92cb2e135f
md"Stream A flow (m³/h): $(@bind q_A Slider(0.0:1.0:100.0, default=40.0, show_value=true))"

# ╔═╡ a2579062-a25f-11f1-a6ac-c165df4f261c
md"Stream B flow (m³/h): $(@bind q_B Slider(0.0:1.0:100.0, default=35.0, show_value=true))"

# ╔═╡ a257906c-a25f-11f1-bb83-4ba72e0f3ebb
md"Stream C flow (m³/h): $(@bind q_C Slider(0.0:1.0:100.0, default=15.0, show_value=true))"

# ╔═╡ a2579076-a25f-11f1-a920-81cfcc362b9d
md"Blend temperature (°C): $(@bind Tblend_C Slider(0.0:1.0:50.0, default=25.0, show_value=true))"

# ╔═╡ a2579080-a25f-11f1-bdf4-898ea44f3c8b
md"Blend pressure (bar, kept high enough to stay liquid): $(@bind Pblend_bar Slider(5.0:1.0:20.0, default=10.0, show_value=true))"

# ╔═╡ a2579080-a25f-11f1-9ea5-714e43eaae90
begin
	Tblend = Tblend_C + 273.15
	Pblend = Pblend_bar * 1e5
	(Tblend, Pblend)
end

# ╔═╡ a257908a-a25f-11f1-af8a-05759ee9e45a
md"## 3. Convert volumetric flows to molar flows (via EOS liquid density)"

# ╔═╡ a257908a-a25f-11f1-b34e-dde1620af4a2
begin
	v_A = volume(model, Pblend, Tblend, z_A; phase=:liquid)
	v_B = volume(model, Pblend, Tblend, z_B; phase=:liquid)
	v_C = volume(model, Pblend, Tblend, z_C; phase=:liquid)

	# volumetric flow [m3/h] / molar volume [m3/mol] -> molar flow [mol/h]
	n_A = q_A / v_A
	n_B = q_B / v_B
	n_C = q_C / v_C

	md"""
	Molar flows: Stream A ≈ $(round(n_A/1000, digits=1)) kmol/h,
	Stream B ≈ $(round(n_B/1000, digits=1)) kmol/h,
	Stream C ≈ $(round(n_C/1000, digits=1)) kmol/h.
	"""
end

# ╔═╡ a2579094-a25f-11f1-8aff-3732706477ea
md"## 4. Soft sensor output: blended composition \& RVP proxy"

# ╔═╡ a2579094-a25f-11f1-9a0e-c52d93030852
begin
	n_component = n_A .* z_A .+ n_B .* z_B .+ n_C .* z_C
	z_blend = n_component ./ sum(n_component)

	p_bubble, vl, vv, y = bubble_pressure(model, Tblend, z_blend)
	p_bubble_kpa = p_bubble / 1000

	md"""
	**Blended composition (mol fractions):**
	propane $(round(z_blend[1], digits=3)),
	butane $(round(z_blend[2], digits=3)),
	isobutane $(round(z_blend[3], digits=3)),
	pentane $(round(z_blend[4], digits=3)).

	**Inferred blend bubble-point pressure (RVP proxy, soft-sensor output)
	at $(round(Tblend_C, digits=1)) °C:**
	**$(round(p_bubble_kpa, digits=1)) kPa** ($(round(p_bubble_kpa/6.895, digits=1)) psi)

	No analyzer touched the blended tank to get this number — it comes
	entirely from the three (periodic) stream assays and the three
	(continuous) flow meters.
	"""
end

# ╔═╡ a2579206-a25f-11f1-88e6-0fa97bfd3dd7
md"""
## 5. Sensitivity: blend RVP proxy vs Stream A flow share

Sweep Stream A's flow (renormalizing B and C proportionally to keep total
throughput fixed) at fixed temperature, to see how the blend's inferred
RVP proxy responds to shifting more of the light, propane-rich stream into
the blend. A soft sensor should move smoothly and monotonically here —
more of the volatile stream should raise the blend's bubble-point
pressure.
"""

# ╔═╡ a257933c-a25f-11f1-a504-cba55716eed2
begin
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

	plot(100 .* collect(share_range), rvp_curve;
		xlabel="Stream A share of total flow (%)",
		ylabel="Blend bubble-point pressure (kPa)",
		title="Soft-sensor response at $(round(Tblend_C, digits=1)) °C",
		legend=false, lw=2, marker=:circle, markersize=3)
end

# ╔═╡ a2579346-a25f-11f1-afcb-65b9d1b0b320
md"""
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
"""

# ╔═╡ Cell order:
# ╟─a2578e0a-a25f-11f1-912a-a7548e2945bd
# ╠═a2578e8c-a25f-11f1-aed3-2909b1692d1a
# ╠═a2578e96-a25f-11f1-a343-01595997ac9a
# ╠═a2578ea0-a25f-11f1-aea6-ebf1fab08c70
# ╟─a2578ea0-a25f-11f1-9898-ad9b6121781d
# ╠═a2578ea8-a25f-11f1-b68c-47304d34bbe5
# ╠═a2578eb4-a25f-11f1-ac10-191cd683d5f3
# ╟─a2578eb4-a25f-11f1-9684-277af3b809cc
# ╠═a2579044-a25f-11f1-ba55-d533cb9b6a0c
# ╟─a257904e-a25f-11f1-83e7-3dcec25a39a8
# ╟─a2579058-a25f-11f1-b570-fb92cb2e135f
# ╟─a2579062-a25f-11f1-a6ac-c165df4f261c
# ╟─a257906c-a25f-11f1-bb83-4ba72e0f3ebb
# ╟─a2579076-a25f-11f1-a920-81cfcc362b9d
# ╟─a2579080-a25f-11f1-bdf4-898ea44f3c8b
# ╠═a2579080-a25f-11f1-9ea5-714e43eaae90
# ╟─a257908a-a25f-11f1-af8a-05759ee9e45a
# ╠═a257908a-a25f-11f1-b34e-dde1620af4a2
# ╟─a2579094-a25f-11f1-8aff-3732706477ea
# ╠═a2579094-a25f-11f1-9a0e-c52d93030852
# ╟─a2579206-a25f-11f1-88e6-0fa97bfd3dd7
# ╠═a257933c-a25f-11f1-a504-cba55716eed2
# ╟─a2579346-a25f-11f1-afcb-65b9d1b0b320
