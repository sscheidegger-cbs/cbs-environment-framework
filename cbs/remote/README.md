# CBS Remote

Generic, declarative, allow-listed execution of CBS commands on a remote host
over SSH.

The component is independent of Flutter, of any stack and of any platform
repository. It does not synchronise Git, does not build, does not deploy and
never runs a shell command supplied by the user.

## Components

- `contract.sh`: results, reasons, return codes, validation patterns and the
  explicit allow-list of CBS commands that may be bound to a remote action.
- `remote_manifest.sh`: strict loader for the declarative manifest.
- `remote_transport.sh`: SSH invocation, argument quoting, the two fixed
  remote scripts (read-only probe, launcher) and the filter of the launch
  session output.
- `remote_verifier.sh`: remote repository verification (identity, branch,
  commit, cleanliness, entrypoint).
- `remote_checker.sh`: `cbs remote check`.
- `remote_runner.sh`: `cbs remote run`.

## Commands

```text
cbs remote check <manifest>
cbs remote run <manifest> <action>
```

`check` is read-only: it verifies the connection and the remote repository and
executes nothing.

`run` performs the same verification, then executes the CBS command bound to
`<action>` in the remote repository. The launcher repeats the verification in
the SSH session that executes the action, immediately before `exec` (see
"Verification"). No extra argument is accepted: the arguments of an action are
fixed by the manifest.

Neither command fetches, pulls, pushes, clones, checks out, resets, cleans,
stashes or commits. A remote repository that is not already in the expected
state is refused, not repaired.

## Manifest

A manifest is a `KEY=VALUE` file. Blank lines and lines starting with `#` are
ignored. It is parsed, never sourced: no shell code in a manifest is evaluated.
Unknown keys, duplicate keys, empty values, indented lines, CRLF line endings
and values outside the documented character set are rejected.

A manifest contains no secret. SSH authentication relies on the SSH
configuration, agent and keys of the invoking user. A repository origin that
carries a password or token is refused.

The framework ships no manifest. Keep manifests outside the framework
repository, or in an untracked location.

### Keys

Required:

```text
CBS_REMOTE_MANIFEST_VERSION=1
CBS_REMOTE_ID=<id>
CBS_REMOTE_SSH_DESTINATION=<ssh alias | user@host>
CBS_REMOTE_REPOSITORY_PATH=<absolute path on the remote host>
CBS_REMOTE_REPOSITORY_ORIGIN=<expected origin URL>
CBS_REMOTE_EXPECTED_BRANCH=<branch>
CBS_REMOTE_EXPECTED_COMMIT=<40 or 64 hex digits | LOCAL_HEAD>
CBS_REMOTE_ALLOWED_ACTIONS=<action names separated by single spaces>
CBS_REMOTE_ACTION_<NAME>_COMMAND=<CBS command words>   (one per allowed action)
```

Optional:

```text
CBS_REMOTE_SSH_PORT=<1-65535>
CBS_REMOTE_SSH_CONNECT_TIMEOUT=<1-120, default 10>
CBS_REMOTE_SSH_IDENTITY_FILE=<absolute path of a private key file>
CBS_REMOTE_PATH_PREPEND=<absolute directories separated by ":">
CBS_REMOTE_CBS_ENTRYPOINT=<path of the CBS executable, default bin/cbs>
CBS_REMOTE_LOCAL_REPOSITORY_PATH=<local repository>   (only with LOCAL_HEAD)
```

Rules:

- The host address is configuration, not framework code. Prefer an SSH alias
  defined in `~/.ssh/config` as `CBS_REMOTE_SSH_DESTINATION`.
- `CBS_REMOTE_SSH_IDENTITY_FILE` is a path only; the key content never enters a
  manifest.
- `CBS_REMOTE_EXPECTED_COMMIT=LOCAL_HEAD` compares the remote `HEAD` with the
  `HEAD` of `CBS_REMOTE_LOCAL_REPOSITORY_PATH` (absolute, or relative to the
  manifest directory). A literal commit pins an exact commit and forbids
  `CBS_REMOTE_LOCAL_REPOSITORY_PATH`.
