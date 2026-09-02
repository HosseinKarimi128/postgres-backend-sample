CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA app;
CREATE SCHEMA api;

CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
GRANT anon, authenticated TO CURRENT_USER;
GRANT USAGE ON SCHEMA api TO anon, authenticated;

CREATE TABLE app.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE CHECK (email = lower(email)),
  password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 120),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES app.projects(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 200),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX projects_owner_id_idx ON app.projects(owner_id);
CREATE INDEX tasks_owner_id_idx ON app.tasks(owner_id);
CREATE INDEX tasks_project_id_idx ON app.tasks(project_id);

CREATE FUNCTION app.current_user_id() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(CURRENT_SETTING('request.jwt.claim.sub', TRUE), '')::uuid
$$;

CREATE FUNCTION app.set_owner_id() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.owner_id := app.current_user_id();
  RETURN NEW;
END
$$;

CREATE TRIGGER projects_set_owner BEFORE INSERT ON app.projects
FOR EACH ROW EXECUTE FUNCTION app.set_owner_id();
CREATE TRIGGER tasks_set_owner BEFORE INSERT ON app.tasks
FOR EACH ROW EXECUTE FUNCTION app.set_owner_id();

ALTER TABLE app.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY projects_owned ON app.projects FOR ALL TO authenticated
USING (owner_id = app.current_user_id())
WITH CHECK (owner_id = app.current_user_id());

CREATE POLICY tasks_owned ON app.tasks FOR ALL TO authenticated
USING (owner_id = app.current_user_id())
WITH CHECK (
  owner_id = app.current_user_id()
  AND EXISTS (SELECT 1 FROM app.projects p WHERE p.id = project_id AND p.owner_id = app.current_user_id())
);

GRANT SELECT, INSERT, UPDATE, DELETE ON app.projects, app.tasks TO authenticated;
CREATE VIEW api.projects WITH (security_invoker = TRUE) AS SELECT id, name, created_at FROM app.projects;
CREATE VIEW api.tasks WITH (security_invoker = TRUE) AS SELECT id, project_id, title, completed_at, created_at FROM app.tasks;
GRANT SELECT, INSERT, UPDATE, DELETE ON api.projects, api.tasks TO authenticated;
