# CBS Environment Framework

## Status

Initial B17b-A skeleton.

No operational CBS capability is qualified yet.

## Responsibilities

This repository hosts the reusable CBS engineering framework used to prepare,
resolve, orchestrate and qualify development and deployment environments.

It also owns the reusable industrial definitions of technical stacks required
to reconstruct those environments consistently.

## Ownership boundary

CBS owns reusable engineering and stack infrastructure.

Platform repositories remain owners of application code, business logic,
platform-specific configuration, hooks, tests and qualification evidence.

An artifact must only move from a platform repository into this repository
after its generic and reusable nature has been demonstrated and qualified.

## Main areas

- `bin/` - command-line entry points.
- `cbs/` - framework implementation.
- `stacks/` - reusable stack definitions and compositions.
- `docker/` - reusable industrial Docker artifacts.
- `templates/` - reusable environment/configuration templates.
- `bindings/` - platform/project specializations.
- `tests/` - framework tests.
- `docs/` - framework documentation.

## Source control

GitLab is the operational Git remote for development.

GitHub may expose a synchronized read-only mirror used by ChatGPT and other
read-only consumers. Development does not depend on GitHub CLI or direct
GitHub write access.
