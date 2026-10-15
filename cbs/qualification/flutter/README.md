# CBS Flutter/iOS Qualification Contract

Generic contract for the local qualification of a Flutter application on an
iOS simulator, inside a Git checkout isolated by CBS.

**Status: contract, PREFLIGHT and ANALYZE (D04b-C.2b), plus the preparation of
local `path:` dependencies (D04b-C.2c, section "Local path dependencies"
below; implemented and tested on Linux, not qualified on macOS), and the
extraction of the common execution engine (D04b-C.2e step 1, `execution.sh`,
section "Common execution engine" below; implemented and tested on Linux, native
macOS qualification pending), and the operation `TEST` (D04b-C.2f, `test.sh`,
section "TEST" below; implemented and tested on Linux with shims only, never run
with a real Flutter toolchain, not qualified on macOS).** `contract.sh` is
independent of any business application and runs nothing. `preflight.sh`
(read-only), `analyze.sh` ("ANALYZE") and `test.sh` ("TEST") are the only
executors; `execution.sh` is a library, not an executor.
`BUILD_IOS` and `REPORT` are declared by the contract and are **not
implemented**. The `TEST` tests use shims only: no real Flutter, Dart, Xcode or
simulator has been run for `TEST`, and no native macOS run of `TEST` is claimed.

## Components

- `contract.sh`: constants, pure validators and structured-output helpers.
  It is sourced (it reads nothing else than the isolation contract of this
  repository, at a fixed path derived from its own location) and defines
  functions only.

- `preflight.sh`: read-only observation of the checkout, the toolchain and the
  simulator (operation `PREFLIGHT`). Unchanged by ANALYZE.
- `execution.sh`: the technical mechanisms common to the mutating operations
  (below, "Common execution engine"). Sourced, defines functions only. It
  sources `preflight.sh`, which sources `contract.sh`.
- `analyze.sh`: operation `ANALYZE` (below). It sources `execution.sh`.
- `test.sh`: operation `TEST` (below). It sources `execution.sh`.

Not part of these steps: `BUILD_IOS`, `REPORT`, any CLI entry (`bin/cbs`
is unchanged), any SSH transport (`cbs/remote/` is unchanged), any change to the
worktree isolation (`cbs/worktree/` is unchanged).

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

## ANALYZE

```bash
bash cbs/qualification/flutter/analyze.sh KEY=VALUE...
```

The arguments are the request of the contract (data only, same validation).
`actions` must contain `analyze` (otherwise `ACTION_NOT_ALLOWED`, which the
contract already requires to come after `preflight`).

Sequence, each step stopping the operation:

1. validate the request with `contract.sh`;
2. check the evidence location (below) before anything runs;
3. run `PREFLIGHT` on the same request; ANALYZE continues only when its result
   is exactly `PASS` (`cbs_flutter_qual_gate_allows`), otherwise
   `NOT_RUN` / `PREFLIGHT_NOT_PASSED` (136), nothing executed, nothing written.
   PREFLIGHT is what verifies, read-only, that the checkout
   `isolation_root/isolation_id` is owned by CBS (isolation manager `verify`),
   the exact commit and origin, a detached clean `HEAD`, and the toolchain;
4. check the checkout path again (`ISOLATION_REJECTED` if it is not a plain
   directory inside the isolation root) and find `flutter` in the absolute
   entries of `PATH` (`TOOL_UNAVAILABLE` if it vanished);
5. create the evidence directory and run `flutter analyze` once.

### The command

Exactly `flutter analyze`: the single argument is the constant
`CBS_FLUTTER_QUAL_ANALYZE_ARGUMENT`. No value of the request, of the checkout or
of the environment is part of the command; there is no `eval`, no `source` of
anything but the fixed files of this directory, no option (`--no-pub` and the
like are an open decision). The tool is run from the isolated checkout, never from the source
repository, with `LC_ALL=C` and its standard input closed.

### Bounds

- Timeout: `timeout_seconds`. A fixed supervisor runs the command in its own
  process group, then sends `TERM` and, 1 second later, `KILL` to that group.
  Output captured so far is kept.
