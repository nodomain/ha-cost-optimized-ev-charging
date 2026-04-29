###############################################################################
# Dashboard: EV Smart Charging
#
# Two views:
#   1. Charging — daily overview, designed for readability
#   2. Settings — voltage config, detailed entities, statistics
#
# Uses panel: false (masonry) with cards sized to avoid label truncation.
###############################################################################
views:
  # =========================================================================
  # VIEW 1: CHARGING
  # =========================================================================
  - title: Charging
    path: charging
    icon: mdi:ev-station
    badges: []
    cards:
      # --- Tibber price graph (full width, most important visual) ---
      - type: picture-entity
        entity: ${TIBBER_GRAPH_CAMERA}
        show_state: false
        show_name: false

      # --- Charger status ---
      - type: entities
        title: "🔌 Charger"
        show_header_toggle: false
        entities:
          - entity: binary_sensor.goe_${GOE_SERIAL}_car_0
            name: Car connected
          - entity: sensor.goe_${GOE_SERIAL}_car_value
            name: Vehicle status
          - entity: select.goe_${GOE_SERIAL}_frc
            name: Charge mode
          - entity: sensor.goe_${GOE_SERIAL}_nrg_4
            name: Charging current (actual)
          - entity: sensor.goe_${GOE_SERIAL}_nrg_11
            name: Charging power
          - entity: sensor.goe_${GOE_SERIAL}_wh
            name: Session energy

      # --- Vehicle (BMW iX1) ---
      - type: entities
        title: "🚗 iX1 xDrive30"
        show_header_toggle: false
        entities:
          - entity: sensor.ix1_xdrive30_battery_hv_state_of_charge
            name: Battery SoC
          - entity: input_number.ev_target_soc
            name: Target SoC
          - entity: sensor.ix1_xdrive30_range_ev_remaining_range
            name: Remaining range
          - entity: sensor.ix1_xdrive30_battery_ev_charging_power
            name: Charging power (BMW)
          - entity: sensor.ix1_xdrive30_charging_ev_charging_state
            name: Charging state
          - entity: sensor.ix1_xdrive30_charging_ev_remaining_time_estimate
            name: Time to full
          - entity: sensor.ix1_xdrive30_vehicle_mileage
            name: Mileage

      # --- SoC gauge ---
      - type: gauge
        entity: sensor.ix1_xdrive30_battery_hv_state_of_charge
        name: Battery
        unit: "%"
        min: 0
        max: 100
        needle: true
        severity:
          green: 60
          yellow: 30
          red: 0

      # --- Smart charging info ---
      - type: entities
        title: "🧠 Smart Charging"
        show_header_toggle: false
        entities:
          - entity: sensor.ev_hours_needed_to_target
            name: Hours needed to target
          - entity: sensor.ev_estimated_full_time
            name: Estimated full at
          - entity: sensor.ev_charging_efficiency
            name: Charging efficiency
          - entity: sensor.ev_charging_cost_rate
            name: Current cost rate

      # --- Budget & cost ---
      - type: entities
        title: "💰 Budget"
        show_header_toggle: false
        entities:
          - entity: input_number.ev_monthly_budget
            name: Monthly budget limit
          - entity: sensor.ev_charging_cost_monthly
            name: Cost this month
          - entity: sensor.ev_energy_monthly
            name: Energy this month
          - entity: sensor.ev_average_price_per_kwh_monthly
            name: Average price per kWh

      # --- Budget gauge ---
      - type: gauge
        entity: sensor.ev_charging_cost_monthly
        name: Monthly EV Budget
        unit: "EUR"
        min: 0
        max: 50
        needle: true
        severity:
          green: 0
          yellow: 35
          red: 45

      # --- Scheduling ---
      - type: entities
        title: "⏰ Scheduling"
        show_header_toggle: false
        entities:
          - entity: input_number.ev_cheap_hours
            name: Cheap hours per day
          - entity: input_number.ev_target_soc
            name: Charge target SoC
          - entity: sensor.ev_next_cheap_hour
            name: Next cheap hour
          - entity: sensor.ev_cheap_hours_remaining
            name: Cheap hours remaining today
          - entity: sensor.ev_expected_price_today
            name: Expected avg. price today
          - entity: sensor.ev_potential_energy_today
            name: Potential energy remaining
          - entity: sensor.ev_potential_range_today
            name: Potential range remaining
          - entity: input_number.ev_consumption_per_100km
            name: Vehicle consumption
          - type: divider
          - entity: sensor.electricity_price_${TIBBER_HOME}
            name: Current electricity price
          - entity: sensor.ev_voltage_status
            name: Voltage status

      # --- Tomorrow preview ---
      - type: entities
        title: "📅 Tomorrow"
        show_header_toggle: false
        entities:
          - entity: sensor.ev_tomorrow_cheapest_hours
            name: Cheapest hours
          - entity: sensor.ev_tomorrow_expected_price
            name: Expected avg. price

      # --- Cost forecast ---
      - type: entities
        title: "📈 Forecast"
        show_header_toggle: false
        entities:
          - entity: sensor.ev_monthly_cost_forecast
            name: Projected monthly cost
          - entity: sensor.ev_monthly_range_forecast
            name: Projected monthly range
          - entity: input_number.ev_monthly_budget
            name: Monthly budget limit

      # --- Quick action buttons ---
      - type: horizontal-stack
        cards:
          - type: button
            entity: input_boolean.ev_smart_charging_enabled
            name: Smart Charging
            icon: mdi:robot
            show_state: true
            tap_action:
              action: toggle
          - type: button
            entity: input_boolean.ev_force_charge
            name: Force Charge
            icon: mdi:flash
            show_state: true
            tap_action:
              action: toggle

  # =========================================================================
  # VIEW 2: SETTINGS & DETAILS
  # =========================================================================
  - title: Settings
    path: settings
    icon: mdi:cog
    badges: []
    cards:
      # --- Voltage protection ---
      - type: entities
        title: "🛡️ Voltage Protection"
        show_header_toggle: false
        entities:
          - entity: input_number.ev_voltage_warn
            name: Warning threshold
          - entity: input_number.ev_voltage_reduce
            name: Reduce threshold
          - entity: input_number.ev_voltage_stop
            name: Stop threshold
          - type: divider
          - entity: sensor.ev_voltage_status
            name: Current status
          - entity: binary_sensor.ev_voltage_warning_zone
            name: Warning zone
          - entity: binary_sensor.ev_voltage_reduce_zone
            name: Reduce zone
          - entity: binary_sensor.ev_voltage_critical_zone
            name: Critical zone

      # --- Charging parameters ---
      - type: entities
        title: "⚙️ Charging Parameters"
        show_header_toggle: false
        entities:
          - entity: input_number.ev_current_safe
            name: Safe current (reduced)
          - entity: input_number.ev_current_normal
            name: Normal current

      # --- Grid details ---
      - type: entities
        title: "💶 Tibber / Grid"
        show_header_toggle: false
        entities:
          - entity: sensor.electricity_price_${TIBBER_HOME}
            name: Current price
          - entity: sensor.voltage_phase1_${TIBBER_HOME}
            name: Grid voltage L1
          - entity: sensor.current_l1_${TIBBER_HOME}
            name: Grid current L1
          - entity: sensor.power_${TIBBER_HOME}
            name: House power (realtime)
          - entity: sensor.accumulated_cost_${TIBBER_HOME}
            name: House cost today

      # --- Voltage gauges ---
      - type: horizontal-stack
        cards:
          - type: gauge
            entity: sensor.voltage_phase1_${TIBBER_HOME}
            name: Grid Voltage
            min: 200
            max: 245
            severity:
              green: 218
              yellow: 210
              red: 0
          - type: gauge
            entity: sensor.goe_${GOE_SERIAL}_nrg_0
            name: Wallbox Voltage
            min: 200
            max: 245
            severity:
              green: 218
              yellow: 210
              red: 0

      # --- History graphs ---
      - type: history-graph
        title: "📉 Voltage (24h)"
        hours_to_show: 24
        entities:
          - entity: sensor.voltage_phase1_${TIBBER_HOME}
            name: Grid
          - entity: sensor.goe_${GOE_SERIAL}_nrg_0
            name: Wallbox

      - type: history-graph
        title: "⚡ Power (24h)"
        hours_to_show: 24
        entities:
          - entity: sensor.goe_${GOE_SERIAL}_nrg_11
            name: Charging
          - entity: sensor.power_${TIBBER_HOME}
            name: House

      - type: history-graph
        title: "🔋 Battery SoC (48h)"
        hours_to_show: 48
        entities:
          - entity: sensor.ix1_xdrive30_battery_hv_state_of_charge
            name: SoC

      - type: history-graph
        title: "⚡ Charging Efficiency (24h)"
        hours_to_show: 24
        entities:
          - entity: sensor.ev_charging_efficiency
            name: Efficiency %

      # --- Cost summary ---
      - type: entities
        title: "📅 Cost & Energy Summary"
        show_header_toggle: false
        entities:
          - entity: sensor.ev_charging_cost_monthly
            name: Cost this month
          - entity: sensor.ev_energy_monthly
            name: Energy this month
          - type: divider
          - entity: sensor.ev_charging_cost_quarterly
            name: Cost this quarter
          - entity: sensor.ev_energy_quarterly
            name: Energy this quarter
          - type: divider
          - entity: sensor.ev_charging_cost_yearly
            name: Cost this year
          - entity: sensor.ev_energy_yearly
            name: Energy this year

      # --- Bar charts ---
      - type: statistics-graph
        title: "📊 Monthly Cost"
        entities:
          - entity: sensor.ev_charging_cost_monthly
        period:
          calendar:
            period: month
        stat_types:
          - change
        chart_type: bar

      - type: statistics-graph
        title: "⚡ Monthly Energy"
        entities:
          - entity: sensor.ev_energy_monthly
        period:
          calendar:
            period: month
        stat_types:
          - change
        chart_type: bar
