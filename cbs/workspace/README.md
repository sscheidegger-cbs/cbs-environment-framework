# Workspace / Repository lifecycle

B17b-C implements the minimal CBS Workspace and Repository lifecycle layer.

Observation and mutation are separated. Incompatible existing states are blocked rather than corrected implicitly.

## Implemented components

```text
cbs/workspace/contract.sh
cbs/workspace/repository_contract.sh
cbs/workspace/workspace_observer.sh
cbs/workspace/workspace_manager.sh
cbs/workspace/repository_manager.sh
```

## Workspace contract

Qualified workspace states:

```text
READY
MISSING
INVALID
UNKNOWN
```

Qualified path classes:

```text
DIRECTORY
FILE
OTHER
ABSENT
```

Qualified return codes:

```text
0   success
40  missing workspace
41  invalid workspace
42  unknown workspace state
64  usage or missing argument
```

## Repository contract

Qualified repository states:

```text
READY
MISSING
NOT_GIT
REMOTE_MISMATCH
UNKNOWN
```

Qualified worktree observations:

```text
CLEAN
DIRTY
UNKNOWN
```

Qualified return codes:

```text
0   success
50  repository missing
51  target is not a Git repository
52  remote mismatch
53  unknown repository state
64  usage or missing argument
```

A dirty worktree is not by itself an invalid repository.
Repository validity and worktree cleanliness are separate observations.

## Workspace lifecycle

Qualified behavior:

```text
READY -> REUSE -> no mutation
MISSING -> CREATE -> only when direct parent exists
INVALID -> BLOCK
UNKNOWN -> BLOCK
```

The Workspace Manager does not recursively create missing parent directories.

Qualified real workspace:

```text
/home/sscheidegger/projects
```

Observed result:

```text
CBS_WORKSPACE_STATE=READY
CBS_WORKSPACE_ACTION=REUSE
REAL_WORKSPACE_MUTATION=NONE
```

## Repository lifecycle

Qualified behavior:

```text
READY -> REUSE -> no mutation
MISSING -> CLONE
NOT_GIT -> BLOCK -> existing content preserved
REMOTE_MISMATCH -> BLOCK -> existing remote preserved
UNKNOWN -> BLOCK
```

The Repository Manager does not overwrite an existing non-Git directory.
The Repository Manager does not rewrite an incompatible origin remote.

Clone behavior was qualified only against a temporary local Git repository created by the automated tests.

No additional Core Platform clone was performed during B17b-C qualification.

## Real Core Platform observation

Qualified repository:

```text
/home/sscheidegger/projects/core-platform
```

Qualified origin:

```text
git@gitlab.com:core3234722/core-platform.git
```

Observed qualification state:

```text
CBS_REPOSITORY_STATE=READY
CBS_REPOSITORY_WORKTREE_STATE=DIRTY
CBS_REPOSITORY_ACTION=REUSE
REAL_REPOSITORY_MUTATION=NONE
```

A DIRTY worktree does not invalidate a repository whose Git identity and expected origin are coherent.

During real repository ensure qualification, HEAD, Git status and origin remained unchanged.

## Read-only observer

Qualified command:

```text
cbs workspace check <workspace-path> <repository-path> <origin>
```

The command observes Workspace and Repository state without mutation.

## CLI

Qualified lifecycle commands:

```text
cbs workspace ensure <workspace-path>
cbs repository ensure <repository-path> <origin>
```

The CLI exposes only behavior already qualified by the Workspace and Repository managers.

## Safety principles

```text
observe before mutate
validate before reuse
fail explicitly on incompatible existing state
reuse when already compliant
no hidden Git correction
no destructive cleanup
```

B17b-C performs no checkout, reset, clean, remote rewrite or worktree manipulation.

## Qualification boundary

B17b-C does not implement:

```text
worktree lifecycle
branch creation
branch checkout
Git reset
Git clean
remote repair
recursive workspace hierarchy creation
stack resolution
instance lifecycle
port allocation
Docker runtime lifecycle
deployment
release management
```

Worktree lifecycle belongs to B17b-D.

## Qualification result

The functional qualification validated contracts, observation, mutation gates, managers, CLI integration, B17b-A/B non-regression and real Workspace/Repository reuse.

```text
B17b-C_STEP_7_RESULT=PASS
B17b-C_STEP_7_SYNTAX=PASS
B17b-C_STEP_7_TESTS=PASS
B17b-C_STEP_7_NON_REGRESSION=PASS
B17b-C_STEP_7_REAL_WORKSPACE=PASS
B17b-C_STEP_7_REAL_REPOSITORY=PASS
B17b-C_STEP_7_CHANGESET_SCOPE=PASS
```