- Output: redacted line by line (`cbs_flutter_qual_redact_stream`) **before** it
  is written, then capped at `log_max_bytes`. Exceeding the cap is
  `LOG_LIMIT_EXCEEDED` (133), whatever the tool status; the log keeps the first
  `log_max_bytes` bytes and `LOG_TRUNCATED=YES`.

### Results

| Result    | Reason                  | RC  | When |
|-----------|-------------------------|-----|------|
| `PASS`    | -                       | 0   | `flutter` exited with `0` (tool status `0`) |
| `FAIL`    | `COMMAND_FAILED`        | 130 | non-zero exit; the exact status is `OPERATION_TOOL_RC` |
| `FAIL`    | `TIMEOUT`               | 131 | `timeout_seconds` elapsed |
| `FAIL`    | `LOG_LIMIT_EXCEEDED`    | 133 | output over `log_max_bytes` |
| `FAIL`    | `EVIDENCE_FAILURE`      | 134 | the evidence could not be written |
| `BLOCKED` | `ACTION_NOT_ALLOWED` and the other request reasons | 120..125 | request refused |
| `BLOCKED` | `PATH_NOT_ALLOWED`      | 124 | evidence root not usable, or evidence already present |
| `BLOCKED` | `ISOLATION_REJECTED`    | 126 | checkout path not a plain directory in the isolation root |
| `BLOCKED` | `TOOL_UNAVAILABLE`      | 127 | `flutter` not found after PREFLIGHT |
| `NOT_RUN` | `PREFLIGHT_NOT_PASSED`  | 136 | PREFLIGHT result is not `PASS` |

`NETWORK_FAILURE` is never emitted: classifying it needs the real messages of
the tool, which are not frozen. A killed tool (status 137) is a `COMMAND_FAILED`
with that status; a status the executor cannot read is never reported as a
success.

### Output

The structured output of the contract, preceded by closed facts
(`CBS_FLUTTER_QUAL_ANALYZE_*`: `QUALIFICATION_ID`, `COMMIT_OBSERVED`,
`PREFLIGHT_RESULT`, `PREFLIGHT_REASON`, `FLUTTER_VERSION`, `COMMAND`,
`DURATION_SECONDS`, `LOG_BYTES`, `LOG_CRC`, `LOG_TRUNCATED`, `EVIDENCE`,
`REJECTED_KEY`). Every fact is checked against a closed pattern before it is
printed; tool output is never part of the answer. The last stdout line is
`CBS_FLUTTER_QUAL_RESULT=<RESULT>`. The exit status is the contract code of the
reason (`0` for `PASS`).

### Evidence

```text
<evidence_root>/<qualification_id>/ANALYZE.log      redacted, bounded output
<evidence_root>/<qualification_id>/ANALYZE.result   the structured answer
```

`evidence_root` must already exist (it is never created here), be a directory
owned by the user, not writable by group or others, and without symbolic link in
any component. The directory `<qualification_id>` is created (mode 700, no
`-p`) unless it already exists as a private directory of the same kind; files
are created with an exclusive create (mode 600). If `ANALYZE.log`,
`ANALYZE.result` or `ANALYZE.log.partial` already exists (a dangling link counts
as existing), the run is refused (`PATH_NOT_ALLOWED`): nothing is overwritten,
followed or deleted. The only file removed is the temporary capture
`ANALYZE.log.partial` of the same run. Evidence is never written in the
checkout or the source repository.

### Common execution engine

`execution.sh` (D04b-C.2e step 1) holds what does not depend on the operation,
moved out of `analyze.sh` without any change of behaviour: the request step,
the evidence location and its exclusive creation, the PREFLIGHT gate, the check
of the checkout path, the bounded execution (fixed supervisor and runner, process
groups, timeout, redaction, log bound), the classification of the outcome and
the structured answer. The file names and the fact names derive from the
operation (`<OPERATION>.log`, `CBS_FLUTTER_QUAL_<OPERATION>_*`).

