# ha-cost-optimized-ev-charging

Smart EV charging automation for Home Assistant using Tibber dynamic pricing and go-eCharger API v2.

## Features

- **Smart scheduling** — charges only during the X cheapest hours of the day (Tibber hourly prices)
- **Monthly EV cost budget** — tracks EV charging cost separately and stops when budget is reached
- **Voltage protection** — progressive action on low grid voltage (warn → reduce current → stop)
- **Force charge override** — manual dashboard toggle to charge regardless of price
- **iPhone push notifications** — on charge start/stop, voltage events, car connect/disconnect
- **Cost & energy tracking** — monthly, quarterly, yearly aggregation with dashboard visualization

## Requirements

- [ha-goecharger-api2](https://github.com/marq24/ha-goecharger-api2) custom component (HACS)
- [Tibber](https://www.home-assistant.io/integrations/tibber/) integration with Pulse
- iOS Companion App for push notifications
- REST sensor for `sensor.tibber_prices` (hourly price list)

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/nodomain/ha-cost-optimized-ev-charging.git
cd ha-cost-optimized-ev-charging

# 2. Create your .env from the example
cp .env.example .env
# Edit .env with your entity IDs (serial, tibber home slug, iphone device name)

# 3. Deploy to your HA config volume
./deploy.sh /Volumes/config   # or wherever your HA config is mounted

# 4. Add to configuration.yaml:
#    homeassistant:
#      packages:
#        ev_goe_tibber: !include ev-goe-tibber.yaml

# 5. Restart Home Assistant

# 6. Create dashboard: paste dashboard YAML into a new manual dashboard
```

## Configuration

All parameters are adjustable from the HA dashboard at runtime:

| Parameter | Default | Description |
|---|---|---|
| Monthly budget | 50 EUR | Max EV charging spend per month |
| Cheap hours/day | 6 | Number of cheapest hours to charge |
| Normal current | 10 A | Standard charging current (Schuko) |
| Safe current | 6 A | Reduced current on low voltage |
| Voltage warn | 215 V | Notification threshold |
| Voltage reduce | 210 V | Current reduction threshold |
| Voltage stop | 208 V | Force-stop threshold |

## How It Works

```
Every minute (+ on car connect, + on price change):
  1. Fetch today's 24 hourly prices from Tibber
  2. Sort prices, find threshold for X cheapest hours
  3. Check: current hour price ≤ threshold?
  4. Check: monthly EV cost < budget?
  5. Check: voltage OK? Price data available?
  6. All true → frc=2 (force charge) + iPhone notification
  7. Any false → frc=1 (force stop) + iPhone notification (on transition only)
```

**Important:** The automation uses `frc=1` (force stop) to prevent charging,
not `frc=0` (neutral). Neutral would let the wallbox charge in its default mode.

## File Structure

```
├── README.md
├── .env.example                          # Template for personal config
├── .gitignore                            # Excludes .env
├── deploy.sh                             # Generates YAML from templates + .env
├── packages/
│   └── ev-goe-tibber.yaml.tpl           # HA package template
└── dashboard/
    └── ev-goe-tibber-dashboard.yaml.tpl  # Dashboard template
```

## Environment Variables (.env)

| Variable | Example | Description |
|---|---|---|
| `GOE_SERIAL` | `123456` | go-eCharger serial (from entity IDs like `sensor.goe_XXXXXX_nrg_11`) |
| `TIBBER_HOME` | `musterstrasse_1` | Tibber home slug (from `sensor.electricity_price_XXXXX`) |
| `IPHONE_DEVICE` | `my_iphone` | iPhone device name (from `notify.mobile_app_XXXXX`) |
| `TIBBER_GRAPH_CAMERA` | `camera.tibber_graph_musterstrasse_1` | Tibber graph camera entity |

## Cost Tracking

EV charging cost is tracked separately from household electricity:

```
Charging power (W) × Electricity price (EUR/kWh) = Cost rate (EUR/h)
  → Riemann sum integration → Total cost (EUR)
    → Utility meters → Monthly / Quarterly / Yearly
```

Energy consumption is tracked in parallel via the wallbox's built-in energy counter.

## Voltage Protection

| Voltage | Status | Action |
|---|---|---|
| > 215 V | ok | Normal charging |
| ≤ 215 V (2 min) | warning | iPhone notification |
| ≤ 210 V (30 sec) | reduce | Current reduced to safe level |
| ≤ 208 V (20 sec) | critical | Charging force-stopped |
| > 215 V (3 min) | recovered | Current restored to normal |

## Automations

| ID | Trigger | Action |
|---|---|---|
| `ev_smart_charge_scheduler` | Every min + car connect + price change | Start/stop based on price + budget |
| `ev_force_charge_on/off` | Dashboard toggle | Manual override |
| `ev_voltage_*` | Voltage thresholds | Warn → reduce → stop → restore |
| `ev_car_connected/disconnected` | Plug state change | Notify + reset on disconnect |
| `ev_ha_start_reset` | HA boot | Reset force charge toggle |

## Key Entities Created

| Entity | Description |
|---|---|
| `sensor.ev_charging_cost_rate` | Instantaneous cost rate (EUR/h) |
| `sensor.ev_charging_cost_total` | Accumulated total EV cost (EUR) |
| `sensor.ev_charging_cost_monthly` | EV cost this month (resets 1st) |
| `sensor.ev_charging_cost_yearly` | EV cost this year (resets Jan 1) |
| `sensor.ev_energy_monthly` | EV energy this month (kWh) |
| `sensor.ev_energy_yearly` | EV energy this year (kWh) |
| `sensor.ev_average_price_per_kwh_monthly` | Avg price paid per kWh |
| `sensor.ev_voltage_status` | ok / warning / reduce / critical |

## License

MIT
