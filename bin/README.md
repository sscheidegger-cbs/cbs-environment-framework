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
```

Behavior:

- an invocation without arguments displays help;
- help aliases return the same help;
- version reads the repository `VERSION` file;
- an unknown command returns exit code `2`;
- a missing or empty `VERSION` file returns exit code `3`.

No context, setup, runtime, stack, instance or deployment command is implemented yet.