The engine defines no command: the operation file looks the tool up and passes
the complete command line, constant text of that file. `analyze.sh` keeps the
selected action, the argument `analyze`, the lookup of `flutter` and the order
of the steps. The interface of ANALYZE (arguments, structured output, return
codes, evidence files) is unchanged. `TEST` and `BUILD_IOS` are not implemented
by this step; the supervisor and runner markers (`CBS_ANALYZE_*`) keep their
historical names for now.

### What ANALYZE does not control

- `flutter analyze` itself may write in the checkout (`.dart_tool/`,
  `pubspec.lock`, ...) and in the caches of the user (`HOME`, pub cache, Flutter
  SDK cache). The source repository is neither written nor read. A checkout
  dirtied by the tool is refused by the next PREFLIGHT (dirty tree): a new
  isolation is needed to run again.
- A process the tool detaches into another session or process group is outside
  the supervision of the timeout.
- With `KILL` (tool ignoring `TERM`) the tail of the output not yet read by the
  filter may be lost.
- The commit and origin are those PREFLIGHT verified; the content of the commit
  is trusted (analyzing code runs the build hooks of its packages).

## TEST

```bash
bash cbs/qualification/flutter/test.sh KEY=VALUE...
```

The arguments are the request of the contract (data only, same validation).
`actions` must contain `test` (otherwise `ACTION_NOT_ALLOWED`) and the request
carries `test_scope`. `test.sh` sources `execution.sh` and does not duplicate
it: validation, evidence location, PREFLIGHT gate, checkout check, supervision,
timeout, redaction, log bound, classification, structured answer and evidence
files are those of ANALYZE (above), with `TEST` as the operation (`TEST.log`,
`TEST.result`, facts `CBS_FLUTTER_QUAL_TEST_*`). The tool is looked up in the
absolute entries of `PATH`, run from the isolated checkout (never the source
repository), with `LC_ALL=C` and its standard input closed.

### The command

The words `test` and (integration only) `-d` are constants of `test.sh`. The
only values of the request that reach the command are the test files and, for
`integration`, the simulator identifier, as separate words of a command that is
never parsed by a shell. No Flutter option or argument is accepted from a
caller; secrets and `--dart-define` are refused by the contract.

| `test_scope`  | `test_targets` | Command |
|---------------|----------------|---------|
| `unit_widget` | absent         | `flutter test` |
| `unit_widget` | present        | `flutter test <file>...` (order of the request) |
| `integration` | present        | `flutter test <file>... -d <simulator_udid>` |
| `integration` | absent         | refused, see "Open decision" |

For `unit_widget`, a `simulator_udid` given in the request is not used.

Files are checked in the isolated checkout, before anything runs and without
writing: no component of the path is a symbolic link, the file exists and is a
regular file. A missing file is `INPUT_INVALID` (121); a symbolic link or a file
that is not regular is `PATH_NOT_ALLOWED` (124); the rejected key is
`test_targets`. Without `test_targets`, the `test` directory of the checkout
must not be, nor contain, a symbolic link (`PATH_NOT_ALLOWED`, key
`test_scope`); a missing `test` directory is left to `flutter`, which reports it
(`FAIL`).

### Open decision: `integration` without `test_targets`

`contract.sh` accepts `test_scope=integration` without `test_targets`, and it is
unchanged. No command that is both safe and explicit can be derived from such a
request: `flutter test` alone runs the `test` directory, not the integration
tests, and naming the `integration_test` directory would be a selection the
caller never validated. `TEST` therefore refuses that request on its own, before
PREFLIGHT: `BLOCKED`, `INPUT_INVALID` (121), key `test_targets`, nothing
executed, nothing written. Whether the contract should require `test_targets`
for `integration`, or define a default selection, is **not decided**.

### Simulator (integration)

`PREFLIGHT` must be `PASS` first. `TEST` then observes the requested simulator
again, read-only (`xcrun simctl list devices`, the observation of
`preflight.sh`), because `execution.sh` does not expose the state observed by
PREFLIGHT. The run starts only if the simulator is `BOOTED`. A `SHUTDOWN` or
transitional simulator, a simulator that vanished or a failed observation is
`BLOCKED` / `SIMULATOR_UNAVAILABLE` (129), key `simulator_udid`, nothing
executed. `TEST` never boots, creates, erases or deletes a simulator, and only
the explicit `simulator_udid` is used (no alias).

