# Context Manager

The Context Manager implemented in B17b-A distinguishes configured project context from observed Git state.

## Implemented components

```text
cbs/context/context.sh
cbs/context/git_observer.sh
config/contexts/core-platform.local.env
```

## Context contract

Context format version 1 requires exactly these keys:

```text
CBS_CONTEXT_VERSION
CBS_CONTEXT_CLIENT
CBS_CONTEXT_ENTITY_TYPE
CBS_CONTEXT_ENTITY_NAME
CBS_CONTEXT_REPOSITORY_PATH
CBS_CONTEXT_BRANCH
CBS_CONTEXT_ENVIRONMENT
```

Qualified Core Platform example:

```text
CBS_CONTEXT_VERSION=1
CBS_CONTEXT_CLIENT=ourea
CBS_CONTEXT_ENTITY_TYPE=platform
CBS_CONTEXT_ENTITY_NAME=core-platform
CBS_CONTEXT_REPOSITORY_PATH=/home/sscheidegger/projects/core-platform
CBS_CONTEXT_BRANCH=main
CBS_CONTEXT_ENVIRONMENT=LOCAL
```

The versioned Core Platform context tracks the current canonical Core branch `main`.

Historical B17b-A qualification was originally performed on `fix/b06-keycloak-kong-e2e`. That historical qualification evidence is preserved in B17b-A and is not rewritten by this current configuration.

## Context parser

The context file is parsed as data and is not blindly sourced as a shell script.

The parser rejects:

- missing context file;
- malformed lines;
- unknown keys;
- duplicate keys;
- empty values;
- missing required keys;
- unsupported context versions;
- invalid entity types;
- invalid environment values.

Supported entity types:

```text
platform
project
```

Supported environment values:

```text
LOCAL
TEST
PREPROD
PROD
```

## Git observation

The Git observer reads the repository declared by the context and observes:

- repository root;
- current branch;
- HEAD commit SHA.

The observed HEAD is dynamic and is deliberately not stored in the context file.

## Drift detection

The current implementation compares configured and observed values for:

- repository path;
- branch.

It exposes:

```text
CBS_CONTEXT_DRIFT
CBS_CONTEXT_DRIFT_REPOSITORY_PATH
CBS_CONTEXT_DRIFT_BRANCH
```

CBS_CONTEXT_DRIFT=NO means the configured repository path and branch match the state actually observed by Git.

## Current limits

B17b-A does not yet implement workspace discovery, repository lifecycle, worktree management, stack resolution, instance management, runtime lifecycle, deployment, secrets management or GitLab/GitHub repository management.
