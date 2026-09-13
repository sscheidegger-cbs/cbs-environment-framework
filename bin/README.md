# bin

Command-line entry points for the CBS Environment Framework.

## Implemented in B17b-A

The current executable entry point is:

```text
bin/cbs
```

Implemented commands:

```text
cbs
cbs help
cbs --help
cbs -h
cbs version
cbs --version
cbs status <context-file>
```

## Help

An invocation without arguments displays help.

The following commands are equivalent:

```text
cbs
cbs help
cbs --help
cbs -h
```

## Version

```text
cbs version
cbs --version
```

The version command reads the repository VERSION file.

## Status

```text
cbs status <context-file>
```

The status command loads and validates the supplied context file, observes the declared Git repository and displays configured and observed state.

Current output includes:

```text
CBS_CONTEXT_CLIENT
CBS_CONTEXT_ENTITY_TYPE
CBS_CONTEXT_ENTITY_NAME
CBS_CONTEXT_ENVIRONMENT
CBS_CONTEXT_REPOSITORY_PATH
CBS_OBSERVED_REPOSITORY_PATH
CBS_CONTEXT_BRANCH
CBS_OBSERVED_BRANCH
CBS_OBSERVED_HEAD
CBS_CONTEXT_DRIFT
CBS_CONTEXT_DRIFT_REPOSITORY_PATH
CBS_CONTEXT_DRIFT_BRANCH
```

A missing context argument is rejected with exit code 2.

## Current limits

Runtime lifecycle, independent instance creation and deployment management are not implemented yet.

## Workstation

Qualified command:

```text
cbs workstation check <context-file>
```

The command:

- validates workstation prerequisites;
- observes Docker isolation state for the supplied context;
- aggregates the result through the Workstation Manager;
- does not install, start, stop, remove or reconfigure workstation resources.

Qualified aggregate states:

```text
READY
INCOMPLETE
CONFLICT
UNKNOWN
```

For the qualified Core Platform context:

```text
cbs workstation check config/contexts/core-platform.local.env
```

The observed qualified state is READY with return code 0.

## Workspace / Repository

Qualified commands:

```text
cbs workspace check <workspace-path> <repository-path> <origin>
cbs workspace ensure <workspace-path>
cbs repository ensure <repository-path> <origin>
```

Qualified lifecycle behavior:

```text
Workspace READY -> REUSE
Workspace MISSING -> CREATE if direct parent exists
Workspace INVALID -> BLOCK

Repository READY -> REUSE
Repository MISSING -> CLONE
Repository NOT_GIT -> BLOCK
Repository REMOTE_MISMATCH -> BLOCK
```

The workspace check command is read-only.

The ensure commands do not perform implicit checkout, reset, clean, remote repair or worktree manipulation.

For the qualified Core Platform repository, repository ensure performs REUSE and preserves the existing dirty worktree.

## Worktree

Qualified commands:

```text
cbs worktree check <repository-path>
cbs worktree ensure <repository-path> <worktree-path> <branch>
```

Qualified behavior:

```text
READY -> REUSE
MISSING -> CREATE
BRANCH_CONFLICT -> BLOCK
PATH_CONFLICT -> BLOCK
INVALID_REPOSITORY -> BLOCK
UNKNOWN -> BLOCK
```

The check command is read-only.

The ensure command does not perform implicit reset, clean, branch deletion or worktree deletion.

B17b-D qualifies Git worktree coexistence for develop, release and hotfix.

It does not qualify runtime instance coexistence.

## Stack

Qualified commands:

```text
cbs stack resolve <manifest>
cbs stack prerequisites <manifest>
```

Qualified behavior:

```text
resolve -> validate and expose stack requirements and capabilities
prerequisites -> evaluate REQUIRED manifest prerequisites against workstation observations
```

Both commands are read-only.

The Stack CLI does not install or upgrade prerequisites and does not start runtime components.

## Instance

Qualified commands:

```text
cbs instance check <manifest>
cbs instance ensure <manifest>
```

Qualified real behavior for the current Core Platform local instance:

```text
REAL_INSTANCE_STATE=READY
REAL_INSTANCE_ACTION=REUSE
REAL_INSTANCE_MUTATION=NONE
```

`instance check` performs read-only resource observation.

`instance ensure` currently qualifies safe reuse of the existing instance.

It does not create an independent instance and does not start, stop, restart, remove or reconfigure Docker resources.

In B17b-F, READY means that all resources declared by the instance manifest were found as expected.

READY does not qualify runtime or container health.

## Platform

Qualified commands:

```text
cbs platform resolve <manifest>
cbs platform start <manifest>
cbs platform check <manifest>
cbs platform status <manifest>
cbs platform stop <manifest>
cbs platform qualify <manifest>
```

The Core Platform LOCAL binding delegates these actions to the existing Core lifecycle scripts.

Independent instance creation, multi-instance runtime coexistence, remote deployment and release management are not qualified by B17b-G.
