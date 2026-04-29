###############################################################################
# PACKAGE: ev-goe-tibber.yaml
#
# Smart EV charging with Tibber dynamic pricing + go-eCharger API v2.
#
# Features:
#   - Smart scheduling: charge only during the X cheapest hours of the day
#   - Monthly EV cost budget: stops charging when budget is reached
#   - EV cost tracking: separate from household (monthly/quarterly/yearly)
#   - Voltage protection: warn → reduce current → stop on low voltage
#   - Force charge override via dashboard toggle
#   - iPhone push notifications on charge start/stop/voltage events
#
# go-eCharger: V4 11 kW, serial ${GOE_SERIAL}, local WebSocket, FW 59.4
# Tibber Pulse: Hofreuthackerstraße 23
# iPhone: notify.mobile_app_${IPHONE_DEVICE}
###############################################################################

# =============================================================================
# INPUT BOOLEANS
# =============================================================================
input_boolean:
  ev_smart_charging_enabled:
    name: "EV smart charging enabled"
    icon: mdi:ev-station
    initial: true

  ev_force_charge:
    name: "EV force charge override"
    icon: mdi:flash

# =============================================================================
# INPUT NUMBERS — dashboard-adjustable parameters
# =============================================================================
input_number:
  # --- Budget & scheduling ---
  ev_monthly_budget:
    name: "EV monthly charging budget"
    min: 0
    max: 300
    step: 5
    unit_of_measurement: "EUR"
    icon: mdi:cash-check
    mode: slider
    initial: 50

  ev_cheap_hours:
    name: "EV cheap hours to charge per day"
    min: 1
    max: 12
    step: 1
    icon: mdi:clock-outline
    mode: slider
    initial: 6

  # --- Charging current ---
  ev_current_safe:
    name: "EV safe current (reduced)"
    min: 6
    max: 16
    step: 1
    unit_of_measurement: "A"
    icon: mdi:current-ac
    mode: box
    initial: 6

  ev_current_normal:
    name: "EV normal charging current"
    min: 6
    max: 16
    step: 1
    unit_of_measurement: "A"
    icon: mdi:current-ac
    mode: box
    initial: 10

  # --- Vehicle parameters ---
  ev_consumption_per_100km:
    name: "EV consumption per 100 km"
    min: 10
    max: 40
    step: 0.5
    unit_of_measurement: "kWh/100km"
    icon: mdi:car-electric-outline
    mode: box
    initial: 22

  ev_target_soc:
    name: "EV target state of charge"
    min: 50
    max: 100
    step: 5
    unit_of_measurement: "%"
    icon: mdi:battery-charging-80
    mode: slider
    initial: 80

  # --- Voltage protection thresholds ---
  ev_voltage_warn:
    name: "EV voltage warning threshold"
    min: 190
    max: 240
    step: 1
    unit_of_measurement: "V"
    icon: mdi:flash-alert
    mode: box
    initial: 215

  ev_voltage_reduce:
    name: "EV voltage reduce threshold"
    min: 190
    max: 240
    step: 1
    unit_of_measurement: "V"
    icon: mdi:flash-alert-outline
    mode: box
    initial: 210

  ev_voltage_stop:
    name: "EV voltage stop threshold"
    min: 190
    max: 240
    step: 1
    unit_of_measurement: "V"
    icon: mdi:flash-off
    mode: box
    initial: 208