- Remote paths must be absolute, must not contain `..` or `~`, and may only
  contain letters, digits, `. _ / + @ - ` and inner spaces.
- `CBS_REMOTE_CBS_ENTRYPOINT` is relative to the remote repository, or
  absolute.
- Action names match `[a-z][a-z0-9_]{0,39}`. The command of the action named
  `x_y` is declared in `CBS_REMOTE_ACTION_X_Y_COMMAND`.
- An action command is a list of words separated by single spaces. Each word
  is made of `A-Z a-z 0-9 . _ / + @ : = % , -`. Shell metacharacters, quotes,
  globs, `~` and `..` segments are rejected. The first word cannot start with
  `-`.

### Allowed CBS commands

The first words of an action command must be exactly one entry of this
explicit allow-list (`CBS_REMOTE_COMMAND_ALLOW_LIST` in `contract.sh`):

```text
version
status
workstation check
workspace check
worktree check
instance check
stack resolve
stack prerequisites
stack environment
platform resolve
runtime android list
```

Each entry is listed because the CBS code it reaches was read and found to
observe or resolve only: it creates, modifies, installs, starts, stops and
deletes nothing. `stack prerequisites` and `stack environment` only detect
toolchains (`CBS_TOOLCHAIN_MUTATION=NONE`); `instance check` only lists
Docker containers, networks and volumes; `runtime android list` only runs
`emulator list`.

Excluded on purpose:

```text
stack toolchains ensure        installs toolchains
platform start                 starts the platform
platform stop                  stops the platform
runtime android ensure|start|stop
workspace ensure, repository ensure, worktree ensure, instance ensure
platform check, platform status, platform qualify
remote                         no recursion
```

`platform check`, `platform status` and `platform qualify` are excluded
because CBS only dispatches them to a hook script owned by the platform
repository: their effect cannot be established from CBS. For the Core Platform
binding read during this work, the `check` hook chain starts the `postgres`
service (`docker compose up -d`) and runs SQL `DROP TABLE` / `CREATE TABLE` /
`INSERT`, the `status` hook runs `uv run` (which may synchronise a Python
environment), and the `qualify` hook creates and removes report directories.
Those observations describe one platform repository at one commit; they are
not a guarantee for any other.

Any operation whose name contains `ensure`, `start`, `stop` or an installation
is outside the catalog. Extending the allow-list is an explicit change of
`contract.sh` together with its tests (`tests/test_remote_contract.sh`
compares the list entry by entry). The manifest loader refuses any action whose
command is not in the list (`COMMAND_NOT_ALLOWED`) before any SSH session.

### Example

The values below are placeholders.

```text
CBS_REMOTE_MANIFEST_VERSION=1
CBS_REMOTE_ID=builder
CBS_REMOTE_SSH_DESTINATION=builder-host
CBS_REMOTE_REPOSITORY_PATH=/srv/work/cbs-environment-framework
CBS_REMOTE_REPOSITORY_ORIGIN=git@git.example.invalid:group/cbs-environment-framework.git
CBS_REMOTE_EXPECTED_BRANCH=main
CBS_REMOTE_EXPECTED_COMMIT=LOCAL_HEAD
CBS_REMOTE_LOCAL_REPOSITORY_PATH=/home/user/work/cbs-environment-framework
CBS_REMOTE_ALLOWED_ACTIONS=stack_resolve stack_environment
CBS_REMOTE_ACTION_STACK_RESOLVE_COMMAND=stack resolve stacks/flutter/stack.env
CBS_REMOTE_ACTION_STACK_ENVIRONMENT_COMMAND=stack environment stacks/flutter/stack.env
```

```text
cbs remote check builder.remote.env
cbs remote run builder.remote.env stack_resolve
```

## SSH contract

Every invocation uses:

