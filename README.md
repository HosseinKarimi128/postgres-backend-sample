# PostgreSQL Backend Sample

A database-first backend using only PostgreSQL and PostgREST. PostgreSQL owns authentication, authorization, validation, transactions, business rules, and reporting; PostgREST exposes them over HTTP.

## Run

```bash
cp .env.example .env
docker compose up -d
./tests/smoke.sh
```

The API is available at `http://localhost:3000`.

## API

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/rpc/register` | Create a user and return a JWT |
| POST | `/rpc/login` | Verify a password and return a JWT |
| GET | `/rpc/me` | Return the current user |
| GET/POST/PATCH/DELETE | `/projects` | RLS-protected project CRUD |
| GET/POST/PATCH/DELETE | `/tasks` | RLS-protected task CRUD |
| POST | `/rpc/create_project_with_first_task` | Transactional operation |
| POST | `/rpc/complete_task` | Complete an owned task |
| GET | `/project_stats` | Per-user reporting view |

## Example

```bash
curl -s http://localhost:3000/rpc/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"hoka@example.com","password":"correct-horse-battery"}'

export TOKEN='<returned-token>'
curl -s http://localhost:3000/rpc/create_project_with_first_task \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Postgres backend","task_title":"Ship sample"}'
```

`app` is private and contains tables and helpers. `api` is the only exposed schema. Identity always comes from verified JWT claims, never a caller-supplied user ID.

For production, use a secret manager, TLS, rotated JWT keys, proper migrations, backups, and connection pooling.
