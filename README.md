# CBS Environment Framework

## Status

CBS Environment Framework is an active transverse CBS engineering framework.

The framework was implemented and qualified incrementally during B17, with
Core Platform as the first reference platform.

Capabilities already implemented and qualified on their documented B17 scopes include:

- command-line entry point and context management;
- Git context observation and drift detection;
- workstation prerequisite and isolation checks;
- workspace and repository lifecycle;
- worktree lifecycle;
- minimal stack resolution and prerequisite evaluation;
- platform resolution and platform hook execution;
- Core Platform LOCAL binding and qualification orchestration;
- Core Platform LOCAL multi-instance isolation.

Some capabilities remain partial or intentionally deferred.

In particular:

- generic instance creation is not complete;
- multi-client operation has not yet been qualified;
- multi-stack genericity has not yet been demonstrated with two qualified heterogeneous platforms;
- generic release, deployment, policy, authorization, secret, audit and remote-environment capabilities are not qualified as framework-wide capabilities.

Core Platform remains the first qualified reference implementation. Its qualification does not prove that all target CBS capabilities are already generic or complete.

## Responsibilities

This repository hosts reusable CBS engineering capabilities used to prepare,
resolve, orchestrate and qualify development environments and progressively
other execution environments.

It also owns reusable technical stack definitions when their generic and
reusable nature has been demonstrated.

## Ownership boundary

CBS owns reusable engineering framework capabilities.

Platform repositories remain owners of:

- application code;
- business logic;
- platform-specific configuration;
- runtime implementation;
- platform hooks;
- functional tests;
- platform qualification evidence.

The CBS Environment Framework orchestrates platform capabilities but does not
replace platform-owned runtime logic or tests.

## Main areas

- `bin/` - command-line entry points.
- `cbs/context/` - context loading, validation and observation.
- `cbs/workstation/` - workstation prerequisites and isolation.
- `cbs/workspace/` - workspace and repository lifecycle.
- `cbs/worktree/` - worktree observation and lifecycle.
- `cbs/stack/` - stack resolution and prerequisite evaluation.
- `cbs/instance/` - instance observation and lifecycle support.
- `cbs/platform/` - platform resolution and hook execution.
- `stacks/` - reusable stack definitions.
- `bindings/` - platform/project integration contracts where applicable.
- `tests/` - framework tests.
- `docs/` - framework documentation.

## Qualification status

Qualification is incremental and scoped.

Implemented, tested, qualified and generic are distinct states.

Core Platform LOCAL currently provides the strongest reference qualification.
The next major genericity proof is expected from a second heterogeneous
platform/stack rather than from adding further Core-specific behavior.

## Documentation authority

Git is authoritative for executable commands, scripts, manifests and tests.
Notion contains architecture, methodology, decisions and historical B17 evidence.

Historical B17 pages remain historical evidence and must not be rewritten as if
they originated from the later transverse CBS documentation structure.

## Source control

For the B17 framework repository, the qualified operational publication chain is:

local Git -> GitLab authoritative write repository -> GitLab push mirror -> GitHub read-only mirror

Owners, namespaces and repository URLs used during B17 are operational historical
values and must not be treated as permanent CBS institutional invariants.

## Version

The current development version is stored in `VERSION`.

The repository is still in development and must not be interpreted as a fully
qualified multi-client, multi-platform, multi-environment CBS product solely
from the capabilities already demonstrated with Core Platform.

## D01b-B Stack resources and Managed Toolchains

D01b-B extends the historical B17 Stack baseline without rewriting or
invalidating its qualification evidence.

The Stack layer now classifies declared resources using the following
transverse resource types:

```text
SYSTEM_PREREQUISITE
MANAGED_TOOLCHAIN
PROJECT_DEPENDENCY
RUNTIME_COMPONENT
PLATFORM_CAPABILITY
```

The generic Stack resolver discovers declared resources without maintaining a
hardcoded list of technologies.

### Managed Toolchains

A Managed Toolchain is a reusable, versioned development toolchain whose
physical installation can be managed by CBS independently from a consumer
project repository.

The current Managed Toolchain lifecycle separates read-only observation from
explicit mutation:

```text
DECLARE
RESOLVE
OBSERVE
CLASSIFY
REUSE or INSTALL
VERIFY
```

Existing Stack commands remain read-only:

```text
cbs stack resolve <manifest>
cbs stack prerequisites <manifest>
```

Toolchain mutation is exposed separately and explicitly:

```text
cbs stack toolchains ensure <manifest>
```

The Managed Toolchain manager classifies observed installations as:

```text
MISSING
PRESENT_COMPATIBLE
PRESENT_INCOMPATIBLE
INVALID
UNKNOWN
```

and derives one of the following decisions:

```text
REUSE
INSTALL
RECONCILE
BLOCK
```

`RECONCILE` is currently an explicit bounded state. Automatic reconciliation
of an incompatible installed version is not implemented and returns
`RECONCILE_NOT_IMPLEMENTED`.

### Provider boundary

Technology-specific behavior is isolated behind the Managed Toolchain provider
boundary.

Provider contract version 1 exposes:

```text
DETECT
ENSURE
VERIFY
```

`resolve` remains a Toolchain Manager operation; it is not a provider
operation. Provider detection supplies the observed installation state and
resolved physical path required by manager resolution.

The generic Stack and Toolchain engines contain no Flutter- or Dart-specific
branching.

### Flutter reference provider

Flutter is the first real Managed Toolchain provider used to qualify the
D01b-B architecture.

The qualified Stack declaration currently requests:

```text
Flutter 3.47.6
```

Dart is treated as bundled with the Flutter distribution rather than as a
separate Managed Toolchain.

Managed Flutter installations use a versioned physical layout:

```text
~/.cbs/toolchains/flutter/<version>
```

This permits deterministic resolution and supports coexistence of distinct
toolchain versions without relying on the workstation global `PATH`.

The resolved path is exposed explicitly to the consumer boundary. Full
project-scoped executable injection into a real consumer project remains part
of the subsequent consumer qualification rather than being inferred from
D01b-B.

### Qualification boundary

D01b-B qualifies:

```text
generic Stack resource classification
generic Managed Toolchain declarations
read-only toolchain resolution and observation
explicit ensure mutation
versioned physical installation paths
compatible installation reuse
post-ensure verification
controlled provider failures
explicit incompatible-version reconciliation boundary
Flutter provider installation and reuse
Flutter with bundled Dart verification
preservation of the historical Core Stack behavior
portable framework non-regression
```

D01b-B does not by itself prove:

```text
multi-stack genericity across two heterogeneous qualified consumers
automatic incompatible-version reconciliation
generic project dependency installation
generic runtime component lifecycle
generic platform capability lifecycle
remote toolchain lifecycle
release or deployment orchestration
```

The next consumer qualification is expected to exercise these transverse
capabilities from a real project rather than extend the generic engine with
consumer-specific behavior.
