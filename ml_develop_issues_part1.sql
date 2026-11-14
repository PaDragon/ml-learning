-- Часть 1: гипотезы и SQL-анализ develop_issues (нарушение SLA)
-- База: develop_issues | Целевая переменная: is_sla_breached на уровне task_assignment

-- =============================================================================
-- 0. Вспомогательная функция: +N рабочих дней (для QA без due_at)
-- =============================================================================
CREATE OR REPLACE FUNCTION add_business_days(ts timestamp without time zone, n integer)
RETURNS timestamp without time zone AS $$
DECLARE
    d date := ts::date;
    cnt integer := 0;
BEGIN
    WHILE cnt < n LOOP
        d := d + 1;
        IF EXTRACT(DOW FROM d) NOT IN (0, 6) THEN
            cnt := cnt + 1;
        END IF;
    END LOOP;
    RETURN d + (ts - ts::date);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- =============================================================================
-- 1. VIEW: витрина назначений с effective_due_at и is_sla_breached
-- =============================================================================
CREATE OR REPLACE VIEW v_task_assignment_sla AS
SELECT
    ta.id AS assignment_id,
    ta.task_id,
    ta.developer_id,
    ta.developer_role_id,
    ta.assigned_at,
    ta.due_at,
    ta.completed_at,
    CASE
        WHEN ta.due_at IS NOT NULL THEN ta.due_at
        WHEN dr.slug = 'qa' THEN add_business_days(ta.assigned_at, 3)
        ELSE NULL
    END AS effective_due_at,
    EXTRACT(EPOCH FROM (ta.completed_at - ta.assigned_at)) / 3600 AS hours_to_complete,
    EXTRACT(EPOCH FROM (
        COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3)) - ta.assigned_at
    )) / 86400 AS allowed_days,
    CASE
        WHEN ta.completed_at IS NOT NULL
         AND (
            (ta.due_at IS NOT NULL AND ta.completed_at > ta.due_at)
            OR (ta.due_at IS NULL AND dr.slug = 'qa' AND ta.completed_at > add_business_days(ta.assigned_at, 3))
         )
        THEN 1 ELSE 0
    END AS is_sla_breached,
    CASE
        WHEN ta.completed_at IS NOT NULL THEN
            GREATEST(
                EXTRACT(EPOCH FROM (
                    ta.completed_at - COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3))
                )) / 3600,
                0
            )
        ELSE NULL
    END AS hours_overdue,
    t.task_type_id,
    tt.slug AS task_type,
    t.priority,
    t.story_points,
    t.estimated_hours,
    t.sprint_id,
    ws.slug AS workflow_status,
    d.experience_years,
    el.name AS education_level,
    dr.slug AS developer_role,
    o.industry,
    o.name AS organization_name,
    (SELECT COUNT(*) FROM task_assignments ta2 WHERE ta2.task_id = ta.task_id) AS assignments_on_task,
    EXISTS (
        SELECT 1 FROM task_label_assignments tla
        JOIN labels l ON l.id = tla.label_id
        WHERE tla.task_id = ta.task_id AND l.slug = 'high_priority' AND tla.is_active = true
    ) AS has_high_priority
FROM task_assignments ta
JOIN tasks t ON t.id = ta.task_id
JOIN task_types tt ON tt.id = t.task_type_id
JOIN workflow_statuses ws ON ws.id = t.workflow_status_id
JOIN developers d ON d.id = ta.developer_id
JOIN education_levels el ON el.id = d.education_level_id
JOIN developer_roles dr ON dr.id = ta.developer_role_id
JOIN projects p ON p.id = t.project_id
JOIN organizations o ON o.id = p.organization_id
WHERE ta.completed_at IS NOT NULL
  AND (
      ta.due_at IS NOT NULL
      OR dr.slug = 'qa'
  );

-- =============================================================================
-- 2. H1: масштаб проблемы
-- =============================================================================
SELECT
    COUNT(*) AS total_assignments,
    SUM(is_sla_breached) AS breached_count,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct,
    ROUND(AVG(hours_overdue) FILTER (WHERE is_sla_breached = 1), 2) AS avg_hours_overdue
FROM v_task_assignment_sla;

-- =============================================================================
-- 3. Уровень: assignment vs developer
-- =============================================================================
SELECT
    CASE
        WHEN breach_rate = 0 THEN '0%'
        WHEN breach_rate <= 0.25 THEN '1-25%'
        WHEN breach_rate <= 0.50 THEN '26-50%'
        WHEN breach_rate <= 0.75 THEN '51-75%'
        ELSE '76-100%'
    END AS developer_breach_bucket,
    COUNT(*) AS developers_count
FROM (
    SELECT developer_id, AVG(is_sla_breached::numeric) AS breach_rate
    FROM v_task_assignment_sla
    GROUP BY developer_id
) t
GROUP BY 1
ORDER BY 1;

