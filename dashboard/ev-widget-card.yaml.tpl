# EV Charging Widget — compact card for main dashboard
# Only visible when car is plugged in.
# Run ./deploy.sh then copy the generated ev-widget-card.yaml
# into your main dashboard's raw config.

type: conditional
conditions:
  - condition: state
    entity: binary_sensor.goe_${GOE_SERIAL}_car_0
    state: "on"
card:
  type: glance
  title: null
  columns: 4
  show_name: true
  show_state: true
  entities:
    - entity: sensor.goe_${GOE_SERIAL}_car_value
      name: "🔌 EV"
    - entity: sensor.electricity_price_${TIBBER_HOME}
      name: Price
    - entity: sensor.goe_${GOE_SERIAL}_nrg_11
      name: Power
    - entity: sensor.ev_next_cheap_hour
      name: Next
