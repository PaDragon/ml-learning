-- Запрос, формирующий витрину v_attestation_ml, — источник CSV
-- (develop_issues_dataset.csv), с которым будем работать в Jupyter Notebook
-- attestation_1_eda.ipynb.
--
CREATE OR REPLACE VIEW v_attestation_ml AS
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
    ROUND(EXTRACT(EPOCH FROM (ta.completed_at - ta.assigned_at)) / 3600, 2) AS hours_to_complete,
    ROUND(EXTRACT(EPOCH FROM (
        COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3)) - ta.assigned_at
    )) / 86400, 2) AS allowed_days,
    CASE
        WHEN ta.completed_at IS NOT NULL
         AND (
            (ta.due_at IS NOT NULL AND ta.completed_at > ta.due_at)
            OR (ta.due_at IS NULL AND dr.slug = 'qa'
                AND ta.completed_at > add_business_days(ta.assigned_at, 3))
         )
        THEN 1 ELSE 0
    END AS is_sla_breached,
    ROUND(GREATEST(
        EXTRACT(EPOCH FROM (
            ta.completed_at - COALESCE(ta.due_at, add_business_days(ta.assigned_at, 3))
        )) / 3600,
        0
    ), 2) AS hours_overdue,
    tt.slug AS task_type,
    t.priority,
    t.story_points,
    t.estimated_hours,
    t.sprint_id,
    ws.slug AS workflow_status,
    d.experience_years,
    el.name AS education_level,
    dr.slug AS developer_role,
    t.project_id,
    p.name AS project_name,
    p.code AS project_code,
    p.organization_id,
    o.name AS organization_name,
    o.industry,
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
WHERE ta.completed_at IS NOT NULL                 -- только завершённые назначения
  AND (ta.due_at IS NOT NULL OR dr.slug = 'qa');  -- у кого есть SLA: явный срок или SLA QA (3 раб. дня)
