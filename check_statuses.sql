SELECT ws.slug, ws.name, COUNT(*) AS cnt
FROM tasks t
JOIN workflow_statuses ws ON ws.id = t.workflow_status_id
GROUP BY ws.slug, ws.name, ws.sort_order
ORDER BY ws.sort_order;

SELECT COUNT(*) AS closed FROM tasks WHERE closed_at IS NOT NULL;
SELECT COUNT(*) AS open FROM tasks WHERE closed_at IS NULL;
