# ha-cost-optimized-ev-charging

Smart EV charging automation for Home Assistant using Tibber dynamic pricing and go-eCharger API v2.

## Features

- **Smart scheduling** — charges only during the X cheapest hours of the day (Tibber hourly prices)
- **Overnight charging** — combines today + tomorrow prices for optimal scheduling across midnight
- **Monthly EV cost budget** — tracks EV-specific cost and stops when budget is reached
- **Tomorrow preview** — shows tomorrow's cheapest hours and expected price (available after ~13:00)
- **Next cheap hour** — tells you when the next charging window starts
- **Cost forecast** — projects current spending to end of month
- **Session logging** — logs energy, cost, and totals on every disconnect
- **Voltage protection** — progressive action on low grid voltage (warn → reduce current → stop)
- **Force charge override** — manual dashboard toggle to bypass scheduling
- **Push notifications** — iPhone alerts on charge start/stop, voltage events, car connect/disconnect
- **Range estimation** — shows potential kWh and km based on configured cheap hours and current

## Requirements

- [ha-goecharger-api2](https://github.com/marq24/ha-goecharger-api2) custom component (HACS)
- [Tibber](https://www.home-assistant.io/integrations/tibber/) integration with Pulse
- iOS Companion App for push notifications
- REST sensor for `sensor.tibber_prices` (hourly price list with `today` + `tomorrow` attributes)

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

# 6. Create dashboard: paste ev-goe-tibber-dashboard.yaml into a new manual dashboard
```

## Configuration

All parameters are adjustable from the HA dashboard at runtime:

| Parameter | Default | Description |
|---|---|---|
| Monthly budget | 50 EUR | Max EV charging spend per month |
| Cheap hours/day | 6 | Number of cheapest hours to charge |
| Normal current | 10 A | Standard charging current (Schuko) |
| Safe current | 6 A | Reduced current on low voltage |
| Consumption | 22 kWh/100km | Vehicle efficiency for range calculation |
| Voltage warn | 215 V | Notification threshold |
| Voltage reduce | 210 V | Current reduction threshold |
| Voltage stop | 208 V | Force-stop threshold |

## How It Works

### Scheduling Logic

```
Every minute (+ on car connect, + on price change):
  1. Fetch today's 24 hourly prices (+ tomorrow's if available)
  2. Sort combined prices, find threshold for X cheapest hours
  3. Check: current hour price ≤ threshold?
  4. Check: monthly EV cost < budget?
  5. Check: voltage OK? Price data available?
  6. All true → frc=2 (force charge) + iPhone notification
  7. Any false → frc=1 (force stop) + notification (on transition only)
```

### Overnight Charging

When tomorrow's prices are available (after ~13:00), the scheduler combines today + tomorrow
into a 48-hour window. This means if the cheapest hours span midnight (e.g. 23:00–03:00),
the car will charge through the night without interruption.

### Force Charge Control

- `frc=2` → force start (cheap hour + budget OK)
- `frc=1` → force stop (price too high / budget exceeded / voltage low)
- `frc=0` → neutral (only when car disconnected)

**Important:** `frc=0` does NOT stop charging — it lets the wallbox decide on its own.
The automation always uses `frc=1` to actively prevent charging during expensive hours.

## File Structure

```
├── README.md
├── .env.example                          # Template for personal config
├── .gitignore                            # Excludes .env
├── deploy.sh                             # Generates YAML from templates + .env
├── packages/
│   └── ev-goe-tibber.yaml.tpl           # HA package template
└── dashboard/
    └── ev-goe-tibber-dashboard.yaml.tpl  # Dashboard template (2 views)
```

## Environment Variables (.env)

| Variable | Example | Description |
|---|---|---|
| `GOE_SERIAL` | `123456` | go-eCharger serial (from entity IDs like `sensor.goe_XXXXXX_nrg_11`) |
| `TIBBER_HOME` | `musterstrasse_1` | Tibber home slug (from `sensor.electricity_price_XXXXX`) |
| `IPHONE_DEVICE` | `my_iphone` | iPhone device name (from `notify.mobile_app_XXXXX`) |
| `TIBBER_GRAPH_CAMERA` | `camera.tibber_graph_musterstrasse_1` | Tibber graph camera entity |

## Sensors Created

### Scheduling & Planning

| Entity | Description |
|---|---|
| `sensor.ev_expected_price_today` | Avg price of today's X cheapest hours |
| `sensor.ev_cheap_hours_remaining` | How many cheap hours are left today |
| `sensor.ev_potential_energy_today` | Remaining kWh possible today |
| `sensor.ev_potential_range_today` | Remaining km possible today |
| `sensor.ev_next_cheap_hour` | "now" / "in Xh (HH:00)" / "tomorrow" |
| `sensor.ev_tomorrow_cheapest_hours` | Tomorrow's cheap hour indices (e.g. "10, 11, 12, 13, 14, 15h") |
| `sensor.ev_tomorrow_expected_price` | Avg price of tomorrow's X cheapest hours |
| `sensor.ev_monthly_cost_forecast` | Projected monthly cost based on current pace |

### Cost & Energy Tracking

| Entity | Description |
|---|---|
| `sensor.ev_charging_cost_rate` | Instantaneous cost rate (EUR/h) |
| `sensor.ev_charging_cost_total` | Accumulated total EV cost (EUR) |
| `sensor.ev_charging_cost_monthly` | EV cost this month (resets 1st) |
| `sensor.ev_charging_cost_quarterly` | EV cost this quarter |
| `sensor.ev_charging_cost_yearly` | EV cost this year |
| `sensor.ev_energy_monthly` | EV energy this month (kWh) |
| `sensor.ev_energy_quarterly` | EV energy this quarter |
| `sensor.ev_energy_yearly` | EV energy this year |
| `sensor.ev_average_price_per_kwh_monthly` | Avg price paid per kWh this month |

### Voltage Monitoring

| Entity | Description |
|---|---|
| `sensor.ev_voltage_status` | ok / warning / reduce / critical |
| `sensor.ev_house_voltage_l1` | Grid voltage L1 |
| `binary_sensor.ev_voltage_warning_zone` | Voltage in warning range |
| `binary_sensor.ev_voltage_reduce_zone` | Voltage in reduce range |
| `binary_sensor.ev_voltage_critical_zone` | Voltage in critical range |

## Automations

| ID | Trigger | Action |
|---|---|---|
| `ev_smart_charge_scheduler` | Every min + car connect + price change | Start/stop based on price + budget (48h window) |
| `ev_force_charge_on/off` | Dashboard toggle | Manual override |
| `ev_voltage_*` | Voltage thresholds | Warn → reduce → stop → restore |
| `ev_car_connected` | Car plugged in | Notify with price + budget info |
| `ev_car_disconnected` | Car unplugged | Session log + reset + notify |
| `ev_ha_start_reset` | HA boot | Reset force charge toggle |

## Dashboard

Two views optimized for readability:

**View 1: Charging** (daily use)
- Tibber price graph
- Charger status (car, mode, current, power, session)
- Budget gauge + monthly cost/energy
- Scheduling (cheap hours, next cheap hour, potential energy/range)
- Tomorrow preview
- Cost forecast
- Quick action buttons

**View 2: Settings** (configure once)
- Voltage protection thresholds
- Charging parameters
- Detailed go-eCharger entities
- Detailed Tibber/Grid entities
- Voltage gauges + history
- Cost & energy summary (monthly/quarterly/yearly)
- Statistics bar charts

## Voltage Protection

| Voltage | Status | Action |
|---|---|---|
| > 215 V | ok | Normal charging |
| ≤ 215 V (2 min) | warning | iPhone notification |
| ≤ 210 V (30 sec) | reduce | Current reduced to 6 A |
| ≤ 208 V (20 sec) | critical | Charging force-stopped |
| > 215 V (3 min) | recovered | Current restored to 10 A |

## Cost Tracking

```
Charging power (W) × Electricity price (EUR/kWh) = Cost rate (EUR/h)
  → Riemann sum integration → Total cost (EUR)
    → Utility meters → Monthly / Quarterly / Yearly
```

On each car disconnect, a session summary is logged:
- Session energy (kWh) and estimated cost (EUR)
- Monthly totals
- HA event `ev_charging_session_complete` fired (visible in logbook)

## License

MIT
