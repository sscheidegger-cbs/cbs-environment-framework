# Local Instance

## Scope

This document describes the Instance contract and implementation qualified by B17b-F.

B17b-F implements the minimal CBS local-instance observation and safe-reuse layer for the Core Platform topology that existed at that qualification point.

The historical B17b-F manifest remains preserved as qualification evidence and must not be interpreted as a complete description of the later Core Platform post-K runtime topology.

The current Instance v1 implementation can observe:

- 6 named containers;
- 1 named network;
- 1 external volume.

Core Platform post-K uses a richer persistent-resource model with multiple generation-based volumes. That complete topology cannot currently be represented by Instance v1 without evolving the contract and observer.

Such an evolution is outside D01b-A.

The qualified implementation does not create an independent instance, start or stop runtime services, or modify Docker resources.

## Implemented components

```text
cbs/instance/contract.sh
cbs/instance/instance_observer.sh
cbs/instance/instance_manager.sh
instances/core-platform/instance.env
```

## Instance contract

Contract version:

```text
CBS_INSTANCE_CONTRACT_VERSION=1
```

Qualified instance states:

```text
READY
STOPPED
PARTIAL
CONFLICT
INVALID
UNKNOWN
```

Qualified resource types:

```text
CONTAINER
NETWORK
VOLUME
PORT
```

Qualified resource states:

```text
AVAILABLE
EXPECTED
CONFLICT
UNKNOWN
```

Qualified decisions:

```text
REUSE
CREATE
BLOCK
OBSERVE
```

CREATE is part of the contract vocabulary but is not implemented by B17b-F.

## Instance observer

The observer reads the local-instance manifest and compares the declared resources with the current Docker state.

The qualified Core Platform manifest currently describes:

```text
6 containers
1 network
1 external volume
```

For each resource, the observer emits its type, name and classified resource state.

The observer is read-only.

It does not start, stop, create, remove or modify Docker resources.

## Qualified real state

The qualified observation returned:

```text
CBS_INSTANCE_EXPECTED_RESOURCE_COUNT=8
CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT=0
CBS_INSTANCE_CONFLICT_RESOURCE_COUNT=0
CBS_INSTANCE_STATE=READY
CBS_INSTANCE_ACTION=REUSE
CBS_INSTANCE_OBSERVATION_RESULT=PASS
```

In B17b-F, READY means that all resources declared by the current instance manifest were found as expected.

READY does not mean that every container is running or healthy.

Runtime health is not qualified by B17b-F.

## Mutation gate

The qualified decision policy is:

```text
READY -> REUSE
STOPPED -> REUSE
PARTIAL -> OBSERVE
CONFLICT -> BLOCK
INVALID -> BLOCK
UNKNOWN -> OBSERVE
```

The mutation gate is decision-only and performs no mutation.

## Instance manager

The minimal instance manager applies the mutation decision to the observed instance state.

For the qualified Core Platform local instance, the result is:

```text
CBS_INSTANCE_MANAGER_STATE_BEFORE=READY
CBS_INSTANCE_MANAGER_ACTION=REUSE
CBS_INSTANCE_MANAGER_MUTATION=NONE
CBS_INSTANCE_MANAGER_RESULT=PASS
```

The manager therefore qualifies safe reuse of the existing instance.

It does not implement creation of an independent local instance.

## CLI

Qualified commands:

```text
cbs instance check <manifest>
cbs instance ensure <manifest>
```

`instance check` invokes the read-only instance observer.

`instance ensure` invokes the minimal instance manager.

For the currently qualified Core Platform instance, both operations preserve the existing runtime resources.

```text
REAL_INSTANCE_STATE=READY
REAL_INSTANCE_ACTION=REUSE
REAL_INSTANCE_MUTATION=NONE
```

## Core Platform constraints

The current Core Platform local instance has the following qualified constraints:

```text
FIXED_CONTAINER_NAMES
FIXED_NETWORK_NAME
FIXED_EXTERNAL_VOLUME
FIXED_HOST_PORTS
```

The current manifest therefore describes the existing local Core Platform instance; it does not define an isolated multi-instance topology.

## Safety principles

```text
observation before mutation
READY -> REUSE
STOPPED -> REUSE
PARTIAL -> OBSERVE
CONFLICT -> BLOCK
INVALID -> BLOCK
UNKNOWN -> OBSERVE
```

B17b-F never infers runtime health from resource presence.

## Qualification boundary

B17b-F does not qualify:

```text
independent instance creation
multi-instance coexistence
dynamic container naming
dynamic network allocation
dynamic volume allocation
dynamic port allocation
runtime start
runtime stop
runtime restart
runtime health
service health aggregation
container health aggregation
deployment
release management
```

Qualified boundary:

```text
MULTI_INSTANCE_COEXISTENCE=NOT_QUALIFIED
INSTANCE_CREATE=NOT_IMPLEMENTED
RUNTIME_HEALTH=NOT_QUALIFIED
```

## Qualification result

```text
B17b-F_STEP_8_RESULT=PASS
B17b-F_STEP_8_SYNTAX=PASS
B17b-F_STEP_8_TESTS=PASS
B17b-F_STEP_8_REAL_STATE=READY
B17b-F_STEP_8_REAL_ACTION=REUSE
B17b-F_STEP_8_REAL_MUTATION=NONE
B17b-F_STEP_8_CONSTRAINTS=PASS
B17b-F_STEP_8_MULTI_INSTANCE=NOT_QUALIFIED
B17b-F_STEP_8_RUNTIME_HEALTH=NOT_QUALIFIED
B17b-F_STEP_8_READ_ONLY=PASS
B17b-F_STEP_8_NON_REGRESSION=PASS
B17b-F_STEP_8_CHANGESET_SCOPE=PASS
```