### Results

| Result    | Reason                  | RC  | When |
|-----------|-------------------------|-----|------|
| `PASS`    | -                       | 0   | `flutter` exited with `0` (tool status `0`) |
| `FAIL`    | `COMMAND_FAILED`        | 130 | non-zero exit; the exact status is `OPERATION_TOOL_RC` |
| `FAIL`    | `TIMEOUT`               | 131 | `timeout_seconds` elapsed |
| `FAIL`    | `LOG_LIMIT_EXCEEDED`    | 133 | output over `log_max_bytes` |
| `FAIL`    | `EVIDENCE_FAILURE`      | 134 | the evidence could not be written |
| `BLOCKED` | `INPUT_INVALID`         | 121 | request refused; test file absent; `integration` without `test_targets` |
| `BLOCKED` | request reasons         | 122..125 | request refused (`PATH_NOT_ALLOWED` also: link or irregular test file, evidence not usable or already present) |
| `BLOCKED` | `ISOLATION_REJECTED`    | 126 | checkout path not a plain directory in the isolation root |
| `BLOCKED` | `TOOL_UNAVAILABLE`      | 127 | `flutter` not found after PREFLIGHT |
| `BLOCKED` | `SIMULATOR_UNAVAILABLE` | 129 | `integration`: simulator not `BOOTED` |
| `NOT_RUN` | `PREFLIGHT_NOT_PASSED`  | 136 | PREFLIGHT result is not `PASS` |

`NETWORK_FAILURE` is never emitted. Evidence rules (location, exclusive
creation, modes, no overwrite, redaction, bound) are those of ANALYZE.

### What TEST does not control

- The same limits as ANALYZE (writes of `flutter` in the checkout and caches, a
  process detached from the process group, tail of the output lost on `KILL`).
  `flutter test` may dirty the checkout: the next PREFLIGHT refuses a dirty tree.
- The `-d <udid>` form is the constant chosen by this file; it has **not** been
  confirmed on a real toolchain, nor has the behaviour of `flutter test` on an
  integration test.
- The check of the test files and the observation of the simulator happen before
  the run: the checkout or the simulator may change in between (no atomicity).
- Test files ignored by Git and absent from the commit are not detected beyond
  the existence check in the checkout; only symbolic links, absence and
  non-regular files are refused.

## Rules imposed on the future executor

These rules are part of the contract. ANALYZE and TEST apply them for their own
operation; the other executors are not implemented.

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

Rule for `test_scope=integration` without `test_targets` (accepted by the
contract, refused by `TEST`, see "TEST"); test selection strategy beyond
`test_scope` / `test_targets`; exact Flutter command options (including for
`flutter analyze` and `flutter test`, and the form of the device option);
simulator management; cache
locations; final timeout and log bounds; durable evidence storage;
`NETWORK_FAILURE` classification.

## Tests

```bash
bash tests/test_flutter_qualification_contract.sh
bash tests/test_flutter_qualification_security.sh
bash tests/test_flutter_qualification_portability.sh
bash tests/test_flutter_qualification_preflight.sh
bash tests/test_flutter_qualification_preflight_security.sh
bash tests/test_flutter_qualification_analyze.sh
bash tests/test_flutter_qualification_analyze_security.sh
bash tests/test_flutter_qualification_analyze_portability.sh
bash tests/test_flutter_qualification_test.sh
bash tests/test_flutter_qualification_test_security.sh
bash tests/test_flutter_qualification_test_portability.sh
```

The contract tests are hermetic: forbidden-tool shims (`flutter`, `dart`,
`xcrun`, `xcodebuild`, `simctl`, `git`, `ssh`, `scp`, `curl`, `wget`, `open`) are
placed first in `PATH` and must remain uncalled. The PREFLIGHT, ANALYZE and TEST tests
use real Git repositories and real CBS isolations in a private directory, with
shims for Flutter, Dart, Xcode and `simctl` as the only such tools on `PATH`;
they run the suites sequentially (one at a time). They run on Linux and are meant to run
on macOS with `/bin/bash` 3.2; the portability test reports separately whether a
native Bash 3.2 was available (`NOT_RUN` otherwise). Qualification on a real Mac
and with a real toolchain is not claimed by these suites: it is the macOS step of
D04b-C.2c, documented below.

