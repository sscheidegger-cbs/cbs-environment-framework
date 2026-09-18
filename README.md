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
