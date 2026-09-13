# Core Platform stack

This directory contains the B17b-E CBS stack manifest derived from the qualified Core Platform implementation.

## Manifest

```text
stacks/core-platform/stack.env
```

Stack identity:

```text
CBS_STACK_ID=core-platform
CBS_STACK_VERSION=1
```

## Source facts

The B17b-E inventory and cross-check established the following Core Platform facts from the real platform repository.

### Python

```text
Python 3.12
```

The Core Platform repository declares Python 3.12 through `.python-version` and requires Python >=3.12 in `pyproject.toml`.

## Required workstation prerequisites

The manifest declares:

```text
GIT=REQUIRED
UV=REQUIRED
DOCKER=REQUIRED
DOCKER_COMPOSE=REQUIRED
PYTHON_312=REQUIRED
```

All five were observed PRESENT on the qualified workstation.

Qualified result:

```text
CBS_STACK_PREREQUISITE_REQUIRED_COUNT=5
CBS_STACK_PREREQUISITE_FAILURE_COUNT=0
CBS_STACK_STATE=READY
CBS_STACK_PREREQUISITE_EVALUATION_RESULT=PASS
```

## Required platform components

The manifest declares:

```text
FASTAPI=REQUIRED
SQLALCHEMY=REQUIRED
ALEMBIC=REQUIRED
POSTGRESQL=REQUIRED
POSTGIS=REQUIRED
PGVECTOR=REQUIRED
REDIS=REQUIRED
OPENSEARCH=REQUIRED
KONG=REQUIRED
KEYCLOAK=REQUIRED
```

These declarations were derived from the observed Core Platform Python and Docker Compose configuration.

A component marked REQUIRED belongs to the selected Core Platform stack definition.

It does not mean that the component runtime has been started or health-checked by B17b-E.

## Declared capabilities

```text
start
check
status
qualify
```

B17b-E records and resolves these capability declarations but does not execute them.

## Qualification boundary

The current manifest is not an installer.

It does not:

```text
install Python
install uv
install Docker
install Docker Compose
install or start PostgreSQL
install or start Redis
install or start OpenSearch
install or start Kong
install or start Keycloak
start the Core Platform API
allocate runtime resources
```

Runtime and local-instance lifecycle remain outside B17b-E.
