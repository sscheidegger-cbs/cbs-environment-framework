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

No workspace, repository lifecycle, worktree, stack, instance, runtime or deployment management command is implemented yet.
