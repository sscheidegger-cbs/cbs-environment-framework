# CBS Platform Binding

The Platform layer binds CBS lifecycle actions to hooks implemented by a concrete platform repository.

## Components

- `contract.sh`: states, actions and return codes.
- `platform_resolver.sh`: repository and hook resolution.
- `platform_hook_runner.sh`: hook execution and return-code propagation.

## Qualified actions

`resolve`, `start`, `check`, `status`, `stop` and `qualify`.

`resolve` is read-only. `start` and `stop` are mutative lifecycle actions delegated to the bound platform.

## Runtime and Instance boundary

The Instance layer observes declared resource existence and coherence.
The Platform layer executes runtime lifecycle and health operations.
An instance can therefore remain `READY / REUSE` while its existing containers are stopped.

## B17b-G qualification boundary

Qualified: Core Platform LOCAL binding, hook validation, return-code propagation and the nominal resolve/status/check/qualify/stop/start lifecycle.

Not qualified or not implemented: multi-instance runtime coexistence, independent instance creation, dynamic runtime resource allocation, remote deployment and release management.
