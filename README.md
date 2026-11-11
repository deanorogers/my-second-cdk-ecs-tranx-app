# Quarkus transactions service

A simple Java Quarkus application exposing an in-memory `Transaction` API (hard-coded data, no database).

## Endpoints

- `GET /` returns a plain-text status message.
- `GET /transactions` lists transactions; optional `?accountId=1001` filter. Its `INSTANCE_FROM` response header contains the `INSTANCE_NAME` environment variable.
- `GET /transactions/{id}` returns a single transaction or `404`.
- `POST /transactions` creates a transaction (`accountId`, `type` CREDIT|DEBIT, positive `amount`, `currency`; optional `id`, `description`, `timestamp`) and returns `201 Created`.

Seed data covers accounts `1001`, `2001` and `3001` (ids `t-1001`..`t-3001`).

Set `INSTANCE_NAME` in the application environment. It is required at startup;
the underscore in the response header may be filtered by some proxies.

## Run, test, package

```bash
export INSTANCE_NAME=local
./mvnw quarkus:dev
./mvnw test
./mvnw package
```

## Docker

```bash
docker build -t quarkus-transactions:local .
docker run --rm -p 8080:80 -e INSTANCE_NAME=local quarkus-transactions:local
scripts/smoke-test.sh http://localhost:8080
```

## Deploy to ECS

Copy `.env.deploy.example` to `.env.deploy.local`, fill in the values, then run `scripts/deploy-ecs.sh`.
On success the image tag is written to SSM parameter `/my-second-cdk-ecs-tranx-service/image-tag` (override with `SSM_LAST_IMAGE_PARAM`).