# =============================================================================
# TEMPLATE SENSORS
# =============================================================================
template:
  # --- Trigger-based price cache: fetches from official Tibber integration ---
  - triggers:
      - trigger: time_pattern
        minutes: "/15"
      - trigger: homeassistant
        event: start
    action:
      - action: tibber.get_prices
        data:
          start: "{{ today_at('00:00') }}"
          end: "{{ today_at('23:59') }}"
        response_variable: today_resp
      - action: tibber.get_prices
        data:
          start: "{{ (today_at('00:00') + timedelta(days=1)).isoformat() }}"
          end: "{{ (today_at('23:59') + timedelta(days=1)).isoformat() }}"
        response_variable: tomorrow_resp
        continue_on_error: true
    sensor:
      - name: "EV price cache"
        unique_id: ev_price_cache
        icon: mdi:cash-sync
        state: "{{ now().isoformat() }}"
        attributes:
          today: >-
            {% set entries = today_resp.prices.values() | first | default([]) %}
            {% set ns = namespace(hourly=[]) %}
            {% for i in range(0, entries | length, 4) %}
              {% set ns.hourly = ns.hourly + [{'total': entries[i].price}] %}
            {% endfor %}
            {{ ns.hourly }}
          tomorrow: >-
            {% if tomorrow_resp is defined and tomorrow_resp.prices is defined %}
              {% set entries = tomorrow_resp.prices.values() | first | default([]) %}
              {% if entries | length >= 96 %}
                {% set ns = namespace(hourly=[]) %}
                {% for i in range(0, entries | length, 4) %}
                  {% set ns.hourly = ns.hourly + [{'total': entries[i].price}] %}
                {% endfor %}
                {{ ns.hourly }}
              {% else %}
                {{ none }}
              {% endif %}
            {% else %}
              {{ none }}
            {% endif %}

  # --- All EV sensors in one consolidated block ---
  - sensor:
      - name: "EV charging cost rate"
        unique_id: ev_charging_cost_rate
        unit_of_measurement: "EUR/h"
        state_class: measurement
        icon: mdi:cash-clock
        state: >-
          {% set power_w = states('sensor.goe_${GOE_SERIAL}_nrg_11') | float(0) %}
          {% set price = states('sensor.electricity_price_${TIBBER_HOME}') | float(0) %}
          {{ (power_w / 1000 * price) | round(3) }}
        availability: >-
          {{ has_value('sensor.goe_${GOE_SERIAL}_nrg_11')
             and has_value('sensor.electricity_price_${TIBBER_HOME}') }}

      - name: "EV average price per kWh monthly"
        unique_id: ev_avg_price_kwh_monthly
        unit_of_measurement: "EUR/kWh"
        icon: mdi:chart-line
        state: >-
          {% set cost = states('sensor.ev_charging_cost_monthly') | float(0) %}
          {% set energy = states('sensor.ev_energy_monthly') | float(0) %}
          {{ (cost / energy) | round(3) if energy > 0 else 0 }}
        availability: >-
          {{ has_value('sensor.ev_charging_cost_monthly')
             and has_value('sensor.ev_energy_monthly') }}

      - name: "EV expected price today"
        unique_id: ev_expected_price_today
        unit_of_measurement: "EUR/kWh"
        icon: mdi:crystal-ball
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% if raw is not none and raw | length > 0 %}
            {% set prices = raw | map(attribute='total') | list %}
            {% set hours = states('input_number.ev_cheap_hours') | int(6) %}
            {% if prices | length >= hours %}
              {% set cheap = (prices | sort)[:hours] %}
              {{ (cheap | sum / cheap | length) | round(3) }}
            {% else %}
              {{ 0 }}
            {% endif %}
          {% else %}
            {{ 0 }}
          {% endif %}
        availability: >-
          {{ state_attr('sensor.ev_price_cache', 'today') is not none }}

      - name: "EV potential energy today"
        unique_id: ev_potential_energy_today
        unit_of_measurement: "kWh"
        icon: mdi:battery-charging
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set hours = states('input_number.ev_cheap_hours') | int(6) %}
          {% set current_hour = now().hour %}
          {% set remaining_prices = prices[current_hour:] %}
          {% set sorted_all = prices | sort %}
          {% set threshold = sorted_all[hours - 1] if sorted_all | length >= hours else 999 %}
          {% set cheap_remaining = remaining_prices | select('le', threshold) | list %}
          {% set amps = states('input_number.ev_current_normal') | float(10) %}
          {% set voltage = 230 %}
          {{ (cheap_remaining | length * amps * voltage / 1000) | round(1) }}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {{ raw is not none and raw | length >= 24 }}

      - name: "EV potential range today"
        unique_id: ev_potential_range_today
        unit_of_measurement: "km"
        icon: mdi:map-marker-distance
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set hours = states('input_number.ev_cheap_hours') | int(6) %}
          {% set current_hour = now().hour %}
          {% set remaining_prices = prices[current_hour:] %}
          {% set sorted_all = prices | sort %}
          {% set threshold = sorted_all[hours - 1] if sorted_all | length >= hours else 999 %}
          {% set cheap_remaining = remaining_prices | select('le', threshold) | list %}
          {% set amps = states('input_number.ev_current_normal') | float(10) %}
          {% set voltage = 230 %}
          {% set kwh = cheap_remaining | length * amps * voltage / 1000 %}
          {% set consumption = states('input_number.ev_consumption_per_100km') | float(22) %}
          {{ (kwh / consumption * 100) | round(0) }}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {{ raw is not none and raw | length >= 24 }}

      - name: "EV cheap hours remaining"
        unique_id: ev_cheap_hours_remaining
        unit_of_measurement: "h"
        icon: mdi:clock-fast
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set hours = states('input_number.ev_cheap_hours') | int(6) %}
          {% set current_hour = now().hour %}
          {% set remaining_prices = prices[current_hour:] %}
          {% set sorted_all = prices | sort %}
          {% set threshold = sorted_all[hours - 1] if sorted_all | length >= hours else 999 %}
          {{ remaining_prices | select('le', threshold) | list | length }}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {{ raw is not none and raw | length >= 24 }}

      - name: "EV tomorrow cheapest hours"
        unique_id: ev_tomorrow_cheapest_hours
        icon: mdi:calendar-arrow-right
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'tomorrow') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set hours = states('input_number.ev_cheap_hours') | int(6) %}
          {% set sorted = prices | sort %}
          {% set threshold = sorted[hours - 1] %}
          {% set ns = namespace(indices=[]) %}
          {% for p in prices %}
            {% if p <= threshold and ns.indices | length < hours %}
              {% set ns.indices = ns.indices + [loop.index0] %}
            {% endif %}
          {% endfor %}
          {{ ns.indices | map('string') | join(', ') }}h
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'tomorrow') %}
          {{ raw is not none and raw | length >= 24 }}

      - name: "EV tomorrow expected price"
        unique_id: ev_tomorrow_expected_price
        unit_of_measurement: "EUR/kWh"
        icon: mdi:calendar-clock
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'tomorrow') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set hours = states('input_number.ev_cheap_hours') | int(6) %}
          {% set cheap = (prices | sort)[:hours] %}
          {{ (cheap | sum / cheap | length) | round(3) }}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'tomorrow') %}
          {{ raw is not none and raw | length >= 24 }}

      - name: "EV next cheap hour"
        unique_id: ev_next_cheap_hour
        icon: mdi:clock-start
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set hours = states('input_number.ev_cheap_hours') | int(6) %}
          {% set current_hour = now().hour %}
          {% set sorted_all = prices | sort %}
          {% set threshold = sorted_all[hours - 1] if sorted_all | length >= hours else 999 %}
          {% set ns = namespace(found=-1) %}
          {% for h in range(current_hour, 24) %}
            {% if prices[h] <= threshold and ns.found == -1 %}
              {% set ns.found = h %}
            {% endif %}
          {% endfor %}
          {% if ns.found == current_hour %}
            now
          {% elif ns.found >= 0 %}
            {{ '%02d' | format(ns.found) }}:00
          {% else %}
            tomorrow
          {% endif %}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {{ raw is not none and raw | length >= 24 }}

      - name: "EV monthly cost forecast"
        unique_id: ev_monthly_cost_forecast
        unit_of_measurement: "EUR"
        icon: mdi:chart-timeline-variant
        state: >-
          {% set cost_so_far = states('sensor.ev_charging_cost_monthly') | float(0) %}
          {% set day_of_month = now().day %}
          {% if day_of_month > 1 and cost_so_far > 0 %}
            {% set days_in_month = ((now().replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)).day %}
            {{ (cost_so_far / day_of_month * days_in_month) | round(2) }}
          {% else %}
            {{ cost_so_far | round(2) }}
          {% endif %}
        availability: >-
          {{ has_value('sensor.ev_charging_cost_monthly') }}

      - name: "EV monthly range forecast"
        unique_id: ev_monthly_range_forecast
        unit_of_measurement: "km"
        icon: mdi:road-variant
        state: >-
          {% set hours = states('input_number.ev_cheap_hours') | float(6) %}
          {% set amps = states('input_number.ev_current_normal') | float(10) %}
          {% set voltage = 230 %}
          {% set consumption = states('input_number.ev_consumption_per_100km') | float(22) %}
          {% set budget = states('input_number.ev_monthly_budget') | float(50) %}
          {% set avg_price = states('sensor.ev_expected_price_today') | float(0.20) %}
          {% set days_in_month = ((now().replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)).day %}
          {% set daily_kwh = hours * amps * voltage / 1000 %}
          {% set monthly_kwh_unlimited = daily_kwh * days_in_month %}
          {% set budget_limited_kwh = budget / avg_price if avg_price > 0 else monthly_kwh_unlimited %}
          {% set monthly_kwh = [monthly_kwh_unlimited, budget_limited_kwh] | min %}
          {{ (monthly_kwh / consumption * 100) | round(0) }}
        availability: >-
          {{ has_value('sensor.ev_expected_price_today')
             and has_value('input_number.ev_cheap_hours')
             and has_value('input_number.ev_current_normal') }}

      # --- SoC-based hours calculation ---
      - name: "EV hours needed to target"
        unique_id: ev_hours_needed_to_target
        unit_of_measurement: "h"
        icon: mdi:clock-check-outline
        state: >-
          {% set soc = states('sensor.ix1_xdrive30_battery_hv_state_of_charge') | float(0) %}
          {% set target = states('input_number.ev_target_soc') | float(80) %}
          {% set capacity_kwh = 64.7 %}
          {% set power_kw = states('input_number.ev_current_normal') | float(10) * 230 / 1000 %}
          {% set kwh_needed = (target - soc) / 100 * capacity_kwh %}
          {% if kwh_needed > 0 and power_kw > 0 %}
            {{ (kwh_needed / power_kw) | round(1) }}
          {% else %}
            {{ 0 }}
          {% endif %}
        availability: >-
          {{ has_value('sensor.ix1_xdrive30_battery_hv_state_of_charge') }}

      - name: "EV charging efficiency"
        unique_id: ev_charging_efficiency
        unit_of_measurement: "%"
        icon: mdi:transmission-tower-import
        state_class: measurement
        state: >-
          {% set wallbox_w = states('sensor.goe_${GOE_SERIAL}_nrg_11') | float(0) %}
          {% set bmw_w = states('sensor.ix1_xdrive30_battery_ev_charging_power') | float(0) %}
          {% if wallbox_w > 100 and bmw_w > 0 %}
            {{ (bmw_w / wallbox_w * 100) | round(1) }}
          {% else %}
            {{ 0 }}
          {% endif %}
        availability: >-
          {{ has_value('sensor.goe_${GOE_SERIAL}_nrg_11')
             and has_value('sensor.ix1_xdrive30_battery_ev_charging_power')
             and states('sensor.goe_${GOE_SERIAL}_nrg_11') | float(0) > 100 }}

      - name: "EV estimated full time"
        unique_id: ev_estimated_full_time
        icon: mdi:clock-end
        state: >-
          {% set hours = states('sensor.ev_hours_needed_to_target') | float(0) %}
          {% if hours > 0 %}
            {{ (now() + timedelta(hours=hours)).strftime('%H:%M') }}
          {% else %}
            —
          {% endif %}
        availability: >-
          {{ has_value('sensor.ev_hours_needed_to_target') }}

      - name: "EV house voltage L1"
        unique_id: ev_house_voltage_l1
        unit_of_measurement: "V"
        device_class: voltage
        state_class: measurement
        state: "{{ states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0) }}"
        availability: >-
          {{ has_value('sensor.voltage_phase1_${TIBBER_HOME}') }}

      - name: "EV voltage status"
        unique_id: ev_voltage_status
        icon: mdi:flash-triangle-outline
        state: >-
          {% set v = states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0) %}
          {% set warn = states('input_number.ev_voltage_warn') | float(215) %}
          {% set reduce = states('input_number.ev_voltage_reduce') | float(210) %}
          {% set stop = states('input_number.ev_voltage_stop') | float(208) %}
          {% if v <= 0 %}unknown
          {% elif v <= stop %}critical
          {% elif v <= reduce %}reduce
          {% elif v <= warn %}warning
          {% else %}ok{% endif %}
        availability: >-
          {{ has_value('sensor.voltage_phase1_${TIBBER_HOME}') }}

    binary_sensor:
      - name: "EV voltage warning zone"
        unique_id: ev_voltage_warning_zone
        device_class: problem
        state: >-
          {{ states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0)
             <= states('input_number.ev_voltage_warn') | float(215)
             and states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0) > 0 }}
        availability: >-
          {{ has_value('sensor.voltage_phase1_${TIBBER_HOME}') }}

      - name: "EV voltage reduce zone"
        unique_id: ev_voltage_reduce_zone
        device_class: problem
        state: >-
          {{ states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0)
             <= states('input_number.ev_voltage_reduce') | float(210)
             and states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0) > 0 }}
        availability: >-
          {{ has_value('sensor.voltage_phase1_${TIBBER_HOME}') }}

      - name: "EV voltage critical zone"
        unique_id: ev_voltage_critical_zone
        device_class: problem
        state: >-
          {{ states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0)
             <= states('input_number.ev_voltage_stop') | float(208)
             and states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0) > 0 }}
        availability: >-
          {{ has_value('sensor.voltage_phase1_${TIBBER_HOME}') }}

