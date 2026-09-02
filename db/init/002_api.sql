\getenv jwt_secret JWT_SECRET
SELECT FORMAT('ALTER DATABASE %I SET app.jwt_secret = %L', CURRENT_DATABASE(), :'jwt_secret') \gexec
SELECT set_config('app.jwt_secret', :'jwt_secret', FALSE);

CREATE FUNCTION app.base64url(value text) RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT rtrim(translate(value, '+/', '-_'), '=') $$;

CREATE FUNCTION app.issue_token(p_user app.users) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET SEARCH_PATH = pg_catalog, PUBLIC, app
AS $$
DECLARE
  header text := app.base64url(encode(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8'), 'base64'));
  payload text;
  signature text;
BEGIN
  payload := app.base64url(encode(convert_to(json_build_object(
    'role', 'authenticated', 'sub', p_user.id, 'email', p_user.email,
    'iat', EXTRACT(EPOCH FROM now())::integer,
    'exp', EXTRACT(EPOCH FROM now() + INTERVAL '1 hour')::integer
  )::text, 'utf8'), 'base64'));
  signature := app.base64url(encode(hmac(header || '.' || payload, CURRENT_SETTING('app.jwt_secret'), 'sha256'), 'base64'));
  RETURN header || '.' || payload || '.' || signature;
END
$$;

CREATE FUNCTION api.register(email text, password text) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET SEARCH_PATH = pg_catalog, PUBLIC, app AS $$
DECLARE u app.users;
BEGIN
  IF length(register.password) < 12 THEN RAISE EXCEPTION 'password must contain at least 12 characters' USING ERRCODE = '22023'; END IF;
  INSERT INTO app.users(email, password_hash)
  VALUES (lower(trim(register.email)), crypt(register.password, gen_salt('bf', 12))) RETURNING * INTO u;
  RETURN json_build_object('token', app.issue_token(u), 'user', json_build_object('id', u.id, 'email', u.email));
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'email is already registered' USING ERRCODE = '23505';
END
$$;

CREATE FUNCTION api.login(email text, password text) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET SEARCH_PATH = pg_catalog, PUBLIC, app AS $$
DECLARE u app.users;
BEGIN
  SELECT * INTO u FROM app.users WHERE users.email = lower(trim(login.email));
  IF u.id IS NULL OR u.password_hash <> crypt(login.password, u.password_hash) THEN
    RAISE EXCEPTION 'invalid credentials' USING ERRCODE = '28P01';
  END IF;
  RETURN json_build_object('token', app.issue_token(u), 'user', json_build_object('id', u.id, 'email', u.email));
END
$$;

CREATE FUNCTION api.me() RETURNS TABLE(id uuid, email text, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET SEARCH_PATH = pg_catalog, PUBLIC, app AS $$
  SELECT id, email, created_at FROM app.users WHERE id = app.current_user_id()
$$;

GRANT EXECUTE ON FUNCTION api.register(text, text), api.login(text, text) TO anon;
GRANT EXECUTE ON FUNCTION api.me() TO authenticated;
