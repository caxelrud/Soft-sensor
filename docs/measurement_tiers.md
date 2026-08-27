# Measurement tiers

A soft sensor's design is dictated by what's actually instrumented on the
real unit — not by what's convenient to assume. The less state information
(compositions, temperatures, pressures at the relevant location) is
directly measured, the more the soft sensor has to *simulate* to
reconstruct the missing states, rather than just evaluate a property from
already-known conditions. This is a primary axis for scoping every
notebook in this repo, alongside the unit operation itself.

Every notebook should state its assumed measurement set explicitly (see
"Notebook convention" below) so it's clear which tier it belongs to and,
therefore, what class of method is doing the real work.

## Tier A — Direct calculation

**Assumed available:** full stream composition (GC/analyzer) *and*
temperature *and* pressure at the point of interest.

**Method:** the soft sensor is a stateless property evaluation — plug
measured (T, P, x) into an EOS/thermodynamic model and read off the
target property (bubble point, K-values, enthalpy, ...). No simulation of
the surrounding process is needed; the model only has to get the
thermodynamics right.

**Example in this repo:** `notebooks/01_lpg_rvp_soft_sensor.jl` — full
composition and temperature assumed known, bubble-point pressure computed
directly via Clapeyron.jl PR EOS. This is the easy case and mainly a
vehicle for the thermodynamics layer; real deployments rarely have this
much instrumentation for the exact property they want to know (usually a
lab analyzer *is* the missing measurement).

## Tier B — Local inversion / reconciliation

**Assumed available:** temperature and pressure at the point of interest,
but *not* full composition (e.g. no online GC on this stream).

**Method:** composition can't be read directly, so it has to be inferred
by inverting a local equilibrium relationship — e.g. back out composition
from a measured tray temperature and pressure assuming vapor-liquid
equilibrium at that tray, or reconcile a partial/lagged composition
measurement (an infrequent lab sample) against the continuous T/P signal.
This still leans on the same EOS/equilibrium model as Tier A, but now
solved in the inverse direction, and typically needs a data-driven
bias/trim correction fit against periodic lab results since the
equilibrium-stage assumption is itself an approximation.

**Planned example:** tray-temperature-to-composition inference for a
debutanizer/depropanizer (see roadmap).

## Tier C — Process simulation / state estimation

**Assumed available:** only a handful of temperatures and pressures at
unit boundaries or a few internal points — no composition measurements
anywhere near the target, and not even every tray/stage instrumented.

**Method:** local inversion (Tier B) no longer has enough information;
the missing states have to be reconstructed by simulating the whole unit
(mass/energy balances across all stages, not just one) and adjusting the
simulation until it's consistent with the few available measurements.
This is a state-estimation problem, not just a thermodynamics problem —
techniques like data reconciliation, moving-horizon estimation, or a
Kalman/particle filter over a reduced-order dynamic model are the
relevant tools, with Clapeyron.jl supplying the thermodynamics inside
that larger model rather than being the whole soft sensor. Computationally
heavier, more assumptions baked in (tray efficiencies, holdups, unmeasured
disturbances), and correspondingly needs more validation against plant
data before it can be trusted.

**Planned example:** stabilizer column RVP soft sensor when only feed and
overhead/bottoms temperatures are available (no intermediate tray
temperatures, no online composition).

## Notebook convention

Each notebook should open with a short "Measurements assumed" block (in
its intro markdown cell) stating exactly which tags/measurements are
taken as given vs. inferred vs. simulated, e.g.:

```
**Measurements assumed available:** stream composition (x), temperature (T).
**Inferred / computed by this soft sensor:** bubble-point pressure (RVP proxy).
**Tier:** A — direct calculation, no process simulation required.
```

This keeps the modeling honest: it's easy to accidentally build a Tier A
demo (assume composition is known) for a problem that's actually Tier B or
C in the field (composition is exactly what's *not* measured). When
scoping a new soft sensor, start from the real instrumentation list for
the target unit, classify the tier first, and only then pick the method.
