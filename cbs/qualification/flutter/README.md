# CBS Flutter/iOS Qualification Contract

Generic contract for the local qualification of a Flutter application on an
iOS simulator, inside a Git checkout isolated by CBS.

**Status: contract and hermetic tests only (D04b-C.2b, step 1).** There is no
executor yet. Nothing in this directory runs Flutter, Dart, Xcode, `simctl`,
Git or SSH, creates a worktree, or writes a file. The contract is independent
of any business application.

## Components

- `contract.sh`: constants, pure validators and structured-output helpers.
  It is sourced (it reads nothing else than the isolation contract of this
  repository, at a fixed path derived from its own location) and defines
  functions only.

Not part of this step: the fixed-action executor, the evidence collector, any
CLI entry (`bin/cbs` is unchanged), any SSH transport (`cbs/remote/` is
unchanged), any change to the worktree isolation (`cbs/worktree/` is
unchanged).

## Reuse

- Identifier, commit and URL-credential rules come from
  `cbs/worktree/isolation_contract.sh` (D04b-C.1): a qualification identifier
  and an isolation identifier are valid exactly when the isolation contract
  says so.
- Only an isolation created and verified by the CBS isolation manager may be
  used by a future executor. This contract does not create, verify or remove
  anything.

## Contract version

`CBS_FLUTTER_QUAL_CONTRACT_VERSION=1`. A request carrying another version is
refused (`CONTRACT_VERSION_UNSUPPORTED`).

## Operations and actions

| Operation   | Action      | Mutating | Meaning                                      |
|-------------|-------------|----------|----------------------------------------------|
| `PREFLIGHT` | `preflight` | no       | observe checkout, toolchain, simulator       |
| `ANALYZE`   | `analyze`   | yes      | static analysis                              |
| `TEST`      | `test`      | yes      | declared test selection                      |
| `BUILD_IOS` | `build_ios` | yes      | unsigned simulator build, no archive         |
| `REPORT`    | `report`    | no       | structured summary of every selected step    |

"Mutating" means: may write into the isolated checkout (`.dart_tool/`,
`build/`, `ios/Flutter/`, caches). It never means: may touch the source
repository.

Action names are lowercase and closed. Anything else (`PREFLIGHT`, `run`,
`flutter`, `analyze;id`, ...) is refused with `ACTION_NOT_ALLOWED`. An action
takes no argument: its arguments are fixed by the contract, never supplied by
a caller; an extra word is refused with `ARGUMENT_REFUSED`.

The list of selected actions is comma-separated, without duplicate, in the
canonical order above. A mutating action requires `preflight` to be selected,
first. `report` may be selected alone.

A mutating operation may start only after a `PREFLIGHT` whose result is exactly
`PASS` (`cbs_flutter_qual_gate_allows`). `REPORT` is always allowed, so that a
refusal can be documented.

## Results

| Result    | Meaning                                                     |
|-----------|-------------------------------------------------------------|
| `PASS`    | executed, observed outcome is a success                     |
| `FAIL`    | executed, observed outcome is a failure                     |
| `BLOCKED` | refused before execution: a precondition or a rule was not met |
| `SKIPPED` | explicitly not selected by the request                      |
| `NOT_RUN` | selected but never executed, hence never observed           |

`SKIPPED` and `NOT_RUN` are never a success and never convert into `PASS`.
`SKIPPED` is an operation-level result only.

Overall result (`cbs_flutter_qual_aggregate`): `FAIL`, then `BLOCKED`, then
`NOT_RUN` take precedence over `PASS`. When nothing passed (only `SKIPPED`),
the overall result is `NOT_RUN`.

## Reasons and return codes

Codes `120..137` are reserved for this contract and collide with no code used
by another CBS component. `64` is the shared usage code.

