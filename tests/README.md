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

The tests cover only capabilities implemented in B17b-A.

Workspace, repository lifecycle, worktrees, stacks, instances, runtime, deployment and infrastructure management are not covered because they are not implemented yet.

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