# =============================================================================
# INTEGRATION SENSOR — Riemann sum for accumulated EV cost
# =============================================================================
sensor:
  - platform: integration
    source: sensor.ev_charging_cost_rate
    name: "EV charging cost total"
    unique_id: ev_charging_cost_total
    unit_prefix: ~
    unit_time: h
    method: left
    round: 2

# =============================================================================
# UTILITY METERS — monthly / quarterly / yearly aggregation
# =============================================================================
utility_meter:
  # --- EV cost ---
  ev_cost_monthly:
    source: sensor.ev_charging_cost_total
    name: "EV charging cost monthly"
    unique_id: ev_cost_monthly
    cycle: monthly

  ev_cost_quarterly:
    source: sensor.ev_charging_cost_total
    name: "EV charging cost quarterly"
    unique_id: ev_cost_quarterly
    cycle: quarterly

  ev_cost_yearly:
    source: sensor.ev_charging_cost_total
    name: "EV charging cost yearly"
    unique_id: ev_cost_yearly
    cycle: yearly

  # --- EV energy ---
  ev_energy_monthly:
    source: sensor.goe_${GOE_SERIAL}_eto
    name: "EV energy monthly"
    unique_id: ev_energy_monthly
    cycle: monthly

  ev_energy_quarterly:
    source: sensor.goe_${GOE_SERIAL}_eto
    name: "EV energy quarterly"
    unique_id: ev_energy_quarterly
    cycle: quarterly

  ev_energy_yearly:
    source: sensor.goe_${GOE_SERIAL}_eto
    name: "EV energy yearly"
    unique_id: ev_energy_yearly
    cycle: yearly

