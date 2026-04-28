# Product

Smart EV charging automation for Home Assistant. Optimizes charging cost by scheduling sessions during the cheapest hours of the day using Tibber dynamic electricity pricing, controlled via the go-eCharger API v2 wallbox integration.

## Core Capabilities

- **Price-based scheduling** — charges only during the X cheapest hours per day (configurable)
- **Monthly budget cap** — tracks EV-specific cost and stops when budget is reached
- **Voltage protection** — progressive response to low grid voltage (warn → reduce current → force-stop)
- **Force charge override** — manual dashboard toggle to bypass scheduling
- **Push notifications** — iPhone alerts on charge start/stop, voltage events, car connect/disconnect
- **Cost & energy tracking** — separate EV metering with monthly/quarterly/yearly aggregation

## Hardware Context

- **Wallbox:** go-eCharger V4, 11 kW, single-phase (Schuko), local WebSocket connection
- **Energy provider:** Tibber with Pulse (hourly dynamic pricing, Germany)
- **Smart meter:** Tibber Pulse provides real-time voltage and consumption
- **Notifications:** iOS Companion App (iPhone)

## Key Design Decisions

- Uses `frc=2` (force charge) and `frc=1` (force stop) — never `frc=0` (neutral) during active scheduling, because neutral lets the wallbox charge in its default mode
- Cost tracking uses Riemann sum integration of (power × price) rather than relying on wallbox energy counters for cost
- All runtime parameters are adjustable from the HA dashboard without restarting
- Templates are parameterized via environment variables to keep personal data (serial numbers, addresses) out of version control