```text
ssh -T -n
    -o BatchMode=yes
    -o StrictHostKeyChecking=yes
    -o PasswordAuthentication=no
    -o KbdInteractiveAuthentication=no
    -o ConnectionAttempts=1
    -o ConnectTimeout=<n>
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3
    -o ClearAllForwardings=yes -o ForwardAgent=no -o ForwardX11=no
    -o PermitLocalCommand=no
    [-p <port>] [-o IdentitiesOnly=yes -i <identity file>]
    -- <destination> <remote command>
```

There is no password prompt, no host-key prompt, no terminal and no
forwarding. An unknown or changed host key, a refused authentication and an
unreachable host all end as `BLOCKED` / `HOST_UNREACHABLE`; the SSH
diagnostic is forwarded unchanged on standard error.

`ssh` is resolved through `PATH`.

## Argument transmission

The remote command line is never built from user text. It is one of two
fixed scripts, run through `/bin/sh -c`, followed by individually
single-quoted words (POSIX quoting, valid for `sh`, `bash` and `zsh`). The
declared CBS entrypoint is started with `exec` and receives its arguments as
separate words, in the remote repository directory.

## Verification

The remote repository is verified twice.

1. A read-only probe (first SSH session) gives an early refusal and the
   diagnostic output.
2. The launcher (second SSH session, the one that executes the action)
   repeats the same observations immediately before `exec`, in the same
   session, and refuses to start the entrypoint on any difference. This
   second verdict is the one that gates execution. A change made on the remote
   host between the probe and the launch is therefore detected.

Both observe the same facts. The probe observes the remote host:

1. `git` is available;
2. the path exists, is a directory and is the top level of a Git repository
   (a subdirectory of a repository is refused);
3. `origin` equals `CBS_REMOTE_REPOSITORY_ORIGIN` exactly;
4. the current branch equals `CBS_REMOTE_EXPECTED_BRANCH` (a detached `HEAD` is
   refused);
5. `HEAD` equals the expected commit;
6. the worktree is clean: any tracked or untracked change, staged or not,
   blocks execution; a failing `git status` blocks execution;
7. the CBS entrypoint exists and is executable.

The probe uses no network access from the remote repository: it reads local
Git state only.

Repository states reuse the Workspace / Repository contract vocabulary
(`READY`, `MISSING`, `NOT_GIT`, `REMOTE_MISMATCH`, worktree `CLEAN` / `DIRTY` /
`UNKNOWN`) and its return codes 50, 51 and 52.

When `HEAD` is not the expected commit, the relation is reported for
diagnosis only: `AHEAD`, `BEHIND`, `DIVERGED` or `UNKNOWN_OBJECT` (the
expected commit does not exist in the remote repository). All of them are
refused.

Credentials found in an observed origin are masked before display.

### Launcher revalidation

Immediately before `exec`, in the same SSH session, the launcher re-checks:
Git availability, repository identity (path exists, is a directory, is the top
level of a Git repository) and `origin`, the branch, the commit (`HEAD` must
equal the commit resolved before the probe, not a newly resolved one), the
cleanliness of the worktree and the availability of the CBS entrypoint. It
repairs nothing: no fetch, checkout, reset, clean or stash.

On a difference the launcher exits without starting the entrypoint and
`cbs remote run` ends as `BLOCKED` with the same reason and return code as the
initial verification (`REPOSITORY_*` 50-52, `BRANCH_MISMATCH` 104,
`COMMIT_MISMATCH` 105, `WORKTREE_DIRTY` 106, `ENTRYPOINT_UNAVAILABLE` 108,
`REMOTE_GIT_UNAVAILABLE` 103). The output carries
`CBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED` and `CBS_REMOTE_LAUNCH_REFUSAL=<reason>`.
The observed origin is never printed by the launcher path.

Verdict protocol: the launcher prints its verdict lines
(`CBS_REMOTE_LAUNCH_*`) on standard output before `exec`. The last protocol
line is `CBS_REMOTE_LAUNCH_PREFLIGHT=PASS` or `=REFUSED`. The local side
consumes the protocol lines up to that line only; everything printed after it
is forwarded unchanged, so the action cannot forge or alter the verdict.
`CBS_REMOTE_ACTION_EXECUTION=START` is printed only after a `PASS` verdict was
received. Values received from the host are accepted only in their documented
shape.

