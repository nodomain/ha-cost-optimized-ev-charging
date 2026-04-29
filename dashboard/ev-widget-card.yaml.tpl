# EV Charging Widget — ultra-compact for wall displays
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
  show_name: false
  show_icon: false
  show_state: true
  entities:
    - entity: sensor.goe_${GOE_SERIAL}_car_value
    - entity: sensor.electricity_price_${TIBBER_HOME}
    - entity: sensor.goe_${GOE_SERIAL}_nrg_11
    - entity: sensor.ev_next_cheap_hour