# Local path dependencies (D04b-C.2c)

```bash
bash cbs/qualification/flutter/dependencies.sh prepare <consumer-id> <consumer-source> <isolation-root> \
    <name> <source> <expected-origin> <commit> [<name> <source> <expected-origin> <commit>]...
bash cbs/qualification/flutter/dependencies.sh verify  (same arguments, read-only)
bash cbs/qualification/flutter/dependencies.sh cleanup <isolation-root> <name> <source> [<name> <source>]...
```

## The problem

A Flutter consumer may declare a local dependency with a relative path:

```yaml
cbs_flutter_ux:
  path: ../cbs-environment-framework/packages/cbs_flutter_ux
```

In a CBS isolation the checkout is `<isolation-root>/<consumer-id>`, so that path
resolves to `<isolation-root>/cbs-environment-framework/packages/cbs_flutter_ux`:
a sibling of the checkout, which does not exist. `flutter pub get`, and therefore
`flutter analyze`, cannot resolve the dependency.

History, kept as observed: a qualification of AMH-USR on macOS gave `PREFLIGHT=PASS`
then `ANALYZE=FAIL` with `COMMAND_FAILED` and a tool status of 66, in the isolation
`amh-usr-d04-analyze-01`. The cause established by the diagnosis is the path above.
That failure stays documented; it is not rewritten by this step.

## Design

- **Same mechanism as the consumer.** The sibling repository is materialized by the
  isolation manager of D04b-C.1 (unchanged): a detached worktree at an explicit
  commit, created directly at `<isolation-root>/<name>`, with its CBS ownership
  proof. `<name>` is the directory name that the relative path expects
  (`cbs-environment-framework` above): it is a valid isolation identifier. No
  symbolic link, no copy, no second mechanism. The relative path of the manifest is
  preserved as is: nothing is rewritten.
- **Nothing is guessed.** The consumer isolation is verified first (owned, exact
  commit and origin, detached, clean). The tracked `pubspec.yaml` of that checkout
  is read (data only: parsed, never evaluated) and its `path:` dependencies of
  `dependencies`, `dev_dependencies` and `dependency_overrides` are classified:
  inside the checkout (nothing to do, the directory must exist), under
  `<isolation-root>/<name>/...` (the repository `<name>` is needed), anything else
  (absolute path, path leaving the isolation root, unexpected character, form that
  cannot be read safely) is refused. A `path:` that belongs to a `git:` source is not a
  local path and is ignored.
- **Explicit mapping.** Each needed `<name>` requires one `<name> <source> <expected-origin> <commit>`
  group: the source repository, its origin and the full commit. A needed name without
  mapping is refused (`DEPENDENCY_UNMAPPED`); a mapping that nothing needs is refused
  (`MAPPING_UNUSED`): nothing unneeded is materialized. Before any creation, each
  source must hold a regular `pubspec.yaml` at the declared package path of the
  commit (`SOURCE_REJECTED` otherwise).
- **Provenance and cleanliness.** After materialization (and for `verify`), the
  manager verifies every resource again (proof, source, origin, exact commit,
  detached `HEAD`, clean worktree). The declared packages must be canonical
  directories (no symbolic link in any component) holding a plain `pubspec.yaml`,
  and the `path:` dependencies of those packages must stay inside the consumer
  checkout or inside a repository of this preparation (`PACKAGE_INVALID` otherwise;
  only one level is checked).
- **Idempotence.** Rerunning `prepare` with the same arguments gives `REUSED` for every
  resource and changes nothing. A resource already present is accepted only when
  the manager verifies it as CBS-owned, at the same commit and origin, detached and
  clean. Anything else already there (a directory without CBS proof, a symbolic
  link even dangling, another commit or origin, a modified worktree) is a conflict:
  `BLOCKED`, left exactly as found, detected before the first creation. An
  identifier already used by a previous (even cleaned) isolation of the root is a
  conflict too, as the isolation contract forbids reusing an identifier. After a
  partial failure (`MATERIALIZATION_FAILED`), the resources already created stay
  (owned, clean) and a rerun reuses them.

