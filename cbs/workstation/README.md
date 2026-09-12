# Workstation

B17b-B implements the minimal CBS workstation qualification layer.

The implementation is read-only: it observes prerequisites and local isolation state but does not install, start, stop, remove or reconfigure workstation resources.

## Implemented components

```text
cbs/workstation/contract.sh
cbs/workstation/prerequisite_checker.sh
cbs/workstation/isolation_checker.sh
cbs/workstation/workstation_manager.sh
```

## Workstation contract

Contract version:

```text
CBS_WORKSTATION_CONTRACT_VERSION=1
```

Qualified return codes:

```text
0   success
10  prerequisite failure
20  isolation conflict
30  invalid input or unexpected checker result
64  invalid context or usage
```

Qualified workstation states:

```text
READY
INCOMPLETE
CONFLICT
UNKNOWN
```

Qualified resource classifications:

```text
RESOURCE_EXPECTED
RESOURCE_EXTERNAL
RESOURCE_CONFLICT
RESOURCE_UNKNOWN
```

## Prerequisite Checker

The current checker validates:

```text
git
ssh
curl
docker
uv
Docker Engine
Docker Compose
Python 3.12
```

The checker does not install missing prerequisites.

On the qualified workstation:

```text
CBS_PREREQUISITE_REQUIRED_FAILURES=0
CBS_PREREQUISITE_RESULT=PASS
```

## Isolation Checker

The isolation checker observes Docker resources associated with the current context.

Qualified resource types:

```text
CONTAINER
NETWORK
VOLUME
PORT
```

Resources associated with the current context are classified as RESOURCE_EXPECTED.

Resources belonging to another observed workload are classified as RESOURCE_EXTERNAL.

An external resource is not automatically a conflict.

Qualified examples from the current workstation:

```text
5432 -> RESOURCE_EXPECTED -> core-platform-postgres
8080 -> RESOURCE_EXPECTED -> core-platform-keycloak
9200 -> RESOURCE_EXPECTED -> core-platform-opensearch

6379 -> RESOURCE_EXTERNAL -> core-poc-redis
9000 -> RESOURCE_EXTERNAL -> core-poc-minio
```

The qualified real-state result is:

```text
CBS_ISOLATION_CONFLICTS=0
CBS_ISOLATION_RESULT=PASS
```

## Conflict classification

The logical ownership contract is qualified independently:

```text
expected owner == observed owner -> RESOURCE_EXPECTED
expected owner != observed owner -> RESOURCE_CONFLICT
missing expected or observed owner -> RESOURCE_UNKNOWN
```

This behavior is validated through synthetic tests and does not mutate Docker.

Automatic conflict discovery from stack or instance specifications is not implemented in B17b-B.

## Workstation Manager

The Workstation Manager orchestrates the prerequisite and isolation checkers without duplicating their logic.

Qualified aggregate behavior:

```text
Prerequisites PASS + Isolation PASS -> READY -> RC 0
Prerequisites FAIL -> INCOMPLETE -> RC 10
Isolation conflict -> CONFLICT -> RC 20
Unexpected checker result -> UNKNOWN -> RC 30
Missing context -> RC 64
```

On the qualified workstation:

```text
CBS_WORKSTATION_PREREQUISITE_RC=0
CBS_WORKSTATION_ISOLATION_RC=0
CBS_WORKSTATION_STATE=READY
CBS_WORKSTATION_RESULT=PASS
```

## CLI

The qualified CLI command is:

```text
cbs workstation check <context-file>
```

Qualified Core Platform invocation:

```text
cbs workstation check config/contexts/core-platform.local.env
```

The command exposes detailed prerequisite and isolation observations followed by the aggregate workstation state.

## Qualification boundary

B17b-B does not implement:

```text
automatic prerequisite installation
workstation upgrade
workspace creation
repository creation or cloning
worktree management
stack resolution
instance management
automatic port allocation
runtime lifecycle
deployment
automatic conflict resolution
```

RESOURCE_CONFLICT is qualified as a classification contract.

Automatic conflict discovery from future stack and instance resource definitions is not implemented in B17b-B.

## Read-only guarantee

The qualified Workstation checks do not mutate:

```text
Git working tree state
Docker containers
Docker networks
Docker volumes
```

This behavior was verified by comparing workstation state before and after execution during qualification.
