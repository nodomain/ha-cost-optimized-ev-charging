# Project Structure

```
ha-cost-optimized-ev-charging/
├── .env.example              # Template for personal config (committed)
├── .env                      # Actual config with entity IDs (gitignored)
├── .gitignore
├── deploy.sh                 # Generates YAML from templates + deploys
├── README.md
├── packages/
│   └── ev-goe-tibber.yaml.tpl       # HA package template (automations, sensors, inputs)
└── dashboard/
    └── ev-goe-tibber-dashboard.yaml.tpl  # Lovelace dashboard template
```

## Deployment Target

The generated files land in the Home Assistant config directory (default `/Volumes/config`):

- `ev-goe-tibber.yaml` — included via `configuration.yaml` as a package
- `ev-goe-tibber-dashboard.yaml` — pasted into a manual Lovelace dashboard

## Package YAML Structure (ev-goe-tibber.yaml.tpl)

The package template is organized in sections separated by comment banners:

1. **Input booleans** — feature toggles
2. **Input numbers** — adjustable parameters
3. **Template sensors** — cost rate, voltage status, expected price, binary sensors
4. **Integration sensor** — Riemann sum for accumulated cost
5. **Utility meters** — monthly/quarterly/yearly aggregation
6. **Automations** — scheduling, force charge, voltage protection, notifications, safety reset

## Conventions

- All EV-related entity IDs use the `ev_` prefix
- Automation IDs match the pattern `ev_<feature>_<action>` (e.g., `ev_voltage_reduce_current`)
- Section headers use `# ===` banner comments for top-level sections, `# ---` for sub-sections
- Template variables use `${VAR}` syntax (shell envsubst)
- Comments explain *why*, not *what* — especially for non-obvious choices like `frc=1` vs `frc=0`
- Notifications include contextual data (price, budget, energy) not just status