# =============================================================================
# AUTOMATIONS
# =============================================================================
automation:
  # -------------------------------------------------------------------------
  # SMART CHARGING: cheapest hours + budget limit
  # -------------------------------------------------------------------------
  - id: ev_smart_charge_scheduler
    alias: "EV: Smart charge during cheapest hours"
    description: >-
      Charges the EV only during the X cheapest hours of the day
      and stops when the monthly EV budget is exceeded.
      Uses frc=2 to force-start and frc=1 to force-stop.
    mode: single
    triggers:
      - trigger: time_pattern
        minutes: "/1"
      # Also trigger when car gets plugged in
      - trigger: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        to: "on"
      # Also trigger when price changes (hourly)
      - trigger: state
        entity_id: sensor.electricity_price_${TIBBER_HOME}
    conditions:
      - condition: state
        entity_id: input_boolean.ev_smart_charging_enabled
        state: "on"
      - condition: state
        entity_id: input_boolean.ev_force_charge
        state: "off"
      # Only act if car is connected
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "on"
    actions:
      - variables:
          monthly_budget: >-
            {{ states('input_number.ev_monthly_budget') | float(50) }}
          monthly_ev_cost: >-
            {{ states('sensor.ev_charging_cost_monthly') | float(0) }}
          budget_exceeded: >-
            {{ monthly_ev_cost >= monthly_budget }}
          cheap_hours: >-
            {% set max_hours = states('input_number.ev_cheap_hours') | int(6) %}
            {% set soc = states('sensor.ix1_xdrive30_battery_hv_state_of_charge') | float(0) %}
            {% set target = states('input_number.ev_target_soc') | float(80) %}
            {% set capacity_kwh = 64.7 %}
            {% set power_kw = states('input_number.ev_current_normal') | float(10) * 230 / 1000 %}
            {% set kwh_needed = (target - soc) / 100 * capacity_kwh %}
            {% set hours_needed = (kwh_needed / power_kw) | round(0, 'ceil') | int if power_kw > 0 else max_hours %}
            {{ [hours_needed, max_hours] | min if hours_needed > 0 else max_hours }}
          current_hour: "{{ now().hour }}"
          prices_today: >-
            {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
            {{ raw | map(attribute='total') | list if raw is not none else [] }}
          prices_tomorrow: >-
            {% set raw = state_attr('sensor.ev_price_cache', 'tomorrow') %}
            {{ raw | map(attribute='total') | list if raw is not none else [] }}
          combined_prices: >-
            {{ prices_today + prices_tomorrow if prices_tomorrow | length >= 24 else prices_today }}
          sorted_prices: >-
            {{ combined_prices | sort if combined_prices | length > 0 else [] }}
          price_threshold: >-
            {{ sorted_prices[cheap_hours - 1]
               if sorted_prices | length >= cheap_hours
               else 999 }}
          current_price: >-
            {{ prices_today[current_hour | int]
               if prices_today | length > current_hour | int
               else states('sensor.electricity_price_${TIBBER_HOME}') | float(999) }}
          voltage_ok: >-
            {{ states('sensor.voltage_phase1_${TIBBER_HOME}') | float(0)
               > states('input_number.ev_voltage_reduce') | float(210) }}
          has_price_data: >-
            {{ prices_today | length >= 24 }}
          # Fallback: if no hourly array, use current price vs daily average
          fallback_should_charge: >-
            {% set current = states('sensor.electricity_price_${TIBBER_HOME}') | float(999) %}
            {% set avg = state_attr('sensor.electricity_price_${TIBBER_HOME}', 'avg_price') | float(0.30) %}
            {{ current <= avg and not budget_exceeded and voltage_ok }}
          soc_ok: >-
            {% set soc = states('sensor.ix1_xdrive30_battery_hv_state_of_charge') | float(0) %}
            {% set target = states('input_number.ev_target_soc') | float(80) %}
            {{ soc < target }}
          should_charge: >-
            {% if has_price_data %}
              {{ not budget_exceeded
                 and voltage_ok
                 and soc_ok
                 and current_price <= price_threshold }}
            {% else %}
              {{ fallback_should_charge and soc_ok }}
            {% endif %}
          current_frc: >-
            {{ states('select.goe_${GOE_SERIAL}_frc') }}
          budget_remaining: >-
            {{ (monthly_budget - monthly_ev_cost) | round(2) }}
      - choose:
          # --- START charging: set frc=2 ---
          - conditions:
              - condition: template
                value_template: "{{ should_charge and current_frc | int != 2 }}"
            sequence:
              - action: select.select_option
                target:
                  entity_id: select.goe_${GOE_SERIAL}_frc
                data:
                  option: "2"
              - action: number.set_value
                target:
                  entity_id: number.goe_${GOE_SERIAL}_amp
                data:
                  value: "{{ states('input_number.ev_current_normal') | int(10) }}"
              # Wait for charger to confirm frc=2 before notifying
              # (prevents duplicate notifications on next trigger cycle)
              - wait_template: "{{ states('select.goe_${GOE_SERIAL}_frc') == '2' }}"
                timeout: "00:00:30"
                continue_on_timeout: true
              - condition: template
                value_template: "{{ wait.completed }}"
              - action: notify.mobile_app_${IPHONE_DEVICE}
                data:
                  title: "🔌 EV charging started"
                  message: >-
                    Price: {{ current_price | round(3) }} EUR/kWh
                    (threshold: {{ price_threshold | round(3) }}).
                    Budget: {{ monthly_ev_cost | round(2) }}/{{ monthly_budget }} EUR
                    ({{ budget_remaining }} EUR left).
                  data:
                    push:
                      sound: "default"
                      interruption-level: "time-sensitive"

          # --- STOP charging: set frc=1 (force stop, not neutral!) ---
          - conditions:
              - condition: template
                value_template: "{{ not should_charge and current_frc | int != 1 }}"
            sequence:
              - action: select.select_option
                target:
                  entity_id: select.goe_${GOE_SERIAL}_frc
                data:
                  option: "1"
              # Wait for charger to confirm frc=1
              - wait_template: "{{ states('select.goe_${GOE_SERIAL}_frc') == '1' }}"
                timeout: "00:00:30"
                continue_on_timeout: true
              - condition: template
                value_template: "{{ wait.completed }}"
              # Only notify when transitioning FROM active charging
              - condition: template
                value_template: "{{ current_frc | int == 2 }}"
              - action: notify.mobile_app_${IPHONE_DEVICE}
                data:
                  title: >-
                    {% if budget_exceeded %}💰 EV stopped — budget reached
                    {% elif not voltage_ok %}⚠️ EV stopped — low voltage
                    {% elif not soc_ok %}🔋 EV stopped — target SoC reached
                    {% elif not has_price_data %}❓ EV stopped — no price data
                    {% else %}⏸️ EV paused — price too high{% endif %}
                  message: >-
                    Price: {{ current_price | round(3) }} EUR/kWh
                    (threshold: {{ price_threshold | round(3) }}).
                    Budget: {{ monthly_ev_cost | round(2) }}/{{ monthly_budget }} EUR.
                    Energy this month: {{ states('sensor.ev_energy_monthly') | float(0) | round(1) }} kWh.
                  data:
                    push:
                      sound: "default"

  # -------------------------------------------------------------------------
  # FORCE CHARGE: manual override from dashboard
  # -------------------------------------------------------------------------
  - id: ev_force_charge_on
    alias: "EV: Force charge ON"
    triggers:
      - trigger: state
        entity_id: input_boolean.ev_force_charge
        to: "on"
    conditions:
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "on"
    actions:
      - action: select.select_option
        target:
          entity_id: select.goe_${GOE_SERIAL}_frc
        data:
          option: "2"
      - action: number.set_value
        target:
          entity_id: number.goe_${GOE_SERIAL}_amp
        data:
          value: "{{ states('input_number.ev_current_normal') | int(13) }}"
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "⚡ EV force charge ON"
          message: >-
            Manual override active. Charging at
            {{ states('input_number.ev_current_normal') }} A.
            Price: {{ states('sensor.electricity_price_${TIBBER_HOME}') | float(0) | round(3) }} EUR/kWh.
    mode: single

  - id: ev_force_charge_off
    alias: "EV: Force charge OFF"
    triggers:
      - trigger: state
        entity_id: input_boolean.ev_force_charge
        to: "off"
    actions:
      - action: select.select_option
        target:
          entity_id: select.goe_${GOE_SERIAL}_frc
        data:
          option: "0"
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "ℹ️ EV force charge OFF"
          message: "Returning to smart scheduling."
    mode: single

  # -------------------------------------------------------------------------
  # VOLTAGE PROTECTION: warn → reduce → stop
  # -------------------------------------------------------------------------
  - id: ev_voltage_warning_notify
    alias: "EV: Voltage warning notification"
    triggers:
      - trigger: numeric_state
        entity_id: sensor.voltage_phase1_${TIBBER_HOME}
        below: input_number.ev_voltage_warn
        for:
          minutes: 2
    conditions:
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "on"
    actions:
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "⚠️ EV: Low grid voltage"
          message: >-
            Grid voltage L1: {{ states('sensor.voltage_phase1_${TIBBER_HOME}') }} V
            (warning threshold: {{ states('input_number.ev_voltage_warn') }} V).
            Charging power: {{ states('sensor.goe_${GOE_SERIAL}_nrg_11') }} W.
    mode: single

  - id: ev_voltage_reduce_current
    alias: "EV: Reduce current on low voltage"
    triggers:
      - trigger: numeric_state
        entity_id: sensor.voltage_phase1_${TIBBER_HOME}
        below: input_number.ev_voltage_reduce
        for:
          seconds: 30
    conditions:
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "on"
      - condition: template
        value_template: >-
          {{ states('number.goe_${GOE_SERIAL}_amp') | float(0)
             > states('input_number.ev_current_safe') | float(10) }}
    actions:
      - action: number.set_value
        target:
          entity_id: number.goe_${GOE_SERIAL}_amp
        data:
          value: "{{ states('input_number.ev_current_safe') | int(10) }}"
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "⚠️ EV: Current reduced"
          message: >-
            Voltage {{ states('sensor.voltage_phase1_${TIBBER_HOME}') }} V
            — reduced to {{ states('input_number.ev_current_safe') }} A.
    mode: single

  - id: ev_voltage_stop_charging
    alias: "EV: Stop charging on critical voltage"
    triggers:
      - trigger: numeric_state
        entity_id: sensor.voltage_phase1_${TIBBER_HOME}
        below: input_number.ev_voltage_stop
        for:
          seconds: 20
    conditions:
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "on"
    actions:
      - action: select.select_option
        target:
          entity_id: select.goe_${GOE_SERIAL}_frc
        data:
          option: "1"
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "🚨 EV: Charging STOPPED — critical voltage"
          message: >-
            Grid voltage {{ states('sensor.voltage_phase1_${TIBBER_HOME}') }} V
            is below {{ states('input_number.ev_voltage_stop') }} V.
            Charging has been force-stopped.
          data:
            push:
              sound: "default"
              interruption-level: "critical"
    mode: single

  - id: ev_voltage_restore_normal
    alias: "EV: Restore normal current when voltage recovers"
    triggers:
      - trigger: numeric_state
        entity_id: sensor.voltage_phase1_${TIBBER_HOME}
        above: input_number.ev_voltage_warn
        for:
          minutes: 3
    conditions:
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "on"
      - condition: state
        entity_id: input_boolean.ev_smart_charging_enabled
        state: "on"
    actions:
      - action: number.set_value
        target:
          entity_id: number.goe_${GOE_SERIAL}_amp
        data:
          value: "{{ states('input_number.ev_current_normal') | int(13) }}"
    mode: single

  # -------------------------------------------------------------------------
  # NOTIFICATIONS: car connected / disconnected
  # -------------------------------------------------------------------------
  - id: ev_car_connected
    alias: "EV: Car connected notification"
    triggers:
      - trigger: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        to: "on"
    actions:
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "🔌 EV connected"
          message: >-
            Car plugged in. Price: {{ states('sensor.electricity_price_${TIBBER_HOME}') | float(0) | round(3) }} EUR/kWh.
            Smart charging: {{ states('input_boolean.ev_smart_charging_enabled') }}.
            Monthly EV cost: {{ states('sensor.ev_charging_cost_monthly') | float(0) | round(2) }} EUR.
    mode: single

  - id: ev_car_disconnected
    alias: "EV: Car disconnected notification"
    triggers:
      - trigger: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        to: "off"
    actions:
      - variables:
          session_kwh: "{{ states('sensor.goe_${GOE_SERIAL}_wh') | float(0) | round(2) }}"
          session_cost: >-
            {% set kwh = states('sensor.goe_${GOE_SERIAL}_wh') | float(0) %}
            {% set avg = states('sensor.ev_average_price_per_kwh_monthly') | float(0.20) %}
            {{ (kwh * avg) | round(2) }}
          monthly_total_kwh: "{{ states('sensor.ev_energy_monthly') | float(0) | round(1) }}"
          monthly_total_cost: "{{ states('sensor.ev_charging_cost_monthly') | float(0) | round(2) }}"
      - action: select.select_option
        target:
          entity_id: select.goe_${GOE_SERIAL}_frc
        data:
          option: "0"
      - action: input_boolean.turn_off
        target:
          entity_id: input_boolean.ev_force_charge
      # Session log notification with full summary
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "🔌 EV disconnected — session complete"
          message: >-
            Session: {{ session_kwh }} kWh (~{{ session_cost }} EUR).
            Monthly: {{ monthly_total_kwh }} kWh / {{ monthly_total_cost }} EUR.
      # Log to HA logbook via event
      - event: ev_charging_session_complete
        event_data:
          energy_kwh: "{{ session_kwh }}"
          estimated_cost_eur: "{{ session_cost }}"
          monthly_energy_kwh: "{{ monthly_total_kwh }}"
          monthly_cost_eur: "{{ monthly_total_cost }}"
          timestamp: "{{ now().isoformat() }}"
    mode: single

  # -------------------------------------------------------------------------
  # SAFETY: reset frc to neutral on HA start
  # -------------------------------------------------------------------------
  - id: ev_ha_start_reset
    alias: "EV: Reset charge mode on HA start"
    triggers:
      - trigger: homeassistant
        event: start
    actions:
      - delay:
          seconds: 30
      - action: input_boolean.turn_off
        target:
          entity_id: input_boolean.ev_force_charge
      # Don't reset frc here — let the scheduler decide on next tick
    mode: single

  # -------------------------------------------------------------------------
  # REMINDER: forgot to plug in
  # -------------------------------------------------------------------------
  - id: ev_forgot_to_plug_in
    alias: "EV: Forgot to plug in reminder"
    description: >-
      Reminds you at 22:00 if the car is home, not plugged in, and SoC is low.
    triggers:
      - trigger: time
        at: "22:00:00"
    conditions:
      - condition: state
        entity_id: device_tracker.ix1_xdrive30_location
        state: "home"
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "off"
      - condition: numeric_state
        entity_id: sensor.ix1_xdrive30_battery_hv_state_of_charge
        below: input_number.ev_target_soc
    actions:
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "🔋 EV: Einstecken vergessen?"
          message: >-
            Auto ist zuhause aber nicht am Charger.
            SoC: {{ states('sensor.ix1_xdrive30_battery_hv_state_of_charge') }}%
            (Ziel: {{ states('input_number.ev_target_soc') | int }}%).
            Reichweite: {{ states('sensor.ix1_xdrive30_range_ev_remaining_range') }} km.
          data:
            push:
              sound: "default"
              interruption-level: "time-sensitive"
    mode: single

  # -------------------------------------------------------------------------
  # MONTHLY REPORT: summary on 1st of each month
  # -------------------------------------------------------------------------
  - id: ev_monthly_report
    alias: "EV: Monthly charging report"
    triggers:
      - trigger: time
        at: "08:00:00"
    conditions:
      - condition: template
        value_template: "{{ now().day == 1 }}"
    actions:
      - variables:
          cost: "{{ states('sensor.ev_charging_cost_monthly') | float(0) | round(2) }}"
          energy: "{{ states('sensor.ev_energy_monthly') | float(0) | round(1) }}"
          avg_price: "{{ states('sensor.ev_average_price_per_kwh_monthly') | float(0) | round(3) }}"
          consumption: "{{ states('input_number.ev_consumption_per_100km') | float(22) }}"
          range_km: "{{ (energy | float / consumption | float * 100) | round(0) if consumption | float > 0 else 0 }}"
          budget: "{{ states('input_number.ev_monthly_budget') | float(50) }}"
      - action: notify.mobile_app_${IPHONE_DEVICE}
        data:
          title: "📊 EV Monatsreport {{ (now() - timedelta(days=1)).strftime('%B %Y') }}"
          message: >-
            Energie: {{ energy }} kWh (~{{ range_km }} km)
            Kosten: {{ cost }} EUR (Budget: {{ budget }} EUR)
            Ø Preis: {{ avg_price }} EUR/kWh
            Effizienz: {{ ((cost | float / energy | float) * 100) | round(1) if energy | float > 0 else '—' }} ct/kWh
    mode: single
