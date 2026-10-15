# Tests

Tests for the CBS Environment Framework.

## B17b-A test suite

Current executable tests:

```text
tests/test_entrypoint.sh
tests/test_context.sh
tests/test_git_observer.sh
tests/test_status.sh
```

## Entry Point

test_entrypoint.sh validates:

- help;
- help aliases;
- invocation without arguments;
- version;
- version alias;
- unknown command rejection;
- expected return codes;
- absence of unimplemented commands from the advertised interface.

## Context parser

test_context.sh validates:

- reading the qualified Core Platform context;
- required context values;
- context validation;
- rejection of an unknown key;
- propagation of parser errors.

## Git observer

test_git_observer.sh validates:

- repository observation;
- branch observation;
- HEAD observation;
- absence of drift for the qualified context;
- detection of an intentionally introduced branch drift.

## Status command

test_status.sh validates:

- context exposure through cbs status;
- observed Git state;
- absence of drift for the qualified Core Platform context;
- observed HEAD format;
- rejection of a missing context argument.

## Current qualification boundary

This section describes the B17b-A test boundary. Additional qualified test suites for B17b-B and subsequent units are documented below.

## B17b-B Workstation test suite

Qualified executable tests:

```text
tests/test_workstation_contract.sh
tests/test_prerequisite_checker.sh
tests/test_isolation_checker.sh
tests/test_isolation_conflict.sh
tests/test_workstation_manager.sh
tests/test_workstation_cli.sh
```

### Workstation contract

Validates:

- contract version;
- return codes;
- prerequisite states;
- resource classifications;
- aggregate workstation states.

### Prerequisite Checker

Validates the currently qualified prerequisites:

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

The real workstation qualification currently returns PASS with zero required failures.

### Isolation Checker

Validates:

- expected resource classification;
- external resource classification;
- context-aware Docker observation;
- ownership of published ports;
- absence of historical false port conflicts;
- real isolation result on the qualified workstation.

### Conflict classification

test_isolation_conflict.sh validates the logical ownership contract:

```text
same owner -> RESOURCE_EXPECTED
different owner -> RESOURCE_CONFLICT
missing owner -> RESOURCE_UNKNOWN
```

This is a synthetic contract test and does not mutate Docker.

### Workstation Manager

Validates aggregate states:

```text
READY
INCOMPLETE
CONFLICT
UNKNOWN
```

It also validates missing-context behavior.

### Workstation CLI

Validates:

- help exposure;
- cbs workstation check <context-file>;
- real READY state;
- missing context;
- unknown workstation subcommand.

### Qualification boundary

The B17b-B tests do not qualify automatic prerequisite installation, workspace/repository/worktree management, stack resolution, instance management, automatic port allocation, runtime lifecycle or deployment.

Automatic conflict discovery from future stack or instance specifications is not implemented in B17b-B.

## B17b-C Workspace / Repository test suite

Qualified executable tests:

```text
tests/test_workspace_contract.sh
tests/test_repository_contract.sh
tests/test_workspace_observer.sh
tests/test_repository_mutation_gate.sh
tests/test_repository_manager.sh
tests/test_workspace_manager.sh
tests/test_workspace_cli.sh
```

### Workspace contract

Validates path classification, Workspace states and return codes.

### Repository contract

Validates repository states, worktree cleanliness observation and return codes.

A DIRTY worktree is explicitly validated as non-blocking when repository identity and origin remain coherent.

### Workspace observer

Validates read-only observation of the real Workspace and Core Platform repository.

### Repository mutation gate

Validates the policy:

```text
MISSING -> candidate for CLONE
NOT_GIT -> BLOCK
REMOTE_MISMATCH -> BLOCK
READY -> REUSE
```

### Repository Manager

Validates:

- clone of a missing repository using a temporary local Git source;
- reuse of a compliant repository;
- blocking of a non-Git target;
- blocking of remote mismatch;
- preservation of incompatible existing state.

### Workspace Manager

Validates:

- creation of a missing Workspace when its direct parent exists;
- reuse of an existing Workspace;
- blocking of invalid targets;
- absence of recursive parent creation.

### Workspace / Repository CLI

Validates:

- cbs workspace check <workspace-path> <repository-path> <origin>;
- cbs workspace ensure <workspace-path>;
- cbs repository ensure <repository-path> <origin>;
- unknown Workspace and Repository subcommands.

### Real-state qualification

The real Workspace / Core Platform qualification validates:

```text
CBS_WORKSPACE_STATE=READY
CBS_REPOSITORY_STATE=READY
CBS_REPOSITORY_WORKTREE_STATE=DIRTY
REAL_WORKSPACE_MUTATION=NONE
REAL_REPOSITORY_MUTATION=NONE
```

### Qualification boundary

B17b-C tests do not qualify worktree lifecycle, branch creation, checkout, reset, clean, remote repair, stack resolution, instance lifecycle, Docker runtime lifecycle, deployment or release management.

Worktree lifecycle belongs to B17b-D.

## B17b-D Worktree test suite

Qualified executable tests:

```text
tests/test_worktree_contract.sh
tests/test_worktree_observer.sh
tests/test_worktree_mutation_gate.sh
tests/test_worktree_manager.sh
tests/test_worktree_coexistence.sh
tests/test_worktree_cli.sh
```

### Worktree contract

Validates Worktree states, branch attachment states, actions and return codes.

### Worktree observer

Validates read-only observation of the real Core Platform worktrees.

The qualified real observation contains:

```text
3 worktrees
1 ATTACHED worktree
2 DETACHED worktrees
3 DIRTY worktrees
```

### Mutation gate

Validates pure decision behavior for REUSE, CREATE and BLOCK cases.

### Worktree Manager

Validates CREATE, REUSE, branch conflict, path conflict, missing parent and missing branch behavior on a temporary Git fixture.

### Worktree coexistence

Validates simultaneous Git worktree coexistence for:

```text
develop
release
hotfix
```

The controlled fixture contains four worktrees in total, including the primary repository worktree.

### Worktree CLI

Validates:

```text
cbs worktree check <repository-path>
cbs worktree ensure <repository-path> <worktree-path> <branch>
```

### Qualification boundary

B17b-D does not qualify runtime instance lifecycle or multi-instance runtime isolation.

## B17b-E Stack test suite

Qualified executable tests:

```text
tests/test_stack_contract.sh
tests/test_core_platform_stack_manifest.sh
tests/test_stack_resolver.sh
tests/test_stack_prerequisite_evaluator.sh
tests/test_stack_cli.sh
```

### Stack contract

Validates contract version, stack states, prerequisite states, component requirements, capabilities, aggregation and return codes.

### Core Platform stack manifest

Validates the Core Platform stack identity, prerequisites, required components and declared capabilities.

### Stack Resolver

Validates manifest resolution, prerequisite/component exposure, capabilities, invalid manifest handling and read-only behavior.

### Stack prerequisite evaluator

Validates mapping of REQUIRED stack prerequisites to Workstation prerequisite observations.

The qualified workstation result is:

```text
CBS_STACK_PREREQUISITE_REQUIRED_COUNT=5
CBS_STACK_PREREQUISITE_FAILURE_COUNT=0
CBS_STACK_STATE=READY
CBS_STACK_PREREQUISITE_EVALUATION_RESULT=PASS
```

### Stack CLI

Validates:

```text
cbs stack resolve <manifest>
cbs stack prerequisites <manifest>
```

### Qualification boundary

B17b-E does not qualify automatic prerequisite installation, runtime lifecycle, local-instance lifecycle, deployment or release management.

## B17b-F Local Instance test suite

Qualified executable tests:

```text
tests/test_instance_contract.sh
tests/test_core_platform_instance_manifest.sh
tests/test_instance_observer.sh
tests/test_instance_mutation_gate.sh
tests/test_instance_manager.sh
tests/test_instance_cli.sh
```

### Instance contract

Validates:

```text
instance states
resource types
resource states
actions
state/action mapping
return codes
source idempotence
```

### Core Platform instance manifest

Validates:

```text
instance identity
6 declared containers
1 declared network
1 declared external volume
fixed-resource constraints
```

### Instance observer

Validates read-only observation and aggregation of the resources declared by the instance manifest.

The qualified real observation is:

```text
CBS_INSTANCE_EXPECTED_RESOURCE_COUNT=8
CBS_INSTANCE_AVAILABLE_RESOURCE_COUNT=0
CBS_INSTANCE_CONFLICT_RESOURCE_COUNT=0
CBS_INSTANCE_STATE=READY
CBS_INSTANCE_ACTION=REUSE
CBS_INSTANCE_OBSERVATION_RESULT=PASS
```

READY means that the resources declared by the manifest were found as expected.

It does not qualify container execution state or runtime health.

### Instance mutation gate

Validates the decision policy:

```text
READY -> REUSE
STOPPED -> REUSE
PARTIAL -> OBSERVE
CONFLICT -> BLOCK
INVALID -> BLOCK
UNKNOWN -> OBSERVE
```

The mutation gate performs no Docker mutation.

### Instance manager

Validates safe reuse of the existing qualified Core Platform local instance.

Qualified real result:

```text
CBS_INSTANCE_MANAGER_STATE_BEFORE=READY
CBS_INSTANCE_MANAGER_ACTION=REUSE
CBS_INSTANCE_MANAGER_MUTATION=NONE
CBS_INSTANCE_MANAGER_RESULT=PASS
```

### Instance CLI

Validates:

```text
cbs instance check <manifest>
cbs instance ensure <manifest>
unknown instance command rejection
missing manifest handling
help exposure
```

### Core Platform constraints

The qualification established:

```text
FIXED_CONTAINER_NAMES
FIXED_NETWORK_NAME
FIXED_EXTERNAL_VOLUME
FIXED_HOST_PORTS
```

### Qualification boundary

B17b-F does not qualify:

```text
independent instance creation
multi-instance runtime coexistence
dynamic resource allocation
runtime lifecycle
runtime health
deployment
release management
```

Qualified boundary:

```text
MULTI_INSTANCE_COEXISTENCE=NOT_QUALIFIED
INSTANCE_CREATE=NOT_IMPLEMENTED
RUNTIME_HEALTH=NOT_QUALIFIED
```

## B17b-G Platform Binding

Qualified tests:

```text
tests/test_platform_contract.sh
tests/test_core_platform_binding_manifest.sh
tests/test_platform_resolver.sh
tests/test_platform_hook_runner.sh
tests/test_platform_cli.sh
```

The real Core Platform LOCAL binding was also qualified through CBS for resolve, status, check, qualify, stop and start.

The canonical Core local regression completed 15/15 PASS.

Multi-instance runtime coexistence, independent instance creation, dynamic resource allocation, remote deployment and release management remain outside the B17b-G qualification boundary.

## Current portable non-regression boundary

`tests/run_portable_non_regression.sh` is the current portable
non-regression runner for the CBS Environment Framework.

It executes the framework tests that remain valid against the current
Core Platform baseline and explicitly excludes tests whose qualification
assertions depend on the historical B17 real-state environment.

The historical real-state tests currently excluded are:

```text
tests/test_instance_cli.sh
tests/test_instance_manager.sh
tests/test_instance_mutation_gate.sh
tests/test_isolation_checker.sh
tests/test_worktree_observer.sh
```

These tests are preserved as B17 qualification artifacts. Their exclusion
from the portable runner does not invalidate, rewrite, or replace the
historical B17 qualification evidence.

The portable runner does not assert that the historical real-state tests
pass against the current post-K Core Platform runtime.

Current qualified portable result:

```text
CBS_PORTABLE_NON_REGRESSION_VERSION=1
CBS_PORTABLE_TEST_PASS_COUNT=48
CBS_PORTABLE_TEST_FAIL_COUNT=0
CBS_HISTORICAL_REAL_STATE_TEST_COUNT=5
CBS_PORTABLE_NON_REGRESSION_RESULT=PASS
```

This boundary separates:

- portable framework non-regression against the current baseline;
- historical B17 qualification tests tied to the real state observed at
  their qualification point.

It does not introduce Instance v2 and does not modify the historical
B17b-F Instance manifest.

## D01b-B Stack / Managed Toolchain test suite

Qualified executable tests:

```text
tests/test_stack_resource_contract.sh
tests/test_stack_resource_resolution.sh
tests/test_stack_toolchain_evaluator.sh
tests/test_stack_toolchain_cli.sh
tests/test_toolchain_contract.sh
tests/test_toolchain_provider_contract.sh
tests/test_toolchain_manager.sh
tests/test_toolchain_ensure.sh
tests/test_toolchain_provider_failure.sh
tests/test_toolchain_reconcile.sh
tests/test_toolchain_fixture_provider.sh
tests/test_flutter_provider.sh
tests/test_flutter_toolchain_manager.sh
tests/test_flutter_stack_manifest.sh
```

### Stack resource classification

Validates the canonical resource classes:

```text
SYSTEM_PREREQUISITE
MANAGED_TOOLCHAIN
PROJECT_DEPENDENCY
RUNTIME_COMPONENT
PLATFORM_CAPABILITY
```

It also validates preservation of historical prerequisite, component and
capability outputs.

### Managed Toolchain lifecycle

Validates:

```text
MISSING -> INSTALL
PRESENT_COMPATIBLE -> REUSE
PRESENT_INCOMPATIBLE -> RECONCILE
INVALID -> BLOCK
UNKNOWN -> BLOCK
```

`resolve` remains read-only.

`ensure` is explicit, performs mutation only when required, and always verifies
the resulting installation before returning PASS.

Automatic RECONCILE is intentionally not implemented. The incompatible case
is explicitly tested and returns `RECONCILE_NOT_IMPLEMENTED` without provider
mutation.

### Provider contract

Provider contract version 1 validates the operations:

```text
DETECT
ENSURE
VERIFY
```

Provider `RESOLVE` is explicitly excluded from version 1.

Tests also validate unknown providers, provider failures, malformed successful
ENSURE results and unsupported provider operations.

### Flutter provider qualification

The Flutter tests validate:

```text
missing installation detection
hermetic installation
compatible installation detection
Flutter version verification
bundled Dart version verification
multi-version path model
Toolchain Manager integration
Stack manifest integration
reuse without mutation
```

Flutter 3.47.6 is also qualified through a real CBS-managed installation under:

```text
~/.cbs/toolchains/flutter/3.47.6
```

The real qualification demonstrated REUSE with `MUTATION=NONE` and successful
post-resolution verification.

### D01b-B qualification boundary

D01b-B does not qualify automatic incompatible-version reconciliation or
multi-stack genericity across two heterogeneous real consumers.

The historical B17 real-state tests remain preserved and excluded from the
portable runner exactly as before.

## D04b-B Remote orchestration test suite

Qualified executable tests:

```text
tests/test_remote_contract.sh
tests/test_remote_manifest.sh
tests/test_remote_transport.sh
tests/test_remote_check.sh
tests/test_remote_run.sh
tests/test_remote_cli.sh
```

Shared fixtures (not test entry points):

```text
tests/fixtures/remote/lib.sh
tests/fixtures/remote/bin/ssh
tests/fixtures/remote/git-status-fails/git
```

### Hermeticity

The suite uses no network, no real SSH and no real remote repository.

`tests/fixtures/remote/bin/ssh` is a simulated `ssh` placed first in `PATH`.
It validates the option contract of the caller (option terminator,
`BatchMode=yes`, `StrictHostKeyChecking=yes`), records what it received, then
either simulates a failure (unreachable host, refused host key, broken
connection, probe malfunction) or runs the received remote command line
locally through `/bin/sh -c`, as a remote login shell would.

Two per-invocation knobs let a test act between the two SSH sessions of
`cbs remote run`: `FAKE_SSH_HOOK_ON_CALL` / `FAKE_SSH_HOOK` run a shell text
just before the Nth session executes (a remote change after the first probe),
and `FAKE_SSH_MODE_ON_CALL` / `FAKE_SSH_CALL_MODE` change the simulated mode of
the Nth session only. The fixture CBS entrypoint can write a marker file kept
outside the repositories, which proves whether it was started.

The "remote host" is a directory of a temporary tree holding a real Git
repository, created with a hermetic Git configuration (no user or system
configuration). A second temporary repository plays the local reference. The
remote path contains a space on purpose.

Simulated Git is used where a Git failure must be provoked:
`tests/fixtures/remote/git-status-fails/git` fails `git status` and delegates
everything else to the real Git. Git absence on the remote host is simulated
with an empty `PATH`.

The temporary directories are removed on exit. Nothing under the real
workspace, `~/.ssh` or `~/.cbs` is read or written.

### Remote contract

Validates contract and manifest versions, structured results, commit
relations, return code uniqueness and non-collision with the Repository
contract codes, the explicit allow-list of CBS commands that may be bound to
an action (exact content compared entry by entry; no entry names an ensure,
start, stop or installation operation; refused: `stack toolchains ensure`,
`platform start|stop|check|status|qualify`, `runtime android ensure|start|stop`,
incomplete prefixes and misplaced words), the launcher verdict vocabulary,
unchanged existing return codes and result emission.

### Remote manifest

Validates a declarative manifest loader that parses and never sources:
valid and optional keys, resolved values, relative local path resolution,
unknown / duplicate / empty / indented / CRLF lines, missing keys,
unsupported version, malformed values (destination, port, timeout, identity
file, remote path, origin, branch, commit, entrypoint, action names), command
injection attempts in values and in action commands, commands outside the
allow-list (every entry accepted with arguments, mutating and platform-hook
commands refused), undeclared or command-less actions, refusal of an origin carrying a
password, and proof that manifest content is not executed.

