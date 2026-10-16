-- =============================================================================
-- FILE: predictive_maintenance_analytics.sql
-- PROJECT: AI4I 2020 Industrial Predictive Maintenance Analytics Pipeline
-- AUTHOR: Technical Analytics Portfolio
-- DATASET: AI4I 2020 Predictive Maintenance Dataset (10,000 telemetry logs)
-- TARGET ENGINE: PostgreSQL / MySQL 8.0+ / SQLite 3.25+
-- DESCRIPTION: End-to-end SQL analysis pipeline covering data auditing, single-
--              variable thresholding, time-series anomaly detection, and a 
--              rule-based prescriptive decision engine.
-- =============================================================================

-- =============================================================================
-- SECTION 1: DATA INTEGRITY & FAILURE OVERLAP AUDIT
-- Objective: Validate baseline metrics, check failure mode contributions, and 
--            detect multi-label overlap discrepancies in target flags.
-- =============================================================================

-- Query 1.1: Overall Operational Failure Baseline
-- Answers: What is the baseline operational failure rate across the dataset?
SELECT 
    COUNT(*) AS total_operations, 
    SUM(machine_failure) AS failed_operations,
    ROUND(100.0 * (SUM(machine_failure) / COUNT(*)), 2) AS failure_pct 
FROM sensor_data;


-- Query 1.2: Failure Mode Contribution Breakdown
-- Answers: Which failure mechanism (TWF, HDF, PWF, OSF, RNF) dominates total failures?
SELECT 
    SUM(TWF) AS Tool_Wear_Failures, 
    ROUND(100.0 * SUM(TWF) / (SUM(TWF) + SUM(HDF) + SUM(PWF) + SUM(OSF) + SUM(RNF)), 2) AS twf_contri,
    
    SUM(HDF) AS Heat_Failures, 
    ROUND(100.0 * SUM(HDF) / (SUM(TWF) + SUM(HDF) + SUM(PWF) + SUM(OSF) + SUM(RNF)), 2) AS hdf_contri,
    
    SUM(PWF) AS Power_Failures, 
    ROUND(100.0 * SUM(PWF) / (SUM(TWF) + SUM(HDF) + SUM(PWF) + SUM(OSF) + SUM(RNF)), 2) AS pwf_contri,
    
    SUM(OSF) AS Overstrain_Failures, 
    ROUND(100.0 * SUM(OSF) / (SUM(TWF) + SUM(HDF) + SUM(PWF) + SUM(OSF) + SUM(RNF)), 2) AS osf_contri,
    
    SUM(RNF) AS Random_Failures, 
    ROUND(100.0 * SUM(RNF) / (SUM(TWF) + SUM(HDF) + SUM(PWF) + SUM(OSF) + SUM(RNF)), 2) AS rnf_contri
FROM sensor_data;


-- Query 1.3: Multi-Label Overlap & Target Variable Discrepancy Check
-- Answers: Do multiple failure triggers happen on single runs, and are any unmapped?
SELECT 
    SUM(Machine_failure) AS total_failed_incidents,
    (SUM(TWF) + SUM(HDF) + SUM(PWF) + SUM(OSF) + SUM(RNF)) AS total_failure_triggers,
    (SUM(TWF) + SUM(HDF) + SUM(PWF) + SUM(OSF) + SUM(RNF)) - SUM(Machine_failure) AS multi_failure_overlaps
FROM sensor_data;

SELECT 
    TWF, HDF, PWF, OSF, RNF,
    Machine_failure
FROM sensor_data
WHERE (TWF = 1 OR HDF = 1 OR PWF = 1 OR OSF = 1 OR RNF = 1)
  AND Machine_failure = 0;


-- =============================================================================
-- SECTION 2: SINGLE-VARIABLE FEATURE THRESHOLDING & BINNING
-- Objective: Evaluate threshold cutoffs across machine variants, thermal zones, 
--            tool wear buckets, and mechanical power bands.
-- =============================================================================

-- Query 2.1: Performance Breakdown Across Machine Quality Variants (H, M, L)
-- Answers: How do failure rates and telemetry metrics vary across product types?
SELECT 
    Type, 
    COUNT(*) AS total_operations,
    SUM(Machine_failure) AS total_machine_failures, 
    ROUND(100.0 * SUM(Machine_failure) / COUNT(*), 2) AS failure_pct,
    ROUND(AVG(Tool_wear_min), 2) AS avg_tool_wear,
    ROUND(AVG(Torque_Nm), 2) AS avg_torque,
    ROUND(AVG(Power_kW), 2) AS avg_power, 
    ROUND(AVG(Temp_Diff_K), 2) AS avg_temp_diff_k
FROM sensor_data
GROUP BY Type
ORDER BY failure_pct DESC;