## Cleanup

`cleanup` verifies every requested resource first, read-only (owned by CBS, exact,
detached, clean): nothing is removed unless all of them pass (`CLEANUP_REFUSED`
otherwise). It then calls the isolation manager `cleanup`, one resource at a time
(non-forced `git worktree remove` of a worktree the manager created; the proof is
kept and a `.cleaned` record is written). A failure stops everything: no retry, no
sweep. A pre-existing directory, a symbolic link, an unknown identifier and a
modified worktree are refused and never touched. Order: clean the consumer isolation
first (`isolation_manager.sh cleanup`), then its dependencies. The identifier of a
cleaned dependency cannot be prepared again in the same isolation root: use a new
root for a new cycle.

## Results

Structured output (`CBS_FLUTTER_DEPS_*`, closed values only, no host path):
`VERSION`, `OPERATION`, `CONSUMER_ID`, `CONSUMER_COMMIT`, `EXTERNAL_COUNT`,
`INTERNAL_COUNT`, `DEPENDENCY_COUNT`, per resource `DEPENDENCY_<n>_NAME`, `_STATE`
(`CREATED`, `REUSED`, `PRESENT`, `MISSING`, `CONFLICT`, `REMOVED`, `NOT_RUN`),
`_COMMIT_EXPECTED`, `_COMMIT_OBSERVED`, `_PACKAGE`, then `REASON`, `DETAIL`, `RC` and,
last, `RESULT` (`PASS`, `FAIL`, `BLOCKED`). The reason is repeated on stderr.

| Reason                   | RC  | Result  | Meaning |
|--------------------------|-----|---------|---------|
| `USAGE`                  | 64  | BLOCKED | unknown command or wrong number of arguments |
| `INPUT_INVALID`          | 140 | BLOCKED | an argument is invalid (value never echoed) |
| `GIT_UNSUPPORTED`        | 141 | BLOCKED | Git older than 2.31 or ignoring `GIT_CONFIG_COUNT` |
| `CONSUMER_REJECTED`      | 142 | BLOCKED | consumer isolation not owned, not exact, not clean |
| `MANIFEST_UNSUPPORTED`   | 143 | BLOCKED | manifest not tracked or readable, form or path refused |
| `DEPENDENCY_UNMAPPED`    | 144 | BLOCKED | a needed repository has no mapping |
| `MAPPING_UNUSED`         | 145 | BLOCKED | a mapping is not needed by the manifest |
| `DEPENDENCY_CONFLICT`    | 146 | BLOCKED | something else is at the path, or not as requested |
| `DEPENDENCY_MISSING`     | 147 | BLOCKED | `verify`: a needed repository is not materialized |
| `SOURCE_REJECTED`        | 148 | BLOCKED | the commit or the package is not in the source |
| `CLEANUP_REFUSED`        | 149 | BLOCKED | a resource to clean is not owned, exact and clean |
| `PACKAGE_INVALID`        | 150 | FAIL    | package, nested path or resource check failed |
| `MATERIALIZATION_FAILED` | 151 | FAIL    | the isolation manager failed to create a resource |
| `CLEANUP_FAILED`         | 152 | FAIL    | the isolation manager failed to remove a resource |

`DETAIL` is a closed identifier (often the reason of the isolation manager, for
example `WORKTREE_DIRTY`). Codes 140..152 collide with no code of another CBS
component.

## Not covered, on purpose

- Only the root `pubspec.yaml` of the consumer is read (not nested manifests, not a
  Dart workspace); `flow-style` dependency sections and tab indentation are refused,
  not interpreted. Packages are checked one level deep.
- `prepare` does not run Flutter, Dart or `pub`, and does not touch the network. It is
  a separate step: PREFLIGHT and ANALYZE (unchanged) neither call it nor check that
  it ran. Run it between the creation of the isolation and PREFLIGHT.
