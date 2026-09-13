# Instances

Versioned local-instance definitions for the CBS Environment Framework.

The instance layer describes concrete local runtime-resource identities and the constraints required to observe and safely reuse them.

## Core Platform

Qualified B17b-F manifest:

```text
instances/core-platform/instance.env
```

Detailed documentation:

```text
instances/core-platform/README.md
```

Qualified identity:

```text
CBS_INSTANCE_ID=core-platform-local
CBS_INSTANCE_VERSION=1
CBS_INSTANCE_STACK_ID=core-platform
```

Qualified real state:

```text
STATE=READY
ACTION=REUSE
MUTATION=NONE
```

The current definition describes the existing Core Platform local instance.

It does not define or create an independent second instance.

## Current constraints

```text
FIXED_CONTAINER_NAMES
FIXED_NETWORK_NAME
FIXED_EXTERNAL_VOLUME
FIXED_HOST_PORTS
```

## Qualification boundary

```text
MULTI_INSTANCE_COEXISTENCE=NOT_QUALIFIED
INSTANCE_CREATE=NOT_IMPLEMENTED
RUNTIME_HEALTH=NOT_QUALIFIED
```

READY means that the resources declared by the instance manifest were found as expected.

READY does not qualify runtime or container health.

Future instance definitions must not be assumed isolated until container names, networks, volumes and host ports have been explicitly qualified.
