# Tech Stack

## Platform

- **Home Assistant** — automation platform (YAML-based configuration)
- **HA Packages** — single-file YAML bundles that group related entities, sensors, and automations

## Dependencies

- **ha-goecharger-api2** — HACS custom component for go-eCharger wallbox control (WebSocket + HTTP API v2)
- **Tibber integration** — official HA integration for electricity pricing (via Tibber Pulse)
- **REST sensor** — custom `sensor.tibber_prices` fetching hourly price arrays from Tibber GraphQL API
- **iOS Companion App** — `notify.mobile_app_*` for push notifications

## Template System

- `.tpl` files in `packages/` and `dashboard/` contain `${VARIABLE}` placeholders
- `deploy.sh` uses `envsubst` to substitute values from `.env` and writes final YAML to the HA config directory
- Environment variables: `GOE_SERIAL`, `TIBBER_HOME`, `IPHONE_DEVICE`, `TIBBER_GRAPH_CAMERA`

## Key HA Concepts Used

| Concept | Purpose |
|---|---|
| `input_boolean` | Feature toggles (smart charging, force charge) |
| `input_number` | Runtime-adjustable parameters (budget, thresholds, currents) |
| `template` sensors | Derived values (cost rate, voltage status, expected price) |
| `sensor.integration` | Riemann sum for accumulated cost |
| `utility_meter` | Monthly/quarterly/yearly reset cycles |
| `automation` | Scheduling logic, voltage protection, notifications |

## Commands

```bash
# Deploy templates to HA config volume
./deploy.sh                    # default target: /Volumes/config
./deploy.sh /path/to/config    # custom target

# After deploy: restart Home Assistant to pick up changes
```

## File Naming

- Templates: `*.yaml.tpl`
- Generated output: `*.yaml` (in HA config root, not committed here)
- Entity IDs: `ev_*` prefix for all EV-related entities
- Automation IDs: `ev_*` prefix (e.g., `ev_smart_charge_scheduler`)
