# EV Charging Widget — compact two-line status bar
# Only visible when car is plugged in.
# Line 1: status · price · power · session
# Line 2: next slot · remaining potential (kWh + km)
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
        line-height: 1.6;
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
    {# === LINE 1: Status · Price · Power · Session === #}
    {% if voltage_status in ['critical', 'reduce'] %}⚠️
    {% elif force == 'on' %}⚡
    {% elif power > 100 %}🟢
    {% elif frc == '1' %}⏸️
    {% else %}🔌
    {% endif %}
    {% if power > 100 %}**{{ (power / 1000) | round(1) }} kW** · {{ '{:.1f}'.format(price * 100) }} ct · {{ session_kwh | round(1) }} kWh · +{{ session_km }} km
    {% elif session_kwh > 0.1 %}{{ session_kwh | round(1) }} kWh (+{{ session_km }} km) geladen · {{ '{:.1f}'.format(price * 100) }} ct
    {% elif budget_used >= budget_max %}Budget erreicht · {{ budget_used | round(0) }}/{{ budget_max | round(0) }} €
    {% elif voltage_status in ['critical', 'reduce'] %}{{ states('sensor.ev_house_voltage_l1') | round(0) }} V · {{ '{:.1f}'.format(price * 100) }} ct
    {% else %}Bereit · {{ '{:.1f}'.format(price * 100) }} ct
    {% endif %}

    {# === LINE 2: Schedule + Remaining potential === #}
    🕐
    {% if power > 100 and cheap_remaining > 0 %}noch {{ cheap_remaining }}h günstig
    {% elif next == 'now' %}günstig — jetzt laden
    {% elif next == 'tomorrow' %}nächste Slot morgen
    {% elif next == 'unknown' %}kein Preisplan
    {% else %}nächster Slot {{ next }}
    {% endif %}
    {% if pot_kwh > 0 %} · ⚡ {{ pot_kwh | round(1) }} kWh / {{ pot_km }} km möglich{% endif %}