- The isolation manager adds (and, at cleanup, removes) the Git administrative entry of
  each worktree in the source repository, as for the consumer isolation. Working
  tree, branches and untracked files of the sources are not touched (tested).
- `flutter analyze` may modify the consumer checkout (`pubspec.lock`, `.dart_tool/`)
  and refuses a dirty tree at the next PREFLIGHT (see "What ANALYZE does not
  control"). A dirty consumer checkout or dependency is refused by `cleanup`: the
  operator decides, nothing is forced.
- No real Flutter, Dart or Xcode has been run by these tests.

## Tests (Linux, hermetic)

```bash
bash tests/test_flutter_qualification_dependencies.sh
bash tests/test_flutter_qualification_dependencies_portability.sh
```

The first one uses temporary Git repositories and the real isolation manager in
temporary roots, no network, no user Git configuration, no Flutter. It covers usage,
refusals before any change, `prepare`, idempotence, `verify`, conflicts (commit,
origin, dirty worktree, directory without proof, symbolic link, dangling link,
burnt identifier), cleanup (all-or-nothing, preserved pre-existing data), several
repositories and partial failure, refused manifests, nested paths, the consumer
gate, arguments as data (secret, injection, traversal), and the structure of the
script (no link, no deletion, no network, no `eval`, one `source`). The second one
scans for Bash 4 and GNU-only constructs, runs the manifest reader under every
available `awk`, and runs the first one with a genuine Bash 3.2 when one exists
(`NOT_RUN` otherwise; `NATIVE_MACOS` is `PASS` only on Darwin).

## Qualification on macOS (D04b-C.2c: QUALIFIED)

Status vocabulary: IMPLEMENTED (code present), TESTED_LINUX (hermetic suites above),
TESTED_MACOS (the two suites above, run natively on a Mac) and QUALIFIED (real
PREFLIGHT and ANALYZE on the Mac, with the real toolchain, after preparation).
D04b-C.2c is QUALIFIED only when the sequence below was really executed and observed.

Commands (run on the Mac, from a checkout of this repository that contains
D04b-C.2c; the paths and the evidence root are the operator's choice and must exist):

```bash
# 0. Variables. Every path must be adapted to the Mac; none is assumed to exist.
CBS_FW="$HOME/projects/cbs-environment-framework"      # checkout holding D04b-C.2c
AMH_SRC="$HOME/projects/amh-usr"                        # source consumer, never modified
ISO_ROOT="$HOME/.cbs/isolations/amh-usr-d04"            # authorized isolation root
EVID_ROOT="${EVID_ROOT:?set the existing evidence root (mode 700)}"
CONSUMER_ID="amh-usr-d04-analyze-02"                    # a new identifier: never reuse one
QUAL_ID="amh-usr-d04-c2c-01"
AMH_COMMIT="bc0ad39d8be6b42a0109b7de18a6104b038f3f92"
FW_COMMIT="177ba996e02b7c58ba1c54aed9f965ba71db8ff2"    # holds packages/cbs_flutter_ux
AMH_ORIGIN="$(git -C "$AMH_SRC" remote get-url origin)"
FW_ORIGIN="$(git -C "$CBS_FW" remote get-url origin)"
printf '%s\n%s\n' "$AMH_ORIGIN" "$FW_ORIGIN"            # review before going on
cd "$CBS_FW" && git status --short --branch && git rev-parse HEAD

# Toolchain for non-interactive SSH sessions.
# The standard SSH PATH may not contain the CBS Flutter installation.
# Adapt the path to the actual Mac installation; do not install or modify
# the host configuration merely to satisfy this qualification.
export PATH="$HOME/.cbs/toolchains/flutter/3.47.6/bin:$PATH"
command -v flutter
command -v dart

# 1. Native tests of this step (Bash 3.2, BSD tools).
/bin/bash --version | head -n 1
/bin/bash tests/test_flutter_qualification_dependencies.sh
/bin/bash tests/test_flutter_qualification_dependencies_portability.sh   # expects NATIVE_MACOS=PASS
bash tests/run_portable_non_regression.sh

# 2. New isolation of the consumer (D04b-C.1, unchanged).
bash cbs/worktree/isolation_manager.sh create "$CONSUMER_ID" "$AMH_SRC" "$AMH_ORIGIN" "$AMH_COMMIT" "$ISO_ROOT"

# 3. Preparation, then read-only verification.
bash cbs/qualification/flutter/dependencies.sh prepare "$CONSUMER_ID" "$AMH_SRC" "$ISO_ROOT" \
    cbs-environment-framework "$CBS_FW" "$FW_ORIGIN" "$FW_COMMIT"
bash cbs/qualification/flutter/dependencies.sh verify "$CONSUMER_ID" "$AMH_SRC" "$ISO_ROOT" \
    cbs-environment-framework "$CBS_FW" "$FW_ORIGIN" "$FW_COMMIT"

# 4. PREFLIGHT then ANALYZE (unchanged executors). The timeout and the log bound
#    are examples inside the contract bounds; choose them. Add the optional keys of
#    the contract (simulator_udid=..., simulator_policy=existing_only) when the
#    qualification targets a given existing simulator.
REQ=(contract_version=1 "qualification_id=$QUAL_ID" "isolation_id=$CONSUMER_ID"
     "source_repository=$AMH_SRC" "expected_origin=$AMH_ORIGIN" "commit=$AMH_COMMIT"
     "isolation_root=$ISO_ROOT" "evidence_root=$EVID_ROOT" target=ios-simulator
     timeout_seconds=900 log_max_bytes=1048576 evidence_retention=keep cleanup_policy=none)
bash cbs/qualification/flutter/preflight.sh "${REQ[@]}" actions=preflight
bash cbs/qualification/flutter/analyze.sh "${REQ[@]}" actions=preflight,analyze
```

Expected observations: step 3 `RESULT=PASS` (`CREATED`, then `PRESENT`), PREFLIGHT
`RESULT=PASS`, ANALYZE `RESULT=PASS` with a log in the evidence directory. Any other
value is reported as observed, never as a PASS. The historical `COMMAND_FAILED` with
tool status 66 is the failure this step is meant to remove: it is considered removed
only if ANALYZE passes after the preparation.

### Observed macOS qualification — D04b-C.2c

Executed on 2026-10-15 with Flutter 3.47.6 and Dart 3.13.5.

- Framework qualification implementation: `966ed2cf6b26752996a62de3a68f81d8457cd510`.
- AMH-USR consumer commit: `bc0ad39d8be6b42a0109b7de18a6104b038f3f92`.
- Framework dependency commit: `177ba996e02b7c58ba1c54aed9f965ba71db8ff2`.
- Dependency preparation: `PASS` (`CREATED`).
- Dependency verification: `PASS` (`PRESENT`).
- PREFLIGHT: `PASS`, return code `0`.
- ANALYZE: `PASS`, tool return code `0`; no issues found.
- Qualification identifier: `amh-usr-d04-c2c-01`.
- Evidence on the qualification Mac:
  `$HOME/.cbs/evidence/amh-usr-d04-c2c-01/amh-usr-d04-c2c-01/`.
- Evidence files: `ANALYZE.result` and `ANALYZE.log`.
- Evidence retention: `keep`; cleanup not authorized.

The historical Flutter command failure with tool return code `66`
was not reproduced after dependency preparation.

This result qualifies PREFLIGHT and ANALYZE for the specified commits
and environment. It does not qualify other Flutter operations.

## Cleanup commands (Mac)

Only what these steps created, in this order. Nothing is forced; a refusal is
reported and stops the sequence. The evidence directory is kept.

```bash
bash cbs/worktree/isolation_manager.sh cleanup "$CONSUMER_ID" "$AMH_SRC" "$ISO_ROOT"
bash cbs/qualification/flutter/dependencies.sh cleanup "$ISO_ROOT" cbs-environment-framework "$CBS_FW"
```

If `flutter analyze` left the consumer checkout modified (for example `pubspec.lock`),
the first command is refused (dirty worktree): inspect it, and decide explicitly what
to do with the isolation; do not use `git reset` or `git clean` on it from this
procedure. The previous isolation `amh-usr-d04-analyze-01` is not touched by any of
these commands.
