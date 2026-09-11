# Tests

Tests for the CBS Environment Framework.

## B17b-A Entry Point

Executable test:

```text
tests/test_entrypoint.sh
```

The test currently validates only implemented behavior:

- help;
- help aliases;
- invocation without arguments;
- version;
- version alias;
- unknown command rejection;
- expected return codes;
- absence of unimplemented commands from the advertised interface.

Context, stacks, runtime, instances and deployment are not tested because they are not implemented yet.