-- Query 2.2: Thermal Dissipation Hazard Analysis
-- Answers: Does a low temperature differential (Delta T < 8.6 K) drive HDF failure?
WITH ThermalBinned AS (
    SELECT *,
        CASE 
            WHEN Temp_Diff_K < 8.6 THEN 'Low Thermal Dissipation'
            ELSE 'Normal Thermal Dissipation'
        END AS thermal_diff_zone
    FROM sensor_data
)
SELECT 
    thermal_diff_zone, 
    COUNT(*) AS total_operations, 
    SUM(Machine_failure) AS total_machine_failures,
    SUM(HDF) AS hdf_count,
    ROUND(100.0 * SUM(HDF) / COUNT(*), 2) AS hdf_failure_pct
FROM ThermalBinned
GROUP BY thermal_diff_zone;


-- Query 2.3: Tool Wear Degradation Bucketing
-- Answers: At what 50-minute tool wear interval does TWF failure escalate?
WITH WearBinned AS (
    SELECT *, 
        CASE 
            WHEN Tool_wear_min <= 50 THEN '000 - 050 min'
            WHEN Tool_wear_min <= 100 THEN '051 - 100 min'
            WHEN Tool_wear_min <= 150 THEN '101 - 150 min'
            WHEN Tool_wear_min <= 200 THEN '151 - 200 min'
            ELSE '> 200 min'
        END AS tool_wear_bucket
    FROM sensor_data
)
SELECT 
    tool_wear_bucket,
    COUNT(*) AS total_operations,
    SUM(TWF) AS twf_cnt,
    SUM(Machine_failure) AS total_machine_failures,
    ROUND(100.0 * SUM(TWF) / COUNT(*), 2) AS twf_failure_rate_pct
FROM WearBinned
GROUP BY tool_wear_bucket
ORDER BY tool_wear_bucket;


-- Query 2.4: Mechanical Power Output Band Analysis
-- Answers: What is the failure distribution across Low, Nominal, and High Power bands?
WITH PowerBinned AS (
    SELECT *,
        CASE 
            WHEN Power_kW < 2.0 THEN 'Low Power (<2kW)'
            WHEN Power_kW BETWEEN 2.0 AND 6.0 THEN 'Nominal Power (2-6kW)'
            WHEN Power_kW > 6.0 THEN 'High Power (>6kW)'
        END AS power_band
    FROM sensor_data
)
SELECT 
    power_band,
    COUNT(*) AS total_operations,
    SUM(Machine_failure) AS total_failures,
    SUM(PWF) AS total_power_failures,
    SUM(OSF) AS total_overstrain_failures,
    ROUND(100.0 * SUM(Machine_failure) / COUNT(*), 2) AS failure_rate_pct
FROM PowerBinned
GROUP BY power_band
ORDER BY failure_rate_pct DESC;


-- =============================================================================
-- SECTION 3: STATISTICAL ANOMALY DETECTION & TIME-SERIES WINDOWING
-- Objective: Execute advanced feature engineering using window functions (LAG, AVG 
--            OVER), statistical standardization (Z-scores), and run-length logic.
-- =============================================================================

-- Query 3.1: Mean Time / Cycles Between Failures (MTBF Run-Length Tracking)
-- Answers: What is the operational run length between consecutive failures?
WITH IndexedTelemetry AS (
    SELECT *, ROW_NUMBER() OVER() AS op_index 
    FROM sensor_data
),
FailureSequence AS (
    SELECT *, 
        LAG(op_index) OVER (ORDER BY op_index) AS prev_failure_index 
    FROM IndexedTelemetry 
    WHERE Machine_failure = 1
)
SELECT 
    op_index AS failure_event_id,
    COALESCE(op_index - prev_failure_index, op_index) AS ops_between_failures
FROM FailureSequence;


-- Query 3.2: Multivariate Z-Score Strain Anomaly Flagging
-- Answers: Can combining normalized Z-scores of speed and torque isolate high strain?
WITH ZScoreCalculations AS (
    SELECT *,
        (Torque_Nm - AVG(Torque_Nm) OVER()) / STDDEV(Torque_Nm) OVER() AS zscore_torque,
        (Rotational_speed_rpm - AVG(Rotational_speed_rpm) OVER()) / STDDEV(Rotational_speed_rpm) OVER() AS zscore_speed
    FROM sensor_data
),
AnomalyFlagged AS (
    SELECT *,
        CASE 
            WHEN zscore_speed < -1.5 AND zscore_torque > 1.5 THEN 'High Strain Anomaly'
            ELSE 'Normal Operational Envelope' 
        END AS flag_anomalies
    FROM ZScoreCalculations
)
SELECT 
    flag_anomalies, 
    COUNT(*) AS total_ops, 
    SUM(Machine_failure) AS total_failures, 
    ROUND(AVG(Torque_Nm), 2) AS avg_torque, 
    ROUND(AVG(Rotational_speed_rpm), 2) AS avg_speed,
    ROUND(100.0 * SUM(Machine_failure) / COUNT(*), 2) AS failure_rate_pct
FROM AnomalyFlagged
GROUP BY flag_anomalies;