-- =============================================================================
-- 4. H2: task_type (incident vs development)
-- =============================================================================
SELECT
    task_type,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
GROUP BY task_type
ORDER BY breach_pct DESC;

-- =============================================================================
-- 5. H3: allowed_days (короткий срок → выше риск)
-- =============================================================================
SELECT
    CASE
        WHEN allowed_days <= 3 THEN '<=3 days'
        WHEN allowed_days <= 5 THEN '4-5 days'
        WHEN allowed_days <= 7 THEN '6-7 days'
        ELSE '8+ days'
    END AS allowed_bucket,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
WHERE allowed_days IS NOT NULL
GROUP BY 1
ORDER BY breach_pct DESC;

-- =============================================================================
-- 6. H4: developer_role
-- =============================================================================
SELECT
    developer_role,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
GROUP BY developer_role
ORDER BY breach_pct DESC;

-- =============================================================================
-- 7. H5: story_points
-- =============================================================================
SELECT
    CASE
        WHEN story_points <= 3 THEN '1-3 SP'
        WHEN story_points <= 8 THEN '4-8 SP'
        ELSE '9+ SP'
    END AS story_points_bucket,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
WHERE story_points IS NOT NULL
GROUP BY 1
ORDER BY breach_pct DESC;

-- =============================================================================
-- 8. H6: число передач (assignments_on_task)
-- =============================================================================
SELECT
    CASE
        WHEN assignments_on_task = 1 THEN '1 assignment'
        WHEN assignments_on_task = 2 THEN '2 assignments'
        WHEN assignments_on_task = 3 THEN '3 assignments'
        ELSE '4+ assignments'
    END AS handoff_bucket,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
GROUP BY 1
ORDER BY breach_pct DESC;

-- =============================================================================
-- 9. H7: experience_years и education
-- =============================================================================
SELECT
    CASE
        WHEN experience_years <= 2 THEN '0-2 years'
        WHEN experience_years <= 5 THEN '3-5 years'
        ELSE '6+ years'
    END AS experience_bucket,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
GROUP BY 1
ORDER BY breach_pct DESC;

SELECT
    education_level,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
GROUP BY education_level
ORDER BY breach_pct DESC;

-- =============================================================================
-- 10. H8: high_priority label
-- =============================================================================
SELECT
    has_high_priority,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
GROUP BY has_high_priority
ORDER BY has_high_priority DESC;

-- =============================================================================
-- 11. H9: industry (заказчик)
-- =============================================================================
SELECT
    industry,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla
GROUP BY industry
ORDER BY breach_pct DESC;

-- =============================================================================
-- 12. H10: dwell time in in_discussion → breach на задаче
-- =============================================================================
WITH ordered AS (
    SELECT
        tst.task_id,
        ws.slug AS status_slug,
        tst.changed_at,
        LEAD(tst.changed_at) OVER (PARTITION BY tst.task_id ORDER BY tst.changed_at) AS next_at
    FROM task_status_transitions tst
    JOIN workflow_statuses ws ON ws.id = tst.to_status_id
),
task_dwell AS (
    SELECT
        task_id,
        SUM(EXTRACT(EPOCH FROM (next_at - changed_at)) / 3600) AS total_discussion_hours
    FROM ordered
    WHERE status_slug = 'in_discussion' AND next_at IS NOT NULL
    GROUP BY task_id
)
SELECT
    CASE
        WHEN COALESCE(td.total_discussion_hours, 0) = 0 THEN 'no discussion'
        WHEN td.total_discussion_hours <= 24 THEN '<=24h'
        WHEN td.total_discussion_hours <= 72 THEN '25-72h'
        ELSE '73h+'
    END AS discussion_dwell_bucket,
    COUNT(*) AS assignments,
    ROUND(100.0 * AVG(v.is_sla_breached::numeric), 2) AS breach_pct
FROM v_task_assignment_sla v
LEFT JOIN task_dwell td ON td.task_id = v.task_id
GROUP BY 1
ORDER BY breach_pct DESC;

-- =============================================================================
-- 13. Датасет для ML (часть 2) — sample + баланс классов
-- =============================================================================
SELECT
    assignment_id,
    task_id,
    developer_id,
    developer_role,
    task_type,
    story_points,
    allowed_days,
    experience_years,
    education_level,
    industry,
    assignments_on_task,
    has_high_priority,
    sprint_id,
    is_sla_breached AS target_is_sla_breached
FROM v_task_assignment_sla
ORDER BY assignment_id
LIMIT 20;

SELECT
    is_sla_breached,
    COUNT(*) AS cnt,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM v_task_assignment_sla
GROUP BY is_sla_breached
ORDER BY is_sla_breached;