| Reason                         | RC  | Result  |
|--------------------------------|-----|---------|
| `USAGE`                        | 64  | BLOCKED |
| `CONTRACT_VERSION_UNSUPPORTED` | 120 | BLOCKED |
| `INPUT_INVALID`                | 121 | BLOCKED |
| `ACTION_NOT_ALLOWED`           | 122 | BLOCKED |
| `ARGUMENT_REFUSED`             | 123 | BLOCKED |
| `PATH_NOT_ALLOWED`             | 124 | BLOCKED |
| `SECRET_REFUSED`               | 125 | BLOCKED |
| `ISOLATION_REJECTED`           | 126 | BLOCKED |
| `TOOL_UNAVAILABLE`             | 127 | BLOCKED |
| `TOOLCHAIN_INCOMPATIBLE`       | 128 | BLOCKED |
| `SIMULATOR_UNAVAILABLE`        | 129 | BLOCKED |
| `COMMAND_FAILED`               | 130 | FAIL    |
| `TIMEOUT`                      | 131 | FAIL    |
| `NETWORK_FAILURE`              | 132 | FAIL    |
| `LOG_LIMIT_EXCEEDED`           | 133 | FAIL    |
| `EVIDENCE_FAILURE`             | 134 | FAIL    |
| `NOT_EXECUTED`                 | 135 | NOT_RUN |
| `PREFLIGHT_NOT_PASSED`         | 136 | NOT_RUN |
| `NOT_SELECTED`                 | 137 | SKIPPED |

`126` to `129`, `130` to `134` and `135` to `137` are declared for the future
executor; this step only validates their form and their result class.

A `PASS` carries no reason (code `0`). Any other result carries a reason of its
own class (`cbs_flutter_qual_result_reason_consistent`).

The exact exit status of an executed tool (for example `flutter analyze`) is
never replaced by a contract code: it is reported separately, as
`CBS_FLUTTER_QUAL_OPERATION_TOOL_RC`, only for `PASS` (must be `0`) and `FAIL`.

## Structured output

Only values taken from closed sets are ever printed: an operation, a result, a
reason, a numeric code. A free text supplied by a caller is never emitted.

```text
CBS_FLUTTER_QUAL_OPERATION=<OPERATION>
CBS_FLUTTER_QUAL_OPERATION_RESULT=<RESULT>
CBS_FLUTTER_QUAL_OPERATION_REASON=<REASON>      (not for PASS)
CBS_FLUTTER_QUAL_OPERATION_RC=<contract code>
CBS_FLUTTER_QUAL_OPERATION_TOOL_RC=<tool status> (PASS or FAIL, if known)

CBS_FLUTTER_QUAL_REASON=<REASON>                 (not for PASS)
CBS_FLUTTER_QUAL_CONTRACT_VERSION=1
CBS_FLUTTER_QUAL_RESULT=<RESULT>                 (always the last stdout line)
```

An inconsistent emission (unknown operation, result without matching reason,
tool status on a blocked operation, ...) prints nothing on stdout and fails
with `64`.

## Request

A request is a list of `KEY=VALUE` entries. It is **data**: it is never
sourced, evaluated, expanded or used to build a command.

A word that is not a `KEY=VALUE` entry with a well-formed key (`--flag`, a
command, a path, `--dart-define=...`) is an arbitrary argument and is refused
with `ARGUMENT_REFUSED`. A key that is not listed below is refused with
`ARGUMENT_REFUSED`, or with `SECRET_REFUSED` when its name looks sensitive
(`token`, `secret`, `passw*`, `credential`, `api_key`, `private_key`, `auth*`,
`dart_define*`). A duplicate key is refused (no later entry overrides an earlier
one). There is no default: every required key must be present.

Required keys:

| Key                  | Rule                                                         |
|----------------------|--------------------------------------------------------------|
| `contract_version`   | `1`                                                          |
| `qualification_id`   | isolation identifier rule (1..64, `[A-Za-z0-9._-]`, no `.lock`) |
| `isolation_id`       | same rule                                                    |
| `source_repository`  | authorized path (below)                                      |
| `expected_origin`    | `[A-Za-z0-9._~:/@+%-]`, at most 1024, no credential          |
| `commit`             | full lowercase object name, 40 or 64 hexadecimal digits      |
| `isolation_root`     | authorized path                                              |
| `evidence_root`      | authorized path                                              |
| `target`             | `ios-simulator` only                                         |
| `actions`            | see "Operations and actions"                                 |
| `timeout_seconds`    | `1..3600`, no leading zero                                   |
| `log_max_bytes`      | `1024..104857600`, no leading zero                           |
| `evidence_retention` | `keep` only (evidence is never deleted by a qualification)   |
| `cleanup_policy`     | `none` or `explicit`                                         |

Optional keys:

