# Planned Features & Ideas

## Dynamic Amperage (Pending CEE Socket Installation)
*Currently postponed until the CEE blau 16A socket is installed (currently using Schuko).*

**Target hardware:** CEE blau 16A, 1-phase 230V → 1.38 kW (6A) to 3.68 kW (16A).

**Idea:** Automatically adjust the charging current based on the electricity price
and/or solar production.

Price-based tiers:
- **Negative prices:** Maximize current (16A / 3.68 kW) to profit as much as possible.
- **Very cheap:** ~12A for fast, cost-effective charging.
- **Normal cheap:** 8–10A for battery- and grid-friendly charging.
- **Top-up / solar-assisted:** 6A minimum to ride out leftover cheap window
  or maximize solar self-consumption share.

---

## Balkonkraftwerk (Yuma, ~800W) Integration

**Prerequisite hardware:** Production measurement required, e.g.:
- Shelly Plug S between inverter and Schuko socket (simple, ~30€), or
- OpenDTU / AhoyDTU on Hoymiles inverter (~20€ ESP32, more data).

**Integration ideas (once data is in HA):**

1. **Solar-aware cheap-hour threshold.**
   During active BKW production, the effective price is lower because part of the
   charging power comes from the roof. Combined with low amperage (6A at CEE blau),
   an 800W BKW covers ~58% of charging demand — meaningful savings even without
   full PV-surplus charging. Add bonus hours during solar production to the cheap
   schedule even when Tibber prices are slightly higher.

2. **Self-consumption tracking.**
   New sensors:
   - `sensor.ev_solar_share_monthly` — % of monthly charging covered by BKW.
   - `sensor.ev_solar_savings_monthly` — EUR saved vs. pure grid charging.

3. **Solar-adjusted monthly cost.**
   Subtract estimated self-consumed solar kWh × Tibber price from the monthly EV
   cost to show the real net spend.

4. **Forecast.Solar integration.**
   Use the free Forecast.Solar integration (based on GPS + roof orientation) to
   predict tomorrow's production curve and shift some charging into sunny hours
   when prices allow.

5. **Dashboard card.**
   New "☀️ Solar" section:
   - Live BKW production (W)
   - Today's production (kWh)
   - EV-consumed solar share (kWh / %)
   - Monthly savings (EUR)

**Not realistic with BKW alone:**
Full PV-surplus-only charging — even at the minimum 6A (1.38 kW), a single BKW
(~800W) cannot cover the demand. This would require a real PV system with
dedicated DC coupling or a larger inverter setup. Revisit if roof PV is ever
added.
