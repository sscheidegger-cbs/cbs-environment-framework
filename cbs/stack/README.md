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

## D01b-B transverse Stack resource model

D01b-B extends the B17b-E Stack layer with a generic resource-classification
contract and Managed Toolchain lifecycle.

The historical B17b-E behavior remains valid and preserved.

### Canonical Stack resource types

The Stack resource contract defines:

```text
SYSTEM_PREREQUISITE
MANAGED_TOOLCHAIN
PROJECT_DEPENDENCY
RUNTIME_COMPONENT
PLATFORM_CAPABILITY
```

The generic Stack resolver classifies declared resources without requiring a
technology-specific list in the resolver.

Historical declarations map as follows:

```text
CBS_STACK_PREREQUISITE_*
-> SYSTEM_PREREQUISITE

CBS_STACK_COMPONENT_*
-> RUNTIME_COMPONENT

CBS_STACK_MANIFEST_CAPABILITY_*
-> PLATFORM_CAPABILITY
```

Managed Toolchains use explicit declarations such as:

```text
CBS_STACK_MANAGED_TOOLCHAIN_IDS=FLUTTER
CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_REQUIREMENT=REQUIRED
CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_VERSION=3.47.6
CBS_STACK_MANAGED_TOOLCHAIN_FLUTTER_PROVIDER=flutter
```

Project dependencies can also be declared generically through
`CBS_STACK_PROJECT_DEPENDENCY_IDS` and associated per-resource fields.

### Stack command semantics

The existing Stack commands remain read-only:

```text
cbs stack resolve <manifest>
cbs stack prerequisites <manifest>
```

Managed Toolchain mutation is explicit and separate:

```text
cbs stack toolchains ensure <manifest>
```

`stack resolve` never installs a toolchain.

`stack prerequisites` never installs a workstation prerequisite.

`stack toolchains ensure` is the explicit mutation surface for Managed
Toolchains.

### Managed Toolchain evaluation

The read-only Stack Toolchain evaluator maps declared Managed Toolchains to
the generic Toolchain Manager and exposes:

```text
resource id
requirement
version
provider
installation state
resolved path
decision
mutation state
```

Typical compatible result:

```text
PRESENT_COMPATIBLE
REUSE
MUTATION=NONE
```

### Managed Toolchain ensure

The Stack Toolchain manager delegates mutation to the generic Toolchain
Manager.

The generic lifecycle distinguishes:

```text
MISSING             -> INSTALL
PRESENT_COMPATIBLE  -> REUSE
PRESENT_INCOMPATIBLE -> RECONCILE
INVALID             -> BLOCK
UNKNOWN             -> BLOCK
```

`RECONCILE` is currently intentionally bounded. Automatic reconciliation is
not implemented and returns `RECONCILE_NOT_IMPLEMENTED` without invoking a
provider mutation.

### Provider boundary

Technology-specific behavior remains outside the generic Stack engine.

Provider contract version 1 exposes:

```text
DETECT
ENSURE
VERIFY
```

Provider `RESOLVE` is intentionally not part of contract version 1.
Resolution remains a Toolchain Manager responsibility based on provider
detection output, including the resolved physical path.

### Flutter reference Stack

The first real Stack using this model is:

```text
stacks/flutter/stack.env
```

It declares Flutter 3.47.6 as a required Managed Toolchain using the Flutter
provider.

Dart is verified as part of the Flutter distribution and is not modeled as a
separate Managed Toolchain in D01b-B.

The qualified CBS-managed physical layout is:

```text
~/.cbs/toolchains/flutter/<version>
```

The version is part of the path, so the model does not impose one global
Flutter version.

### D01b-B qualification boundary

D01b-B qualifies the generic Stack classification and Managed Toolchain
lifecycle with Flutter as the first real provider.

It does not qualify automatic reconciliation, generic project dependency
installation, runtime component lifecycle, or multi-stack genericity across
two heterogeneous real consumers.
