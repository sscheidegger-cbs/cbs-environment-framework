# Stack

B17b-E implements the minimal CBS stack definition, resolution and prerequisite-evaluation layer.

The implementation is read-only with respect to workstation and runtime state.

It does not install prerequisites, start services or mutate a platform repository.

## Implemented components

```text
cbs/stack/contract.sh
cbs/stack/stack_resolver.sh
cbs/stack/stack_prerequisite_evaluator.sh
```

## Stack contract

Contract version:

```text
CBS_STACK_CONTRACT_VERSION=1
```

Qualified stack states:

```text
READY
INCOMPLETE
INVALID
UNKNOWN
```

Qualified prerequisite observation states:

```text
PRESENT
MISSING
UNKNOWN
```

Qualified component requirements:

```text
REQUIRED
OPTIONAL
DISABLED
```

Qualified capabilities:

```text
start
check
status
qualify
```

The contract is source-idempotent.

## Stack manifest

A stack manifest declares:

```text
stack identity
stack version
required workstation prerequisites
required platform components
available platform capabilities
```

The manifest describes requirements.

It does not prove that a component is running and does not install a missing component.

## Stack Resolver

The resolver:

```text
validates the manifest
reads stack identity and version
resolves prerequisite requirements
resolves component requirements
resolves declared capabilities
```

The resolver is read-only.

A structurally valid manifest produces:

```text
CBS_STACK_STATE=READY
CBS_STACK_RESOLUTION_RESULT=PASS
```

At resolver level, READY means that the manifest is valid and resolvable.

It does not prove workstation readiness or runtime health.

## Stack prerequisite evaluator

The prerequisite evaluator combines:

```text
the resolved stack manifest
the qualified CBS Workstation prerequisite checker
```

Only prerequisites marked REQUIRED by the selected stack contribute to the aggregate stack prerequisite state.

The evaluator does not duplicate workstation prerequisite detection and does not install missing prerequisites.

The qualified Core Platform stack currently requires:

```text
GIT
UV
DOCKER
DOCKER_COMPOSE
PYTHON_312
```

On the qualified workstation:

```text
CBS_STACK_PREREQUISITE_REQUIRED_COUNT=5
CBS_STACK_PREREQUISITE_FAILURE_COUNT=0
CBS_STACK_STATE=READY
CBS_STACK_PREREQUISITE_EVALUATION_RESULT=PASS
```

## CLI

Qualified commands:

```text
cbs stack resolve <manifest>
cbs stack prerequisites <manifest>
```

Both commands are read-only.

## Relationship with Workstation

B17b-B owns generic workstation prerequisite observation.

B17b-E owns stack-specific selection and aggregation of those observations.

This separation prevents stack definitions from reimplementing machine inspection logic.

## Safety principles

```text
manifest describes requirements
resolver does not mutate
prerequisite evaluator does not install
workstation checker remains the source of machine observations
only REQUIRED manifest prerequisites block stack readiness
runtime state is not inferred from manifest resolution
```

## Qualification boundary

B17b-E does not qualify:

```text
automatic prerequisite installation
automatic prerequisite upgrade
package-manager mutation
Docker image installation or pull policy
runtime start
runtime stop
runtime restart
runtime health
port allocation
Docker network allocation
volume allocation
instance lifecycle
deployment
release management
```

Those behaviors must not be inferred from a stack state of READY.

## Qualification result

```text
B17b-E_STEP_7_RESULT=PASS
B17b-E_STEP_7_SYNTAX=PASS
B17b-E_STEP_7_TESTS=PASS
B17b-E_STEP_7_STACK_RESOLUTION=PASS
B17b-E_STEP_7_PREREQUISITES=PASS
B17b-E_STEP_7_STACK_STATE=READY
B17b-E_STEP_7_READ_ONLY=PASS
B17b-E_STEP_7_NON_REGRESSION=PASS
B17b-E_STEP_7_CHANGESET_SCOPE=PASS
```
