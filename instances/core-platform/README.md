# Core Platform local instance

This directory contains the B17b-F manifest for the existing qualified Core Platform local instance.

## Manifest

```text
instances/core-platform/instance.env
```

Identity:

```text
CBS_INSTANCE_ID=core-platform-local
CBS_INSTANCE_VERSION=1
CBS_INSTANCE_STACK_ID=core-platform
```

## Declared containers

```text
core-platform-redis
core-platform-opensearch
core-platform-postgres
core-platform-api
core-platform-kong
core-platform-keycloak
```

## Declared shared resources

```text
NETWORK=core-platform-network
EXTERNAL_VOLUME=b15-postgres18-target-data
```

## Qualified constraints

```text
FIXED_CONTAINER_NAMES=REQUIRED
FIXED_NETWORK_NAME=REQUIRED
FIXED_EXTERNAL_VOLUME=REQUIRED
FIXED_HOST_PORTS=REQUIRED
```

These constraints were cross-checked against the real Core Platform Docker Compose configuration.

The Compose configuration exposed 8 fixed host-port mappings during B17b-F qualification.

## Qualified real observation

The real local instance observation returned:

```text
CBS_INSTANCE_EXPECTED_RESOURCE_COUNT=8
CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT=0
CBS_INSTANCE_CONFLICT_RESOURCE_COUNT=0
CBS_INSTANCE_STATE=READY
CBS_INSTANCE_ACTION=REUSE
```

All six declared containers, the declared network and the declared external volume were found.

## Qualified ensure result

```text
CBS_INSTANCE_MANAGER_STATE_BEFORE=READY
CBS_INSTANCE_MANAGER_ACTION=REUSE
CBS_INSTANCE_MANAGER_MUTATION=NONE
CBS_INSTANCE_MANAGER_RESULT=PASS
```

No Docker resource was created, modified or removed.

## Interpretation of READY

READY means that all resources declared by this manifest were found in the expected resource classification.

READY does not qualify that every container is running or healthy.

Runtime health remains outside the B17b-F qualification boundary.

## Multi-instance boundary

The current Core Platform topology still uses fixed container names, a fixed network name, a fixed external volume and fixed host ports.

Therefore:

```text
MULTI_INSTANCE_COEXISTENCE=NOT_QUALIFIED
INSTANCE_CREATE=NOT_IMPLEMENTED
RUNTIME_HEALTH=NOT_QUALIFIED
```

This manifest describes the existing local instance. It does not define an isolated second Core Platform instance.