## Results

Every invocation ends with exactly one `CBS_REMOTE_RESULT=` line on standard
output, the last line produced by the component itself.

```text
PASS     all verifications passed; for run, the remote action returned 0
BLOCKED  a precondition was not met; nothing was executed remotely
FAIL     the remote action ran and failed, or the probe itself malfunctioned
```

Other output keys: `CBS_REMOTE_CONTRACT_VERSION`, `CBS_REMOTE_OPERATION`,
`CBS_REMOTE_MANIFEST`, `CBS_REMOTE_ID`, `CBS_REMOTE_DESTINATION`,
`CBS_REMOTE_REPOSITORY_PATH`, `CBS_REMOTE_SSH_RC`, `CBS_REMOTE_CONNECTION`,
`CBS_REMOTE_REPOSITORY_STATE`, `CBS_REMOTE_REPOSITORY_EXPECTED_ORIGIN`,
`CBS_REMOTE_REPOSITORY_OBSERVED_ORIGIN`, `CBS_REMOTE_EXPECTED_BRANCH`,
`CBS_REMOTE_OBSERVED_BRANCH`, `CBS_REMOTE_EXPECTED_COMMIT`,
`CBS_REMOTE_OBSERVED_COMMIT`, `CBS_REMOTE_COMMIT_RELATION`,
`CBS_REMOTE_WORKTREE_STATE`, `CBS_REMOTE_ENTRYPOINT_STATE`,
`CBS_REMOTE_ACTION`, `CBS_REMOTE_ACTION_COMMAND`,
`CBS_REMOTE_ACTION_EXECUTION`, `CBS_REMOTE_ACTION_RC`, `CBS_REMOTE_REASON`,
`CBS_REMOTE_LAUNCH_PREFLIGHT`, `CBS_REMOTE_LAUNCH_OBSERVED_BRANCH`,
`CBS_REMOTE_LAUNCH_OBSERVED_COMMIT`, `CBS_REMOTE_LAUNCH_REFUSAL`,
`CBS_REMOTE_DIAGNOSTIC`.

`CBS_REMOTE_ERROR=<reason>` is also written to standard error for `BLOCKED` and
`FAIL`.

### Reasons and return codes

```text
PASS                          0
USAGE                         64   BLOCKED
REPOSITORY_MISSING            50   BLOCKED
REPOSITORY_NOT_GIT            51   BLOCKED
REPOSITORY_ORIGIN_MISMATCH    52   BLOCKED
MANIFEST_INVALID              100  BLOCKED
LOCAL_SSH_UNAVAILABLE         101  BLOCKED
HOST_UNREACHABLE              102  BLOCKED
REMOTE_GIT_UNAVAILABLE        103  BLOCKED
BRANCH_MISMATCH               104  BLOCKED
COMMIT_MISMATCH               105  BLOCKED
WORKTREE_DIRTY                106  BLOCKED (also WORKTREE_UNKNOWN)
ACTION_NOT_ALLOWED            107  BLOCKED
ENTRYPOINT_UNAVAILABLE        108  BLOCKED
LOCAL_REFERENCE_UNAVAILABLE   109  BLOCKED
PROBE_FAILED                  110  FAIL
LAUNCH_NOT_CONFIRMED          110  FAIL
REMOTE_ACTION_FAILED          <remote return code>  FAIL
TRANSPORT_FAILURE             255  FAIL (label of ssh status 255, see below)
```

The return codes of the first probe and of the launcher refusals are the
codes that existed before the launcher revalidation. The only addition is the
reason `LAUNCH_NOT_CONFIRMED`, which reuses code 110.

For `FAIL` / `REMOTE_ACTION_FAILED`, the return code of the remote CBS command
is the return code of `cbs remote run` and is also printed as
`CBS_REMOTE_ACTION_RC`. Remote standard output and standard error are
forwarded unchanged on the matching local streams. Because a remote command
may itself return a value that equals one of the codes above, rely on
`CBS_REMOTE_RESULT` and `CBS_REMOTE_REASON` rather than on the return code
alone to tell the cases apart.