### Remote transport

Validates POSIX quoting by round trip through `/bin/sh`, `bash`, `dash` and
`zsh` when installed, on hostile values (quotes, `$()`, backticks, `;`, `&&`,
pipes, redirections, globs, tilde, newlines, leading dashes, Unicode), absence
of single quotes in the fixed remote scripts, the SSH option contract, optional
port / timeout / identity options, and what the simulated `ssh` actually
receives.

It also validates the launcher: no mutating Git command in the script, every
observation and refusal reason present, a single `exec` preceded only by the
passing verdict line, execution of the launcher by every available remote
shell (pass, refusal on commit, refusal on dirty worktree, entrypoint not
started on refusal), the output filter (verdict consumed and reported, bytes
after the verdict forwarded unchanged and unable to forge a verdict, malformed
values ignored, no verdict) and the launch stream (ssh status preserved, 255
without verdict).

On the qualification host `zsh` is not installed, so the zsh round trip is
reported as skipped (`TEST_REMOTE_TRANSPORT_ZSH=SKIPPED_NOT_INSTALLED`).

### Remote check

Validates PASS (local-reference and pinned commit, symbolic-link path) and the
negative cases: host unavailable, refused host key, unknown destination, wrong
commit (`UNKNOWN_OBJECT`, `BEHIND`, `AHEAD`, `DIVERGED`, pinned mismatch),
unavailable local reference, wrong branch, detached `HEAD`, dirty repository
(untracked, modified, staged), failing `git status`, origin mismatch or absence,
masking of origin credentials, missing path, non-Git directory, file instead of
directory, subdirectory of a repository, remote Git absent, missing or
non-executable entrypoint, malfunctioning probe, local `ssh` absent, invalid
manifest and usage errors.

Every scenario also verifies that the remote repository (HEAD, branch, status,
stash list) is unchanged, and that dirty content was neither cleaned nor reset.

`check` is also verified to start nothing and never to send the launcher, and a
change made after a passing `check` (dirty worktree, branch, commit, origin) is
detected by the next `check`.

### Remote run

Validates execution of declared actions, working directory with a space,
argument fidelity, preservation of the remote return code, standard output and
standard error (including return codes 7 and 42), transport failure after
verification, refusal of undeclared or hostile action names before any network
access, and that nothing is executed when the repository is dirty, on the wrong
commit, branch or origin, when the host is unreachable or when the entrypoint
is missing.

It validates the revalidation done by the launcher in the second SSH session:
a remote change injected after the first probe (untracked, modified and staged
files, branch change, detached `HEAD`, new commit, commit moved backwards,
origin change, repository moved, entrypoint made non-executable or removed) is
refused as `BLOCKED` with the usual reason and return code, in exactly two SSH
sessions, with `CBS_REMOTE_ACTION_EXECUTION=START` absent, the fixture
entrypoint never started, its output never seen and the remote state exactly as
the change left it (no reset, clean, checkout or stash). It also validates a
change between a passing `cbs remote check` and `cbs remote run`, the absence of
any launch session after a refused probe, the impossibility for an action to
forge the verdict, and the diagnostics: preflight refusal versus action failure
versus ssh status 255 (action returning 255, broken connection with no verdict,
launch session without verdict).

### Remote CLI

Validates help exposure, routing of `cbs remote check` and `cbs remote run`,
return code propagation, unknown `remote` subcommands, usage errors,
non-regression of existing command routing, structural guarantees (no `eval`,
no sourcing of the manifest, no dynamic shell, no Git mutation or
synchronisation, no recursive deletion, `BatchMode=yes` enforced) and the
absence of hardcoded host address, user, secret material or versioned remote
manifest. It also verifies that a launcher refusal reaches the CLI with the
same result and return code, and that `stack toolchains ensure`,
`platform start`, `platform stop` and `runtime android ensure` cannot be bound
to an action (`MANIFEST_INVALID`, no SSH session).

### D04b-B qualification boundary

Qualified: the behavior of `cbs remote check` and `cbs remote run` against a
simulated SSH and temporary local Git repositories.

Not qualified by this suite: a real SSH connection, a real remote host, the
macOS login shell (zsh) and macOS `PATH` behavior, remote execution of a real
Flutter stack action, iOS build, and long-running remote actions.

The portable runner `tests/run_portable_non_regression.sh` picks the new tests
up automatically through its `tests/test_*.sh` glob.
