\getenv jwt_secret JWT_SECRET
select format('alter database %I set app.jwt_secret = %L', current_database(), :'jwt_secret') \gexec
select set_config('app.jwt_secret', :'jwt_secret', false);

create function app.base64url(value text) returns text
language sql immutable strict as $$ select rtrim(translate(value, '+/', '-_'), '=') $$;

create function app.issue_token(p_user app.users) returns text
language plpgsql stable security definer
set search_path = pg_catalog, public, app
as $$
declare
  header text := app.base64url(encode(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8'), 'base64'));
  payload text;
  signature text;
begin
  payload := app.base64url(encode(convert_to(json_build_object(
    'role', 'authenticated', 'sub', p_user.id, 'email', p_user.email,
    'iat', extract(epoch from now())::integer,
    'exp', extract(epoch from now() + interval '1 hour')::integer
  )::text, 'utf8'), 'base64'));
  signature := app.base64url(encode(hmac(header || '.' || payload, current_setting('app.jwt_secret'), 'sha256'), 'base64'));
  return header || '.' || payload || '.' || signature;
end
$$;

create function api.register(email text, password text) returns json
language plpgsql security definer set search_path = pg_catalog, public, app as $$
declare u app.users;
begin
  if length(password) < 12 then raise exception 'password must contain at least 12 characters' using errcode = '22023'; end if;
  insert into app.users(email, password_hash)
  values (lower(trim(email)), crypt(password, gen_salt('bf', 12))) returning * into u;
  return json_build_object('token', app.issue_token(u), 'user', json_build_object('id', u.id, 'email', u.email));
exception when unique_violation then
  raise exception 'email is already registered' using errcode = '23505';
end
$$;

create function api.login(email text, password text) returns json
language plpgsql security definer set search_path = pg_catalog, public, app as $$
declare u app.users;
begin
  select * into u from app.users where users.email = lower(trim(login.email));
  if u.id is null or u.password_hash <> crypt(password, u.password_hash) then
    raise exception 'invalid credentials' using errcode = '28P01';
  end if;
  return json_build_object('token', app.issue_token(u), 'user', json_build_object('id', u.id, 'email', u.email));
end
$$;

create function api.me() returns table(id uuid, email text, created_at timestamptz)
language sql stable security invoker as $$
  select id, email, created_at from app.users where id = app.current_user_id()
$$;

grant execute on function api.register(text, text), api.login(text, text) to anon;
grant execute on function api.me() to authenticated;
grant select on app.users to authenticated;
