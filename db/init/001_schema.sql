create extension if not exists pgcrypto;
create schema app;
create schema api;

create role anon nologin;
create role authenticated nologin;
grant anon, authenticated to current_user;
grant usage on schema api to anon, authenticated;

create table app.users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (email = lower(email)),
  password_hash text not null,
  created_at timestamptz not null default now()
);

create table app.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references app.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  created_at timestamptz not null default now()
);

create table app.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references app.projects(id) on delete cascade,
  owner_id uuid not null references app.users(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 200),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create index projects_owner_id_idx on app.projects(owner_id);
create index tasks_owner_id_idx on app.tasks(owner_id);
create index tasks_project_id_idx on app.tasks(project_id);

create function app.current_user_id() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create function app.set_owner_id() returns trigger language plpgsql as $$
begin
  new.owner_id := app.current_user_id();
  return new;
end
$$;

create trigger projects_set_owner before insert on app.projects
for each row execute function app.set_owner_id();
create trigger tasks_set_owner before insert on app.tasks
for each row execute function app.set_owner_id();

alter table app.projects enable row level security;
alter table app.tasks enable row level security;

create policy projects_owned on app.projects for all to authenticated
using (owner_id = app.current_user_id())
with check (owner_id = app.current_user_id());

create policy tasks_owned on app.tasks for all to authenticated
using (owner_id = app.current_user_id())
with check (
  owner_id = app.current_user_id()
  and exists (select 1 from app.projects p where p.id = project_id and p.owner_id = app.current_user_id())
);

grant select, insert, update, delete on app.projects, app.tasks to authenticated;
create view api.projects with (security_invoker = true) as select id, name, created_at from app.projects;
create view api.tasks with (security_invoker = true) as select id, project_id, title, completed_at, created_at from app.tasks;
grant select, insert, update, delete on api.projects, api.tasks to authenticated;