| Key                | Rule                                                            |
|--------------------|-----------------------------------------------------------------|
| `test_scope`       | `unit_widget` or `integration`; required when `test` is selected, refused otherwise |
| `test_targets`     | at most 16 relative files `test/**_test.dart` or `integration_test/**_test.dart`, matching the scope; no `..`, no space, no glob; refused when `test` is not selected |
| `simulator_udid`   | explicit UDID (`8-4-4-4-12` hexadecimal); aliases such as `booted` are refused; required for `integration` |
| `simulator_policy` | `existing_only` only: no simulator is created or booted implicitly |

The bounds are safety limits, not defaults. Their final values are an open
design decision.

## Authorized paths

`source_repository`, `isolation_root` and `evidence_root` are absolute and
checked lexically:

- characters `A-Za-z0-9._+@/-` only (no space, `~`, `$`, quote, glob or shell
  metacharacter, control character);
- no empty, `.` or `..` component, no trailing slash, at most 1024 characters;
- at least two components (`/` and `/tmp` are refused);
- no component named `.git`, `.local`, `.ssh`, `.gnupg`, `.aws`, `.kube`,
  `.docker`, `.netrc` or `.env` (any letter case);
- the three roots never equal or contain one another: the source repository is
  never a place to run or write, and the evidence outlives the checkout.

`cbs_flutter_qual_dir_is_canonical` (read-only) additionally checks that an
existing directory contains no symbolic link in any component. On macOS `/tmp`
and `/var` are symbolic links: a caller canonicalizes first (`cd -P`, `pwd -P`)
and gives the physical path.

## Secrets

- A secret is never accepted as a parameter, whichever key carries it
  (`SECRET_REFUSED`), and a refused value is never printed or recorded: only a
  closed reason and a well-formed key name are kept
  (`CBS_FLUTTER_QUAL_VALIDATION_REASON`, `CBS_FLUTTER_QUAL_VALIDATION_KEY`).
- A repository origin carrying credentials (`scheme://user@host`,
  `scheme://user:secret@host`) is refused; `git@host:path` is accepted.
- `cbs_flutter_qual_redact` / `cbs_flutter_qual_redact_stream` replace, with
  `[REDACTED]`: private key blocks, credentials in URLs, Bearer tokens,
  `--dart-define` and `--dart-define-from-file` values, GitHub, AWS access key,
  Slack and GitLab token formats, and the value of any `KEY=VALUE` or
  `KEY: VALUE` whose key contains a sensitive word. Redaction is idempotent and
  uses a portable `sed` subset.
- Redaction is line-based and best effort: it guarantees the listed patterns,
  not the absence of any secret in free text, and it favors over-redaction (for
  example `token_test.dart: 3 tests` loses its `3`). A future executor must
  still avoid secret scenarios in the initial qualification and must pass every
  log through redaction before writing it.

## Rules imposed on the future executor

These rules are part of the contract; they are not implemented in this step.

- Run only in the checkout created and verified by the CBS isolation manager,
  and revalidate it before every operation. Never run on the source repository.
- No arbitrary shell, no `eval`, no `source` of a request or manifest; fixed
  actions only; Flutter options fixed by the contract and confirmed on a real
  toolchain before freezing.
- Never call `ENSURE` of a toolchain, never install or start anything. Never
  create or boot a simulator implicitly.
- No `git clean -fdx`, `git reset --hard`, forced or unbounded deletion, no
  effect on `.local/`, secrets or untracked files of the source repository.
- Timeout and log size limit on every action; logs and evidence in a dedicated
  location, kept after a failure, redacted before being written.
- A `PREFLIGHT` that is not `PASS` forbids every mutating operation.
- Do not extend `cbs remote` or its allow-list: SSH transport is a separate,
  later decision (D04b-C.3).

## Open decisions (not frozen)

Test selection strategy beyond `test_scope` / `test_targets`; exact Flutter
command options; simulator management; cache locations; final timeout and log
bounds; durable evidence storage.

## Tests

```bash
bash tests/test_flutter_qualification_contract.sh
bash tests/test_flutter_qualification_security.sh
bash tests/test_flutter_qualification_portability.sh
```

The tests are hermetic: forbidden-tool shims (`flutter`, `dart`, `xcrun`,
`xcodebuild`, `simctl`, `git`, `ssh`, `scp`, `curl`, `wget`, `open`) are placed
first in `PATH` and must remain uncalled. They run on Linux and are meant to run
on macOS with `/bin/bash` 3.2; the portability test reports separately whether a
native Bash 3.2 was available (`NOT_RUN` otherwise). Qualification on a real Mac
and with a real toolchain is a later step (D04b-C.2c) and is not claimed here.
