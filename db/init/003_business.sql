create function api.create_project_with_first_task(name text, task_title text)
returns api.projects language plpgsql security invoker as $$
declare p app.projects;
declare result api.projects;
begin
  insert into app.projects(name) values (name) returning * into p;
  insert into app.tasks(project_id, title) values (p.id, task_title);
  select p.id, p.name, p.created_at into result;
  return result;
end
$$;

create function api.complete_task(task_id uuid) returns api.tasks
language plpgsql security invoker as $$
declare result api.tasks;
begin
  update app.tasks set completed_at = coalesce(completed_at, now()) where id = task_id
  returning id, project_id, title, completed_at, created_at into result;
  if not found then raise exception 'task not found' using errcode = 'P0002'; end if;
  return result;
end
$$;

create view api.project_stats with (security_invoker = true) as
select p.id, p.name, count(t.id)::integer as task_count,
       count(t.id) filter (where t.completed_at is not null)::integer as completed_count
from app.projects p left join app.tasks t on t.project_id = p.id
group by p.id, p.name;

grant select on api.project_stats to authenticated;
grant execute on function api.create_project_with_first_task(text, text), api.complete_task(uuid) to authenticated;
