# EV Charging Widget — single-line smart status bar
# Only visible when car is plugged in.
#
# Run ./deploy.sh then copy the generated ev-widget-card.yaml
# into your main dashboard's raw config.

type: conditional
conditions:
  - condition: state
    entity: binary_sensor.goe_${GOE_SERIAL}_car_0
    state: "on"
card:
  type: markdown
  card_mod:
    style: |
      ha-card {
        padding: 8px 14px !important;
        font-size: 13px;
        background: var(--card-background-color);
      }
  content: >-
    {% set frc = states('select.goe_${GOE_SERIAL}_frc') %}
    {% set power = states('sensor.goe_${GOE_SERIAL}_nrg_11') | float(0) %}
    {% set price = states('sensor.electricity_price_${TIBBER_HOME}') | float(0) %}
    {% set next = states('sensor.ev_next_cheap_hour') %}
    {% set budget_used = states('sensor.ev_charging_cost_monthly') | float(0) %}
    {% set budget_max = states('input_number.ev_monthly_budget') | float(50) %}
    {% set voltage_status = states('sensor.ev_voltage_status') %}
    {% set force = states('input_boolean.ev_force_charge') %}
    {% set session_kwh = states('sensor.goe_${GOE_SERIAL}_wh') | float(0) %}
    {% set cheap_remaining = states('sensor.ev_cheap_hours_remaining') | int(0) %}
    {% set pot_kwh = states('sensor.ev_potential_energy_today') | float(0) %}
    {% set pot_km = states('sensor.ev_potential_range_today') | int(0) %}
    {% set consumption = states('input_number.ev_consumption_per_100km') | float(22) %}
    {% set session_km = (session_kwh / consumption * 100) | round(0) if consumption > 0 else 0 %}
    {# --- Icon --- #}
    {% if voltage_status in ['critical', 'reduce'] %}⚠️
    {% elif force == 'on' %}⚡
    {% elif power > 100 %}🟢
    {% elif frc == '1' %}⏸️
    {% else %}🔌
    {% endif %}
    {# --- Main info --- #}
    {% if power > 100 %}**{{ (power / 1000) | round(1) }} kW** · {{ '{:.1f}'.format(price * 100) }} ct · {{ session_kwh | round(1) }} kWh · +{{ session_km }} km · noch {{ cheap_remaining }}h · {{ pot_kwh | round(1) }} kWh / {{ pot_km }} km mögl.
    {% elif session_kwh > 0.1 %}{{ session_kwh | round(1) }} kWh (+{{ session_km }} km) · {{ '{:.1f}'.format(price * 100) }} ct · {% if next == 'now' %}▶ jetzt{% elif next == 'tomorrow' %}↗ morgen{% else %}↗ {{ next }}{% endif %} · {{ pot_kwh | round(1) }} kWh / {{ pot_km }} km mögl.
    {% elif budget_used >= budget_max %}Budget · {{ budget_used | round(0) }}/{{ budget_max | round(0) }} € ⛔
    {% elif voltage_status in ['critical', 'reduce'] %}{{ states('sensor.ev_house_voltage_l1') | round(0) }} V · {{ '{:.1f}'.format(price * 100) }} ct
    {% else %}{{ '{:.1f}'.format(price * 100) }} ct · {% if next == 'now' %}▶ jetzt{% elif next == 'tomorrow' %}↗ morgen{% else %}↗ {{ next }}{% endif %} · {{ pot_kwh | round(1) }} kWh / {{ pot_km }} km mögl.
    {% endif %}