## Diagnostics: transport, preflight refusal, action failure

Three situations are told apart by the evidence the local side received, not
by the return code alone.

| Situation | Result and reason | Evidence |
| --- | --- | --- |
| Preflight refusal | `BLOCKED`, reason of the check (`WORKTREE_DIRTY`, ...) | probe verdict, or `CBS_REMOTE_LAUNCH_PREFLIGHT=REFUSED`; the entrypoint was not started |
| Action failure | `FAIL` / `REMOTE_ACTION_FAILED`, the action return code | `CBS_REMOTE_LAUNCH_PREFLIGHT=PASS` and `CBS_REMOTE_ACTION_EXECUTION=START` were received, the status is not 255 |
| ssh status 255 | `FAIL` / `TRANSPORT_FAILURE`, return code 255 | see below |
| No launcher verdict, status other than 255 or 0 | `FAIL` / `LAUNCH_NOT_CONFIRMED`, return code 110 | `CBS_REMOTE_LAUNCH_PREFLIGHT=NOT_REPORTED`, `CBS_REMOTE_ACTION_RC` printed |

Return codes alone are ambiguous: a remote action may return any value,
including the ones used by the preflight (50-52, 104-110) and 255. Use
`CBS_REMOTE_RESULT`, `CBS_REMOTE_REASON` and `CBS_REMOTE_LAUNCH_PREFLIGHT`.

### Status 255

`ssh` returns 255 for its own failures (unreachable host, refused or failed
authentication, host key, timeout, broken connection), but a remote command
may also return 255. When `ssh` returns 255 without proof of its origin,
no certain distinction is announced:

- the reason `TRANSPORT_FAILURE` is a label attached to the status 255, not a
  proof that the failure came from SSH;
- `CBS_REMOTE_DIAGNOSTIC=SSH_STATUS_255_NO_LAUNCHER_VERDICT`: no launcher
  verdict was received; whether the action started is not established;
- `CBS_REMOTE_DIAGNOSTIC=SSH_STATUS_255_ORIGIN_UNDETERMINED`: the launcher
  verdict was `PASS` and the action started; the 255 can come from the
  action or from a connection lost during the action;
- the SSH diagnostic written on standard error is forwarded unchanged and is
  the only available hint.

For the first probe, a 255 is reported as `BLOCKED` / `HOST_UNREACHABLE`. That
reading relies on the design of the probe (a fixed script that ends with
`exit 0` once it started), not on a proof received at run time.

## Order of checks in `run`

```text
1. manifest loading and validation          (no network)
2. action allow-list                        (no network)
3. local ssh availability
4. resolution of the expected commit        (local Git only)
5. remote probe and verification            (first SSH session, read-only)
6. launcher revalidation, then exec         (second SSH session, one script)
```

## Limits

- Verification and execution use two SSH connections. The launcher repeats
  the verification in the second one, immediately before `exec`; a change made
  between the probe and the launch is detected and refused. A change made
  after the launcher's last observation (the few instructions before `exec`,
  or during the action) cannot be detected: no lock is taken on the remote
  repository, and the action itself is free to modify its own repository.
- No overall timeout applies to a remote action. `ServerAlive*` options end a
  dead connection.
- `255` returned by SSH cannot be told apart from a remote command returning
  `255` (see "Status 255").
- With `LOCAL_HEAD`, only the local `HEAD` commit is compared; the local
  worktree state is not checked.
- Remote non-interactive SSH sessions may have a reduced `PATH`.
  `CBS_REMOTE_PATH_PREPEND` prepends directories to it for the probe and the
  action.
- `git status` may refresh the index of the remote repository (an
  optional-lock write inside `.git`); no tracked content changes.
- `stack prerequisites` and `stack environment` run the installed Flutter
  `--version` when a Flutter toolchain is present; whether a given Flutter
  version writes to its own SDK cache on first run was not established.
- Validated with a simulated SSH and temporary local Git repositories only
  (see `tests/README.md`). No real remote host, and no remote login shell
  other than `sh`, `bash` and `dash`, was used for qualification.
