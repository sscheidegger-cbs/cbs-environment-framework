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
