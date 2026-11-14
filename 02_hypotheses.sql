-- Промежуточная аттестация 1 | проверка гипотез (стиль преподавателя: CTE + GROUP BY)
-- Требует: 01_setup_view.sql уже выполнен
-- psql -h 127.0.0.1 -p 5433 -U admin -d develop_issues -f 02_hypotheses.sql

-- =============================================================================
-- Шаблон (как на слайде dvdrental): fact vs normative → is_sla_breached
-- =============================================================================
WITH sla_assignments AS (
    SELECT
        ta.id AS assignment_id,
        ta.developer_id,
        tt.slug AS task_type,
        dr.slug AS developer_role,
        t.story_points,
        d.experience_years,
        o.industry,
        p.organization_id,
        t.project_id,
        (SELECT COUNT(*) FROM task_assignments ta2 WHERE ta2.task_id = ta.task_id) AS assignments_on_task,
        EXTRACT(EPOCH FROM (ta.completed_at - ta.assigned_at))::FLOAT / 86400 AS fact_days,
        EXTRACT(EPOCH FROM (
            COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3)) - ta.assigned_at
        ))::FLOAT / 86400 AS normative_days,
        CASE
            WHEN ta.completed_at > COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3))
            THEN 1 ELSE 0
        END AS is_sla_breached
    FROM task_assignments ta
    JOIN tasks t ON t.id = ta.task_id
    JOIN task_types tt ON tt.id = t.task_type_id
    JOIN projects p ON p.id = t.project_id
    JOIN organizations o ON o.id = p.organization_id
    JOIN developers d ON d.id = ta.developer_id
    JOIN developer_roles dr ON dr.id = ta.developer_role_id
    WHERE ta.completed_at IS NOT NULL
      AND (ta.due_at IS NOT NULL OR dr.slug = 'qa')
)
SELECT 'H1: overall breach rate' AS hypothesis,
       COUNT(*) AS cnt,
       ROUND(AVG(is_sla_breached::numeric) * 100, 2) AS breach_pct
FROM sla_assignments;

-- H2: тип задачи
WITH sla_assignments AS (
    SELECT tt.slug AS task_type,
           CASE WHEN ta.completed_at > COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3))
                THEN 1 ELSE 0 END AS is_sla_breached
    FROM task_assignments ta
    JOIN tasks t ON t.id = ta.task_id
    JOIN task_types tt ON tt.id = t.task_type_id
    JOIN developer_roles dr ON dr.id = ta.developer_role_id
    WHERE ta.completed_at IS NOT NULL AND (ta.due_at IS NOT NULL OR dr.slug = 'qa')
)
SELECT task_type, COUNT(*) AS cnt, ROUND(AVG(is_sla_breached::numeric) * 100, 2) AS breach_pct
FROM sla_assignments GROUP BY task_type ORDER BY breach_pct DESC;

-- H4: роль исполнителя
WITH sla_assignments AS (
    SELECT dr.slug AS developer_role,
           CASE WHEN ta.completed_at > COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3))
                THEN 1 ELSE 0 END AS is_sla_breached
    FROM task_assignments ta
    JOIN developer_roles dr ON dr.id = ta.developer_role_id
    WHERE ta.completed_at IS NOT NULL AND (ta.due_at IS NOT NULL OR dr.slug = 'qa')
)
SELECT developer_role, COUNT(*) AS cnt, ROUND(AVG(is_sla_breached::numeric) * 100, 2) AS breach_pct
FROM sla_assignments GROUP BY developer_role ORDER BY breach_pct DESC;

-- H7: опыт разработчика
WITH sla_assignments AS (
    SELECT d.experience_years,
           CASE WHEN ta.completed_at > COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3))
                THEN 1 ELSE 0 END AS is_sla_breached
    FROM task_assignments ta
    JOIN developers d ON d.id = ta.developer_id
    JOIN developer_roles dr ON dr.id = ta.developer_role_id
    WHERE ta.completed_at IS NOT NULL AND (ta.due_at IS NOT NULL OR dr.slug = 'qa')
)
SELECT
    CASE
        WHEN experience_years <= 2 THEN '0-2 years'
        WHEN experience_years <= 5 THEN '3-5 years'
        ELSE '6+ years'
    END AS experience_bucket,
    COUNT(*) AS cnt,
    ROUND(AVG(is_sla_breached::numeric) * 100, 2) AS breach_pct
FROM sla_assignments
GROUP BY 1 ORDER BY breach_pct DESC;

-- Уровень оценки: developer vs assignment (как customer vs rental)
SELECT developer_id, COUNT(*) AS cnt_assignment,
       ROUND(AVG(is_sla_breached::numeric), 4) AS breach_pct
FROM v_attestation_ml
GROUP BY developer_id
ORDER BY breach_pct ASC
LIMIT 5;

-- Заказчик (organization)
SELECT organization_name, industry, COUNT(*) AS cnt,
       ROUND(AVG(is_sla_breached::numeric) * 100, 2) AS breach_pct
FROM v_attestation_ml
GROUP BY organization_name, industry
ORDER BY breach_pct DESC;

-- Проект
SELECT project_name, COUNT(*) AS cnt,
       ROUND(AVG(is_sla_breached::numeric) * 100, 2) AS breach_pct
FROM v_attestation_ml
GROUP BY project_name
ORDER BY breach_pct DESC;
