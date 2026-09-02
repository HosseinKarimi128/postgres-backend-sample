CREATE FUNCTION api.create_project_with_first_task(name text, task_title text)
RETURNS api.projects LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE p app.projects;
DECLARE result api.projects;
BEGIN
  INSERT INTO app.projects(name) VALUES (create_project_with_first_task.name) RETURNING * INTO p;
  INSERT INTO app.tasks(project_id, title) VALUES (p.id, create_project_with_first_task.task_title);
  SELECT p.id, p.name, p.created_at INTO result;
  RETURN result;
END
$$;

CREATE FUNCTION api.complete_task(task_id uuid) RETURNS api.tasks
LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE result api.tasks;
BEGIN
  UPDATE app.tasks SET completed_at = COALESCE(completed_at, now()) WHERE id = complete_task.task_id
  RETURNING id, project_id, title, completed_at, created_at INTO result;
  IF NOT FOUND THEN RAISE EXCEPTION 'task not found' USING ERRCODE = 'P0002'; END IF;
  RETURN result;
END
$$;

CREATE VIEW api.project_stats WITH (security_invoker = TRUE) AS
SELECT p.id, p.name, count(t.id)::integer AS task_count,
       count(t.id) FILTER (WHERE t.completed_at IS NOT NULL)::integer AS completed_count
FROM app.projects p LEFT JOIN app.tasks t ON t.project_id = p.id
GROUP BY p.id, p.name;

GRANT SELECT ON api.project_stats TO authenticated;
GRANT EXECUTE ON FUNCTION api.create_project_with_first_task(text, text), api.complete_task(uuid) TO authenticated;
