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



  ev_target_soc:
    name: "EV target state of charge"
    min: 50
    max: 100
    step: 5
    unit_of_measurement: "%"
    icon: mdi:battery-charging-100
    mode: slider
    initial: 100

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

  ev_cheap_price_tolerance:
    name: "EV cheap price tolerance"
    # Extends the top-N cheapest threshold upward by this percentage to
    # catch clustered near-cheap hours. E.g. tolerance=20% means any hour
    # within 20% above the N-th cheapest price is considered cheap.
    # Counterbalanced by ev_max_price_vs_avg (hard ceiling).
    min: 0
    max: 100
    step: 1
    unit_of_measurement: "%"
    icon: mdi:plus-minus-variant
    mode: box
    initial: 20

  ev_max_price_vs_avg:
    name: "EV max price vs daily avg"
    # Hard upper cap for the charging threshold, expressed as a fraction of
    # the day's average price. 0.9 means: never charge above 90% of daily
    # average, even if tolerance or hours_needed would suggest otherwise.
    # This is the "natural cheap window" safety limit — ensures we never
    # pay above-average prices while hamstering cheap energy.
    # 1.0 disables the cap (classic behaviour).
    min: 0.5
    max: 1.2
    step: 0.05
    icon: mdi:chart-bell-curve
    mode: slider
    initial: 0.9

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
      - name: "EV average consumption"
        unique_id: ev_average_consumption
        unit_of_measurement: "kWh/100km"
        icon: mdi:car-electric
        state: >-
          {% set soc = states('sensor.ix1_xdrive30_battery_hv_state_of_charge') | float(0) %}
          {% set range_km = states('sensor.ix1_xdrive30_range_ev_remaining_range') | float(0) %}
          {% set capacity_kwh = 64.7 %}
          {% if soc > 0 and range_km > 0 %}
            {% set energy_current = capacity_kwh * (soc / 100) %}
            {{ (energy_current / range_km * 100) | round(1) }}
          {% else %}
            22.0
          {% endif %}
        availability: >-
          {{ has_value('sensor.ix1_xdrive30_battery_hv_state_of_charge')
             and has_value('sensor.ix1_xdrive30_range_ev_remaining_range') }}

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
             and has_value('sensor.electricity_price_${TIBBER_HOME}')
             and states('sensor.goe_${GOE_SERIAL}_nrg_11') not in ['unknown', 'unavailable'] }}

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

      - name: "EV hours needed"
        unique_id: ev_hours_needed
        unit_of_measurement: "h"
        icon: mdi:clock-check-outline
        state: >-
          {% set live_soc = states('sensor.ix1_xdrive30_battery_hv_state_of_charge') %}
          {% set last_soc = states('sensor.ev_last_known_soc') %}
          {% if live_soc not in ['unknown', 'unavailable', 'none', ''] %}
            {% set soc = live_soc | float(50) %}
          {% elif last_soc not in ['unknown', 'unavailable', 'none', ''] %}
            {% set soc = last_soc | float(50) %}
          {% else %}
            {% set soc = 50 %}
          {% endif %}
          {% set target = states('input_number.ev_target_soc') | float(100) %}
          {% set power_kw = states('input_number.ev_current_normal') | float(10) * 230 / 1000 %}
          {% set kwh_needed = (target - soc) / 100 * 64.7 %}
          {% if kwh_needed > 0 and power_kw > 0 %}
            {{ (kwh_needed / power_kw) | round(0, 'ceil') | int }}
          {% else %}
            0
          {% endif %}

      # --- Widget support sensors: expose scheduler's threshold + daily avg ---
      # Used by the "Smart Charging Decision" widget to visualise the same
      # price threshold the scheduler applies, without duplicating the
      # 3-layer calculation inline in the dashboard YAML.
      - name: "EV charge daily avg"
        unique_id: ev_charge_daily_avg
        unit_of_measurement: "EUR/kWh"
        icon: mdi:chart-line-variant
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% if raw is not none and raw | length > 0 %}
            {% set prices = raw | map(attribute='total') | list %}
            {{ (prices | sum / prices | length) | round(4) }}
          {% else %}
            {{ 0 }}
          {% endif %}
        availability: >-
          {{ state_attr('sensor.ev_price_cache', 'today') is not none }}

      - name: "EV charge price threshold"
        unique_id: ev_charge_price_threshold
        unit_of_measurement: "EUR/kWh"
        icon: mdi:ruler
        state: >-
          {% set raw_today = state_attr('sensor.ev_price_cache', 'today') %}
          {% if raw_today is none or raw_today | length == 0 %}
            {{ 0 }}
          {% else %}
            {% set prices_today = raw_today | map(attribute='total') | list %}
            {% set raw_tomorrow = state_attr('sensor.ev_price_cache', 'tomorrow') %}
            {% set prices_tomorrow = raw_tomorrow | map(attribute='total') | list if raw_tomorrow is not none and raw_tomorrow | length >= 24 else [] %}
            {% set combined = prices_today + prices_tomorrow %}
            {% set future = combined[now().hour:] if combined | length > now().hour else combined %}
            {% set hours = states('sensor.ev_hours_needed') | int(6) %}
            {% set hours = [hours, 1] | max %}
            {% set sorted = future | sort %}
            {% set base = sorted[[hours - 1, sorted | length - 1] | min] %}
            {% set spread = (sorted | last - sorted | first) if sorted | length > 1 else 0.01 %}
            {% set tol = states('input_number.ev_cheap_price_tolerance') | float(20) / 100 %}
            {% set extended = base + spread * tol %}
            {% set avg = future | sum / future | length if future | length > 0 else 0 %}
            {% set cap_factor = states('input_number.ev_max_price_vs_avg') | float(0.9) %}
            {% set ceiling = avg * cap_factor if avg > 0 else 999 %}
            {{ [extended, ceiling] | min | round(4) }}
          {% endif %}
        attributes:
          hours_needed: >-
            {{ states('sensor.ev_hours_needed') | int(0) }}
          base: >-
            {% set raw_today = state_attr('sensor.ev_price_cache', 'today') %}
            {% if raw_today is none or raw_today | length == 0 %}
              0
            {% else %}
              {% set prices_today = raw_today | map(attribute='total') | list %}
              {% set raw_tomorrow = state_attr('sensor.ev_price_cache', 'tomorrow') %}
              {% set prices_tomorrow = raw_tomorrow | map(attribute='total') | list if raw_tomorrow is not none and raw_tomorrow | length >= 24 else [] %}
              {% set combined = prices_today + prices_tomorrow %}
              {% set future = combined[now().hour:] if combined | length > now().hour else combined %}
              {% set hours = [states('sensor.ev_hours_needed') | int(6), 1] | max %}
              {% set sorted = future | sort %}
              {{ sorted[[hours - 1, sorted | length - 1] | min] | round(4) }}
            {% endif %}
          extended: >-
            {% set raw_today = state_attr('sensor.ev_price_cache', 'today') %}
            {% if raw_today is none or raw_today | length == 0 %}
              0
            {% else %}
              {% set prices_today = raw_today | map(attribute='total') | list %}
              {% set raw_tomorrow = state_attr('sensor.ev_price_cache', 'tomorrow') %}
              {% set prices_tomorrow = raw_tomorrow | map(attribute='total') | list if raw_tomorrow is not none and raw_tomorrow | length >= 24 else [] %}
              {% set combined = prices_today + prices_tomorrow %}
              {% set future = combined[now().hour:] if combined | length > now().hour else combined %}
              {% set hours = [states('sensor.ev_hours_needed') | int(6), 1] | max %}
              {% set sorted = future | sort %}
              {% set base = sorted[[hours - 1, sorted | length - 1] | min] %}
              {% set spread = (sorted | last - sorted | first) if sorted | length > 1 else 0.01 %}
              {% set tol = states('input_number.ev_cheap_price_tolerance') | float(20) / 100 %}
              {{ (base + spread * tol) | round(4) }}
            {% endif %}
          ceiling: >-
            {% set raw_today = state_attr('sensor.ev_price_cache', 'today') %}
            {% if raw_today is none or raw_today | length == 0 %}
              0
            {% else %}
              {% set prices_today = raw_today | map(attribute='total') | list %}
              {% set raw_tomorrow = state_attr('sensor.ev_price_cache', 'tomorrow') %}
              {% set prices_tomorrow = raw_tomorrow | map(attribute='total') | list if raw_tomorrow is not none and raw_tomorrow | length >= 24 else [] %}
              {% set combined = prices_today + prices_tomorrow %}
              {% set future = combined[now().hour:] if combined | length > now().hour else combined %}
              {% set avg = future | sum / future | length if future | length > 0 else 0 %}
              {% set cap_factor = states('input_number.ev_max_price_vs_avg') | float(0.9) %}
              {{ (avg * cap_factor) | round(4) }}
            {% endif %}
          winner: >-
            {% set raw_today = state_attr('sensor.ev_price_cache', 'today') %}
            {% if raw_today is none or raw_today | length == 0 %}
              none
            {% else %}
              {% set prices_today = raw_today | map(attribute='total') | list %}
              {% set raw_tomorrow = state_attr('sensor.ev_price_cache', 'tomorrow') %}
              {% set prices_tomorrow = raw_tomorrow | map(attribute='total') | list if raw_tomorrow is not none and raw_tomorrow | length >= 24 else [] %}
              {% set combined = prices_today + prices_tomorrow %}
              {% set future = combined[now().hour:] if combined | length > now().hour else combined %}
              {% set hours = [states('sensor.ev_hours_needed') | int(6), 1] | max %}
              {% set sorted = future | sort %}
              {% set base = sorted[[hours - 1, sorted | length - 1] | min] %}
              {% set spread = (sorted | last - sorted | first) if sorted | length > 1 else 0.01 %}
              {% set tol = states('input_number.ev_cheap_price_tolerance') | float(20) / 100 %}
              {% set extended = base + spread * tol %}
              {% set avg = future | sum / future | length if future | length > 0 else 0 %}
              {% set cap_factor = states('input_number.ev_max_price_vs_avg') | float(0.9) %}
              {% set ceiling = avg * cap_factor if avg > 0 else 999 %}
              {{ 'tolerance' if extended <= ceiling else 'ceiling' }}
            {% endif %}
        availability: >-
          {{ state_attr('sensor.ev_price_cache', 'today') is not none }}

      - name: "EV expected price today"
        unique_id: ev_expected_price_today
        unit_of_measurement: "EUR/kWh"
        icon: mdi:crystal-ball
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% if raw is not none and raw | length > 0 %}
            {% set prices = raw | map(attribute='total') | list %}
            {% set threshold = states('sensor.ev_charge_price_threshold') | float(0) %}
            {% set cheap = prices | select('le', threshold) | list %}
            {{ (cheap | sum / cheap | length) | round(3) if cheap | length > 0 else 0 }}
          {% else %}
            {{ 0 }}
          {% endif %}
        availability: >-
          {{ state_attr('sensor.ev_price_cache', 'today') is not none
             and has_value('sensor.ev_charge_price_threshold') }}

      - name: "EV potential energy today"
        unique_id: ev_potential_energy_today
        unit_of_measurement: "kWh"
        icon: mdi:battery-charging
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set threshold = states('sensor.ev_charge_price_threshold') | float(0) %}
          {% set remaining_prices = prices[now().hour:] %}
          {% set cheap_remaining = remaining_prices | select('le', threshold) | list %}
          {% set amps = states('input_number.ev_current_normal') | float(10) %}
          {{ (cheap_remaining | length * amps * 230 / 1000) | round(1) }}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {{ raw is not none and raw | length >= 24
             and has_value('sensor.ev_charge_price_threshold') }}

      - name: "EV potential range today"
        unique_id: ev_potential_range_today
        unit_of_measurement: "km"
        icon: mdi:map-marker-distance
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set threshold = states('sensor.ev_charge_price_threshold') | float(0) %}
          {% set remaining_prices = prices[now().hour:] %}
          {% set cheap_remaining = remaining_prices | select('le', threshold) | list %}
          {% set amps = states('input_number.ev_current_normal') | float(10) %}
          {% set kwh = cheap_remaining | length * amps * 230 / 1000 %}
          {% set consumption = states('sensor.ev_average_consumption') | float(22) %}
          {{ (kwh / consumption * 100) | round(0) }}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {{ raw is not none and raw | length >= 24
             and has_value('sensor.ev_charge_price_threshold') }}

      - name: "EV cheap hours remaining"
        unique_id: ev_cheap_hours_remaining
        unit_of_measurement: "h"
        icon: mdi:clock-fast
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set threshold = states('sensor.ev_charge_price_threshold') | float(0) %}
          {% set remaining_prices = prices[now().hour:] %}
          {{ remaining_prices | select('le', threshold) | list | length }}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {{ raw is not none and raw | length >= 24
             and has_value('sensor.ev_charge_price_threshold') }}

      - name: "EV tomorrow cheapest hours"
        unique_id: ev_tomorrow_cheapest_hours
        icon: mdi:calendar-arrow-right
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'tomorrow') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set hours = [states('sensor.ev_hours_needed') | int(6), 1] | max %}
          {% set sorted = prices | sort %}
          {% set base = sorted[[hours - 1, sorted | length - 1] | min] %}
          {% set spread = (sorted | last - sorted | first) if sorted | length > 1 else 0.01 %}
          {% set tol = states('input_number.ev_cheap_price_tolerance') | float(20) / 100 %}
          {% set extended = base + spread * tol %}
          {% set avg = prices | sum / prices | length %}
          {% set cap_factor = states('input_number.ev_max_price_vs_avg') | float(0.9) %}
          {% set ceiling = avg * cap_factor if avg > 0 else 999 %}
          {% set threshold = [extended, ceiling] | min %}
          {% set ns = namespace(indices=[]) %}
          {% for p in prices %}
            {% if p <= threshold %}
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
          {% set hours = [states('sensor.ev_hours_needed') | int(6), 1] | max %}
          {% set sorted = prices | sort %}
          {% set base = sorted[[hours - 1, sorted | length - 1] | min] %}
          {% set spread = (sorted | last - sorted | first) if sorted | length > 1 else 0.01 %}
          {% set tol = states('input_number.ev_cheap_price_tolerance') | float(20) / 100 %}
          {% set extended = base + spread * tol %}
          {% set avg = prices | sum / prices | length %}
          {% set cap_factor = states('input_number.ev_max_price_vs_avg') | float(0.9) %}
          {% set ceiling = avg * cap_factor if avg > 0 else 999 %}
          {% set threshold = [extended, ceiling] | min %}
          {% set cheap = prices | select('le', threshold) | list %}
          {{ (cheap | sum / cheap | length) | round(3) if cheap | length > 0 else 0 }}
        availability: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'tomorrow') %}
          {{ raw is not none and raw | length >= 24 }}

      - name: "EV next cheap hour"
        unique_id: ev_next_cheap_hour
        icon: mdi:clock-start
        state: >-
          {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
          {% set prices = raw | map(attribute='total') | list %}
          {% set threshold = states('sensor.ev_charge_price_threshold') | float(0) %}
          {% set current_hour = now().hour %}
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
          {{ raw is not none and raw | length >= 24
             and has_value('sensor.ev_charge_price_threshold') }}

      - name: "EV monthly cost forecast"
        unique_id: ev_monthly_cost_forecast
        unit_of_measurement: "EUR"
        icon: mdi:chart-timeline-variant
        state: >-
          {% set cost_so_far = states('sensor.ev_charging_cost_monthly') | float(0) %}
          {% set day_of_month = now().day %}
          {% if day_of_month > 1 and cost_so_far != 0 %}
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
          {% set hours = states('sensor.ev_hours_needed') | float(6) %}
          {% set amps = states('input_number.ev_current_normal') | float(10) %}
          {% set voltage = 230 %}
          {% set consumption = states('sensor.ev_average_consumption') | float(22) %}
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
             and has_value('sensor.ev_hours_needed')
             and has_value('input_number.ev_current_normal') }}

      - name: "EV charging efficiency"
        unique_id: ev_charging_efficiency
        unit_of_measurement: "%"
        icon: mdi:transmission-tower-import
        state_class: measurement
        state: >-
          {% set wallbox_w = states('sensor.goe_${GOE_SERIAL}_nrg_11') | float(0) %}
          {% set bmw_w = states('sensor.ix1_xdrive30_battery_ev_charging_power') | float(0) %}
          {% if wallbox_w > 1000 and bmw_w > 0 %}
            {% set eff = (bmw_w / wallbox_w * 100) | round(1) %}
            {{ [eff, 100.0] | min }}
          {% else %}
            {{ 0 }}
          {% endif %}
        availability: >-
          {{ has_value('sensor.goe_${GOE_SERIAL}_nrg_11')
             and has_value('sensor.ix1_xdrive30_battery_ev_charging_power') }}

      - name: "EV estimated full time"
        unique_id: ev_estimated_full_time
        icon: mdi:clock-end
        state: >-
          {% set hours_needed = states('sensor.ev_hours_needed') | int(0) %}
          {% if hours_needed <= 0 %}
            ✓ Ziel erreicht
          {% else %}
            {% set raw_today = state_attr('sensor.ev_price_cache', 'today') %}
            {% set raw_tomorrow = state_attr('sensor.ev_price_cache', 'tomorrow') %}
            {% if raw_today is none %}
              —
            {% else %}
              {% set prices_today = raw_today | map(attribute='total') | list %}
              {% set prices_tomorrow = raw_tomorrow | map(attribute='total') | list if raw_tomorrow is not none else [] %}
              {% set tomorrow_available = prices_tomorrow | length >= 24 %}
              {% set combined = prices_today + prices_tomorrow %}
              {% set current_hour = now().hour %}
              {% set threshold = states('sensor.ev_charge_price_threshold') | float(0) %}
              {% if combined | length > current_hour %}
                {% set ns = namespace(count=0, wall_hour=-1) %}
                {% for i in range(current_hour, combined | length) %}
                  {% if ns.wall_hour == -1 and combined[i] <= threshold %}
                    {% set ns.count = ns.count + 1 %}
                    {% if ns.count >= hours_needed %}
                      {% set ns.wall_hour = i + 1 %}
                    {% endif %}
                  {% endif %}
                {% endfor %}
                {% if ns.wall_hour > 0 %}
                  {% if ns.wall_hour < 24 %}
                    heute {{ '%02d:00' | format(ns.wall_hour) }}
                  {% elif ns.wall_hour == 24 %}
                    morgen 00:00
                  {% elif ns.wall_hour < 48 %}
                    morgen {{ '%02d:00' | format(ns.wall_hour - 24) }}
                  {% else %}
                    > 48h
                  {% endif %}
                {% elif not tomorrow_available %}
                  morgen (Preise folgen ~13:00)
                {% else %}
                  — nicht genug billige Stunden
                {% endif %}
              {% else %}
                —
              {% endif %}
            {% endif %}
          {% endif %}
        availability: >-
          {{ has_value('sensor.ev_hours_needed')
             and has_value('sensor.ev_charge_price_threshold') }}

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

  # --- Debounced car-connected state: filters out WiFi flaps via Powerline ---
  # The go-eCharger is reached via a FritzPowerline link which occasionally
  # drops for a few seconds. Triggering notifications directly on
  # binary_sensor.goe_..._car_0 causes ghost "connected/disconnected" pairs
  # every time the link flaps.
  #
  # This is a state-based (not trigger-based) template binary sensor so it
  # evaluates continuously. delay_on / delay_off provide the debouncing —
  # a transient transition that reverts within 60 seconds never propagates.
  # availability gates the sensor on a definite source state, so that
  # unknown/unavailable moments during a reconnect surface as "unavailable"
  # on the stable sensor (instead of flipping to "off"). Automations that
  # trigger on explicit from: "on" / from: "off" thus ignore reconnect
  # transitions entirely.
  - binary_sensor:
      - name: "EV car connected (stable)"
        unique_id: ev_car_connected_stable
        device_class: plug
        state: "{{ is_state('binary_sensor.goe_${GOE_SERIAL}_car_0', 'on') }}"
        availability: >-
          {{ has_value('binary_sensor.goe_${GOE_SERIAL}_car_0') }}
        delay_on: "00:01:00"
        delay_off: "00:01:00"

  # --- Last-known session energy: holds the most recent valid wh reading ---
  # When the Powerline link drops, sensor.goe_..._wh goes to 'unknown', which
  # made the disconnect notification render "Session: 0.0 kWh". This
  # trigger-based sensor only updates on transitions to real numeric values,
  # so it keeps the last good kWh reading available for the disconnect
  # summary even if the charger is briefly unreachable at notification time.
  #
  # Additional guard: only update while a car is actually plugged in. This
  # protects against wh being reported as 0 between sessions (go-e behaviour
  # may differ across firmwares) — without the guard, the disconnect
  # notification could race against a wh→0 reset and still show 0.0 kWh
  # despite real session energy.
  - triggers:
      - trigger: state
        entity_id: sensor.goe_${GOE_SERIAL}_wh
        not_to:
          - unknown
          - unavailable
          - none
    conditions:
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "on"
    sensor:
      - name: "EV session energy (last known)"
        unique_id: ev_session_energy_last_known
        unit_of_measurement: "kWh"
        device_class: energy
        state_class: total_increasing
        icon: mdi:ev-plug-type2
        state: "{{ states('sensor.goe_${GOE_SERIAL}_wh') | float(0) | round(3) }}"

  # --- Last-known SoC: holds the most recent valid battery reading ---
  # When the BMW API goes offline, the SoC sensor becomes unavailable.
  # This trigger-based sensor preserves the last good reading so the
  # scheduler and display sensors can still compute hours_needed.
  - triggers:
      - trigger: state
        entity_id: sensor.ix1_xdrive30_battery_hv_state_of_charge
        not_to:
          - unknown
          - unavailable
          - none
    sensor:
      - name: "EV last known SoC"
        unique_id: ev_last_known_soc
        unit_of_measurement: "%"
        device_class: battery
        state_class: measurement
        icon: mdi:battery-sync
        state: "{{ states('sensor.ix1_xdrive30_battery_hv_state_of_charge') | float(0) }}"

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
    net_consumption: true

  ev_cost_quarterly:
    source: sensor.ev_charging_cost_total
    name: "EV charging cost quarterly"
    unique_id: ev_cost_quarterly
    cycle: quarterly
    net_consumption: true

  ev_cost_yearly:
    source: sensor.ev_charging_cost_total
    name: "EV charging cost yearly"
    unique_id: ev_cost_yearly
    cycle: yearly
    net_consumption: true

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
      Charges the EV only during the cheapest hours based on SoC-driven
      demand and a three-layer price threshold (base + spread × tolerance,
      capped by ceiling). Stops when budget is exceeded or target SoC reached.
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
            {% set hours = states('sensor.ev_hours_needed') | int(6) %}
            {{ [hours, 1] | max }}
          current_hour: "{{ now().hour }}"
          prices_today: >-
            {% set raw = state_attr('sensor.ev_price_cache', 'today') %}
            {{ raw | map(attribute='total') | list if raw is not none else [] }}
          prices_tomorrow: >-
            {% set raw = state_attr('sensor.ev_price_cache', 'tomorrow') %}
            {{ raw | map(attribute='total') | list if raw is not none else [] }}
          combined_prices: >-
            {% set today = prices_today[now().hour:] if prices_today | length > now().hour else [] %}
            {% set tomorrow = prices_tomorrow if prices_tomorrow | length >= 24 else [] %}
            {{ today + tomorrow }}
          sorted_prices: >-
            {{ combined_prices | sort if combined_prices | length > 0 else [] }}
          # "Natural cheap window" threshold
          # ------------------------------------------------------------------
          # Three-layer computation:
          #   1. base:     N-th cheapest future price (N = hours_needed
          #                from SoC, via sensor.ev_hours_needed).
          #   2. extended: base + spread × tolerance — spread is the
          #                day's price range (max−min), safe for negative
          #                prices unlike the old |base| × tol formula.
          #   3. ceiling:  daily_avg × max_price_vs_avg — hard safety cap
          #                so we never charge above a fraction of the
          #                day's average, even if need/tolerance suggest it.
          # final = min(extended, ceiling). When ev_max_price_vs_avg is
          # set to ≥1.0, the ceiling is effectively disabled.
          daily_avg: >-
            {{ (combined_prices | sum) / (combined_prices | length)
               if combined_prices | length > 0 else 0 }}
          price_threshold: >-
            {% set base = sorted_prices[cheap_hours - 1]
               if sorted_prices | length >= cheap_hours
               else 999 %}
            {% set spread = (sorted_prices | last - sorted_prices | first) if sorted_prices | length > 1 else 0.01 %}
            {% set tol = states('input_number.ev_cheap_price_tolerance') | float(20) / 100 %}
            {% set extended = base + spread * tol %}
            {% set cap_factor = states('input_number.ev_max_price_vs_avg') | float(0.9) %}
            {% set ceiling = daily_avg * cap_factor if daily_avg > 0 else 999 %}
            {{ [extended, ceiling] | min }}
          current_price: >-
            {# Always use the live Tibber sensor — it reflects the active
               15-minute slot, while prices_today is only a 1-per-hour
               sample and can be wildly off inside an hour. The hourly
               cache stays authoritative for threshold computation (we
               need a per-hour estimate there), but the "is now cheap?"
               decision must use the actual current price. #}
            {% set live = states('sensor.electricity_price_${TIBBER_HOME}') | float(-1) %}
            {% if live >= 0 %}
              {{ live }}
            {% elif prices_today | length > current_hour | int %}
              {{ prices_today[current_hour | int] }}
            {% else %}
              999
            {% endif %}
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
            {% set live_soc = states('sensor.ix1_xdrive30_battery_hv_state_of_charge') %}
            {% set last_soc = states('sensor.ev_last_known_soc') %}
            {% if live_soc not in ['unknown', 'unavailable', 'none', ''] %}
              {% set soc = live_soc | float(0) %}
            {% elif last_soc not in ['unknown', 'unavailable', 'none', ''] %}
              {% set soc = last_soc | float(0) %}
            {% else %}
              {% set soc = 0 %}
            {% endif %}
            {% set target = states('input_number.ev_target_soc') | float(100) %}
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
        entity_id: binary_sensor.ev_car_connected_stable
        from: "off"
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
        entity_id: binary_sensor.ev_car_connected_stable
        from: "on"
        to: "off"
    actions:
      - variables:
          session_kwh: "{{ states('sensor.ev_session_energy_last_known') | float(0) | round(2) }}"
          session_cost: >-
            {% set kwh = states('sensor.ev_session_energy_last_known') | float(0) %}
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
  # FRC WATCHDOG: re-apply desired state after charger-side safety reset
  # -------------------------------------------------------------------------
  # Root cause: the go-eCharger has a safety timeout. When it loses API contact
  # with HA (Powerline WiFi flap), it resets frc (force state) from 1 (OFF)
  # back to 0 (Neutral) after ~60-90s — a deliberate feature to prevent a
  # crashed controller from permanently blocking the charger.
  #
  # Consequence: on reconnect we see frc=0 and, in Neutral mode with a car
  # plugged in, the charger starts drawing ~2 kW until the scheduler's next
  # tick re-applies frc=1. Each flap leaked ~0.03 kWh.
  #
  # Fix: trigger instantly on frc → 0 (including unknown → 0 reconnect events),
  # but only when a car is actually plugged in AND we did not deliberately set
  # frc=0 ourselves (disconnect notification does that, but then the car is
  # already unplugged so the condition filters it out). Re-run the scheduler
  # to restore the correct state. Race window shrinks from ~3s to ~1s.
  - id: ev_frc_watchdog
    alias: "EV: FRC watchdog (re-apply state after charger reset)"
    description: >-
      Protects against the go-eCharger's safety-timeout behaviour that resets
      frc to 0 (Neutral) when WiFi to HA drops out. Triggers on frc→0 while
      the car is plugged in and re-runs the smart-charge scheduler.
    triggers:
      - trigger: state
        entity_id: select.goe_${GOE_SERIAL}_frc
        to: "0"
    conditions:
      # Only care about resets while a car is actually plugged in.
      # When the car is unplugged, ev_car_disconnected legitimately sets frc=0.
      - condition: state
        entity_id: binary_sensor.goe_${GOE_SERIAL}_car_0
        state: "on"
    actions:
      - action: automation.trigger
        target:
          # Entity ID is slugified from the alias, NOT from the `id:` field.
          # alias "EV: Smart charge during cheapest hours" → this entity_id.
          entity_id: automation.ev_smart_charge_during_cheapest_hours
        data:
          skip_condition: true
    mode: restart

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
          consumption: "{{ states('sensor.ev_average_consumption') | float(22) }}"
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
