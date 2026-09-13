# Worktree lifecycle

B17b-D implements the minimal CBS Git worktree lifecycle layer.

The implementation manages Git worktrees only. It does not create, start or qualify runtime instances.

## Implemented components

```text
cbs/worktree/contract.sh
cbs/worktree/worktree_observer.sh
cbs/worktree/worktree_manager.sh
```

## Worktree contract

Qualified states:

```text
READY
MISSING
BRANCH_CONFLICT
PATH_CONFLICT
INVALID_REPOSITORY
UNKNOWN
```

Qualified actions:

```text
READY -> REUSE
MISSING -> CREATE
BRANCH_CONFLICT -> BLOCK
PATH_CONFLICT -> BLOCK
INVALID_REPOSITORY -> BLOCK
UNKNOWN -> BLOCK
```

Qualified branch observations:

```text
ATTACHED
DETACHED
ABSENT
UNKNOWN
```

## Observer

The observer is read-only.

It reports:

```text
worktree path
branch attachment state
branch name or DETACHED
HEAD
worktree CLEAN or DIRTY state
worktree count
```

The real Core Platform observation qualified three existing worktrees:

```text
/home/sscheidegger/projects/core-platform
/home/sscheidegger/projects/b17-step13-3-fresh-worktree
/home/sscheidegger/projects/b17-step13-clean-worktree
```

Observed classification:

```text
1 ATTACHED worktree
2 DETACHED worktrees
3 DIRTY worktrees
```

No Core worktree mutation was performed.

## Worktree Manager

The manager qualifies and implements:

```text
CREATE of a missing worktree when the branch exists and the parent path exists
REUSE of an already compliant worktree
BLOCK when the requested branch is already materialized elsewhere
BLOCK when the requested path is incompatible
BLOCK when the repository is invalid
BLOCK when the requested branch does not exist
```

The manager does not recursively create missing parent directories.

The manager performs no implicit reset, clean, checkout correction, branch deletion or worktree deletion.

## Coexistence qualification

B17b-D qualified simultaneous Git worktree coexistence for:

```text
develop
release
hotfix
```

The qualification fixture contained four worktrees in total:

```text
primary repository worktree
develop
release
hotfix
```

This proves Git worktree coexistence only.

It does not prove multi-instance runtime isolation.

## CLI

Qualified commands:

```text
cbs worktree check <repository-path>
cbs worktree ensure <repository-path> <worktree-path> <branch>
```

The check command is read-only.

The ensure command exposes only CREATE, REUSE and BLOCK behavior already qualified by the Worktree Manager.

## Safety principles

```text
observe before mutate
validate repository before worktree operation
one branch -> one active worktree
reuse when already compliant
fail explicitly on path or branch conflict
no hidden reset or clean
no implicit deletion
```

## Qualification boundary

B17b-D does not qualify:

```text
runtime instance lifecycle
ports
Docker networks
volumes
runtime configuration
secrets
multi-instance runtime coexistence
stack resolution
deployment
release management
```

Runtime instance lifecycle belongs to the later B17b Local Instance unit.

## Qualification result

```text
B17b-D_STEP_8_1_RESULT=PASS
B17b-D_STEP_8_1_SYNTAX=PASS
B17b-D_STEP_8_1_TESTS=PASS
B17b-D_STEP_8_1_REAL_CORE=PASS
B17b-D_STEP_8_1_NON_REGRESSION=PASS
B17b-D_STEP_8_1_CHANGESET_SCOPE=PASS
```
