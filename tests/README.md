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