-- Query 3.3: Pre-Failure Precursor Analysis & Spike Delta Aggregation
-- Answers: What is the 5-step pre-failure baseline power/strain and spike delta?
WITH FailureEvents AS (
    SELECT 
        Type,
        Tool_wear_min,
        Power_kW,
        Strain_Index,
        Machine_failure,
        CASE 
            WHEN Machine_failure = 1 AND LAG(Machine_failure, 1, 0) OVER (PARTITION BY Type ORDER BY Tool_wear_min) = 0 
            THEN 1 ELSE 0 
        END AS is_failure_onset
    FROM sensor_data
),
PrecursorWindow AS (
    SELECT 
        Type,
        Tool_wear_min,
        Power_kW,
        Strain_Index,
        Machine_failure,
        is_failure_onset,
        AVG(Power_kW) OVER (
            PARTITION BY Type 
            ORDER BY Tool_wear_min 
            ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING
        ) AS avg_precursor_power,
        AVG(Strain_Index) OVER (
            PARTITION BY Type 
            ORDER BY Tool_wear_min 
            ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING
        ) AS avg_precursor_strain
    FROM FailureEvents
)
SELECT 
    Type,
    Tool_wear_min AS failure_tool_wear,
    Power_kW AS failure_power,
    ROUND(avg_precursor_power, 2) AS avg_power_5_steps_prior,
    ROUND(Power_kW - avg_precursor_power, 2) AS power_spike_delta,
    Strain_Index AS failure_strain,
    ROUND(avg_precursor_strain, 2) AS avg_strain_5_steps_prior
FROM PrecursorWindow
WHERE is_failure_onset = 1
ORDER BY power_spike_delta DESC;


-- =============================================================================
-- SECTION 4: PRESCRIPTIVE ANALYTICS & DECISION SYSTEMS
-- Objective: Synthesize telemetry metrics into actionable root-cause summaries 
--            and a rule-based prescriptive maintenance classifier.
-- =============================================================================

-- Query 4.1: Failure Mode Root Cause Drivers & MTWF by Machine Variant
-- Answers: What is the primary failure driver and MTWF across variants (H, M, L)?
WITH FailureMetrics AS (
    SELECT 
        Type,
        CASE 
            WHEN TWF = 1 THEN 'Tool Wear Failure'
            WHEN HDF = 1 THEN 'Heat Dissipation Failure'
            WHEN PWF = 1 THEN 'Power Failure'
            WHEN OSF = 1 THEN 'Overstrain Failure'
            WHEN RNF = 1 THEN 'Random Failure'
            ELSE 'No Failure'
        END AS failure_mode,
        Tool_wear_min,
        Power_kW,
        Strain_Index,
        Temp_Diff_K
    FROM sensor_data
)
SELECT 
    Type,
    failure_mode,
    COUNT(*) AS total_incidents,
    ROUND(AVG(Tool_wear_min), 1) AS mean_tool_wear_at_failure,
    ROUND(AVG(Power_kW), 2) AS avg_power_at_failure,
    ROUND(AVG(Temp_Diff_K), 2) AS avg_temp_diff_at_failure,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY Type), 2) AS percent_of_type_failures
FROM FailureMetrics
WHERE failure_mode != 'No Failure'
GROUP BY Type, failure_mode
ORDER BY Type, total_incidents DESC;


-- Query 4.2: Rule-Based Prescriptive Maintenance Classifier
-- Answers: How effectively do multi-variable rules classify health states?
WITH LiveHealthScoring AS (
    SELECT *,
        (2 * PI() * Rotational_speed_rpm * Torque_Nm) / 60000 AS p_mech_kw,
        (Torque_Nm - AVG(Torque_Nm) OVER()) / STDDEV(Torque_Nm) OVER() AS z_torque,
        (Rotational_speed_rpm - AVG(Rotational_speed_rpm) OVER()) / STDDEV(Rotational_speed_rpm) OVER() AS z_speed
    FROM sensor_data
),
PrescriptiveClassified AS (
    SELECT *,
        CASE 
            WHEN Tool_wear_min >= 200 THEN 'CRITICAL: Replace Tool Immediately'
            WHEN Temp_Diff_K < 8.6 THEN 'WARNING: Reduce Feed Rate (Cooling Hazard)'
            WHEN z_torque > 1.8 AND z_speed < -1.2 THEN 'ALERT: High Mechanical Strain'
            WHEN p_mech_kw > 8 OR p_mech_kW < 3.8 THEN 'WARNING: Approaching Power Failure Limit'
            ELSE 'OPTIMAL: Operating in Safe Envelope'
        END AS prescriptive_action
    FROM LiveHealthScoring
)
SELECT 
    prescriptive_action,
    COUNT(*) AS total_operations,
    SUM(Machine_failure) AS intercepted_failures,
    ROUND(100.0 * SUM(Machine_failure) / COUNT(*), 2) AS zone_failure_rate_pct
FROM PrescriptiveClassified
GROUP BY prescriptive_action
ORDER BY intercepted_failures DESC;