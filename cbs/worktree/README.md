# Worktree lifecycle

B17b-D implements the minimal CBS Git worktree lifecycle layer.

The implementation manages Git worktrees only. It does not create, start or qualify runtime instances.

## Implemented components

```text
cbs/worktree/contract.sh
cbs/worktree/worktree_observer.sh
cbs/worktree/worktree_manager.sh
```

## Worktree contract

Qualified states:

```text
READY
MISSING
BRANCH_CONFLICT
PATH_CONFLICT
INVALID_REPOSITORY
UNKNOWN
```

Qualified actions:

```text
READY -> REUSE
MISSING -> CREATE
BRANCH_CONFLICT -> BLOCK
PATH_CONFLICT -> BLOCK
INVALID_REPOSITORY -> BLOCK
UNKNOWN -> BLOCK
```

Qualified branch observations:

```text
ATTACHED
DETACHED
ABSENT
UNKNOWN
```

## Observer

The observer is read-only.

It reports:

```text
worktree path
branch attachment state
branch name or DETACHED
HEAD
worktree CLEAN or DIRTY state
worktree count
```

The real Core Platform observation qualified three existing worktrees:

```text
/home/sscheidegger/projects/core-platform
/home/sscheidegger/projects/b17-step13-3-fresh-worktree
/home/sscheidegger/projects/b17-step13-clean-worktree
```

Observed classification:

```text
1 ATTACHED worktree
2 DETACHED worktrees
3 DIRTY worktrees
```

No Core worktree mutation was performed.

## Worktree Manager

The manager qualifies and implements:

```text
CREATE of a missing worktree when the branch exists and the parent path exists
REUSE of an already compliant worktree
BLOCK when the requested branch is already materialized elsewhere
BLOCK when the requested path is incompatible
BLOCK when the repository is invalid
BLOCK when the requested branch does not exist
```

The manager does not recursively create missing parent directories.

The manager performs no implicit reset, clean, checkout correction, branch deletion or worktree deletion.

## Coexistence qualification

B17b-D qualified simultaneous Git worktree coexistence for:

```text
develop
release
hotfix
```

The qualification fixture contained four worktrees in total:

```text
primary repository worktree
develop
release
hotfix
```

This proves Git worktree coexistence only.

It does not prove multi-instance runtime isolation.

## CLI

Qualified commands:

```text
cbs worktree check <repository-path>
cbs worktree ensure <repository-path> <worktree-path> <branch>
```

The check command is read-only.

The ensure command exposes only CREATE, REUSE and BLOCK behavior already qualified by the Worktree Manager.

## Safety principles

```text
observe before mutate
validate repository before worktree operation
one branch -> one active worktree
reuse when already compliant
fail explicitly on path or branch conflict
no hidden reset or clean
no implicit deletion
```

## Qualification boundary

B17b-D does not qualify:

```text
runtime instance lifecycle
ports
Docker networks
volumes
runtime configuration
secrets
multi-instance runtime coexistence
stack resolution
deployment
release management
```

Runtime instance lifecycle belongs to the later B17b Local Instance unit.

## Qualification result

```text
B17b-D_STEP_8_1_RESULT=PASS
B17b-D_STEP_8_1_SYNTAX=PASS
B17b-D_STEP_8_1_TESTS=PASS
B17b-D_STEP_8_1_REAL_CORE=PASS
B17b-D_STEP_8_1_NON_REGRESSION=PASS
B17b-D_STEP_8_1_CHANGESET_SCOPE=PASS
```

# Git isolation (D04b-C.1)

D04b-C.1 adds a separate capability: a detached Git worktree at an explicit commit, created under a dedicated authorized root, with a CBS ownership proof and an explicit, guarded cleanup.

It extends this directory without modifying the B17b-D contract, observer or manager. `cbs worktree check` and `cbs worktree ensure` are unchanged. The capability is not exposed through `bin/cbs` and `cbs/remote` is untouched.

## Components

```text
cbs/worktree/isolation_contract.sh
cbs/worktree/isolation_manager.sh
```

The manager reuses `contract.sh` (return codes, branch states) and `worktree_observer.sh` (repository validation, branch state, worktree state).

## Commands

```text
isolation_manager.sh create  <id> <source-repository> <expected-origin> <commit> <isolation-root>
isolation_manager.sh verify  <id> <source-repository> <isolation-root>
isolation_manager.sh cleanup <id> <source-repository> <isolation-root>
```

`verify` is read-only. Inputs are validated as data and never sourced or evaluated.

## Preconditions checked before any mutation

```text
identifier: 1..64 chars, [A-Za-z0-9._-], alphanumeric first, no ".lock" suffix
source: absolute, canonical, no symlink component, top level of a Git work tree
origin: `git remote get-url origin` must equal the expected origin (local read, no network)
commit: full lowercase object name, object type "commit", present locally (no implicit retrieval)
root: absolute, canonical, not a symlink, owned by the current user, not group/world writable,
      disjoint from the source repository, explicitly authorized by a marker file
```

The root is authorized only when it contains a regular file (not a symlink) named `.cbs-isolation-root` whose first line is `CBS_ISOLATION_ROOT_V1`. The operator creates it.

The worktree path is always `<root>/<id>`. Any existing entry at that path (directory, file, symlink, dangling symlink, registered or stale worktree) is refused. An empty directory is not adopted.

## Ownership proof

Each creation records `<root>/.cbs-isolation/<id>.proof` (outside the worktree): identifier, random token, state, source, Git common directory, origin (credentials redacted), commit, root, path, worktree Git directory, identity of the directory and of the Git directory (inode, `ls -di`) and proof file. The identifier is reserved atomically (no-clobber) before the worktree is created. An identifier is never reused, including after a cleanup or an abort.

The evidence directory is protected:

```text
.cbs-isolation/        not a symlink, a directory, owned by the current user, mode exactly 700
<id>.proof, <id>.cleaned   regular, not a symlink, owned by the current user, a single link,
                           not writable by group or others (created with mode 600)
```

A directory or a proof that does not meet this is refused (`PROOF_DIR_INVALID`, `PROOF_DIR_NOT_OWNED`, `PROOF_DIR_INSECURE`, `PROOF_SYMLINK`, `PROOF_NOT_OWNED`, `PROOF_INSECURE`), never repaired. Proofs are written through an exclusive temporary file with a unique name, then renamed. A proof, a cleaned record or a lock that already exists is never overwritten or written through.

## Mutual exclusion

`create` and `cleanup` of one authorized root are serialized by a lock directory `<root>/.cbs-isolation.lock`, taken with `mkdir` (atomic on Linux and macOS, no `flock`, Bash 3.2 compatible) after the root has been validated, so that no lock is ever created in a root that was not authorized. The lock records its owner (`pid`, random token); it is released only by its owner, also on `INT`, `TERM` and `HUP` (exit 130, 143, 129, result `FAIL`, reason `INTERRUPTED`).

A lock that is held blocks with `LOCK_BUSY` (68). It is never stolen: a lock left by a hard kill (`SIGKILL`) or a crash blocks every later create and cleanup of that root until the operator checks that no CBS operation is running and removes `<root>/.cbs-isolation.lock`. `verify` is read-only and does not take the lock.

## Reuse and cleanup

```text
REUSE: forbidden (ID_ALREADY_USED / PATH_EXISTS)
CLEANUP: only after the proof and the Git association agree
```

Cleanup requires: the lock of the root, a valid proof in state READY, same source, same root, recomputed path equal to the recorded path, no symlink, Git top level equal to the path, Git directory equal to the recorded one, located under the source common directory and pointing back to `<path>/.git`, same identity of the directory and of the Git directory as recorded, HEAD equal to the recorded commit, detached HEAD, clean worktree, and the worktree listed by the source.

All of these invariants are established a second time immediately before the removal (lock still held, proof unchanged, same identities, HEAD, detached state, cleanliness). Only then does it run a non-forced `git worktree remove` on that exact path, keeps the proof and writes `<id>.cleaned` next to it (exclusive creation, mode 600).

A dirty, locked, replaced, moved or re-attached worktree is refused. There is no forced mode. A cleanup that fails (Git refuses, Git fails half way, the source changed) performs no further deletion: no retry, no `rmdir`, no sweep. The proof is kept and a later attempt on a damaged resource is refused.

## Rollback of a failed creation

If creation fails after the reservation, only what this very invocation created may be rolled back, and only when it is demonstrated at that moment that: the lock is still held, the proof is still the file this invocation wrote (same inode, token and identifier), the path is not a symlink and is still the directory this invocation made (same identity), and, when Git registered a worktree there, every invariant above holds (association, HEAD, detached, clean).

```text
not registered  -> rmdir of the empty directory made by this invocation (never recursive)
registered      -> non-forced git worktree remove of that exact path
anything else   -> refused, the resource is left exactly as found
```

A refused rollback is reported (`ROLLBACK=INCOMPLETE`, `ROLLBACK_REASON=<reason>`, for example `PATH_REPLACED`, `PATH_SYMLINK`, `WORKTREE_DIRTY`, `HEAD_MISMATCH`, `PROOF_SUBSTITUTED`, `LOCK_LOST`). The result is FAIL. The proof is moved to ABORTED only when the lock and the proof are still ours; an ABORTED or CREATING proof never authorizes a cleanup. An interrupted rollback leaves the proof in CREATING: the resource is quarantined, the identifier stays burnt, nothing more is removed.

The implementation never runs `git reset --hard`, `git clean`, `git worktree prune`, any forced Git operation (`--force`, `-f`), any recursive deletion, or any network Git operation. Repository hooks and file system monitors are disabled for the commands it runs.

## macOS (BSD) command compatibility

The manager uses only options shared by GNU and BSD tools: `find <path> -maxdepth 0 -user|-perm|-links` (explicit path first, exact `-perm` or `-perm -mode`), `sed` with `-n`/`-e`, basic regular expressions and `s///` flags `g`/`p` only, `ls -di`, `od -An -N16 -tx1`, `mkdir -m`, `mv -f`, `rm -f` on its own temporary file and lock owner file, `rmdir`. No `flock`, `stat`, `readlink -f`, `realpath`, `date -d`, `sed -i`. `tests/test_worktree_isolation_portability.sh` enforces this with strict `find`/`sed`/`ls` wrappers and a static scan. It is not a substitute for a native macOS run.

## Structured output

```text
CBS_FLUTTER_ISOLATION_RESULT=PASS|FAIL|BLOCKED
CBS_FLUTTER_ISOLATION_ID / ORIGIN / COMMIT_EXPECTED / COMMIT_OBSERVED / PATH
CBS_FLUTTER_ISOLATION_GIT_STATUS / PROOF_ID / REMOVED / ROLLBACK / REASON / RC
```

Values that were not observed or not executed are reported as `NOT_RUN`. `SKIPPED` is never a runtime result.

`CBS_FLUTTER_ISOLATION_ROLLBACK_REASON` is `NOT_RUN` when no rollback was needed, `NONE` when it completed, the refusal reason otherwise.

Return codes: 61 path/root/evidence directory/lock, 62 source repository, 64 usage (inherited from the worktree contract), 65 commit, 66 origin, 67 ownership/proof, 68 state conflict (including `LOCK_BUSY`), 69 operation failure.

## Tests

```text
tests/test_worktree_isolation_contract.sh
tests/test_worktree_isolation_create.sh
tests/test_worktree_isolation_paths.sh
tests/test_worktree_isolation_cleanup.sh
tests/test_worktree_isolation_rollback.sh
tests/test_worktree_isolation_concurrency.sh
tests/test_worktree_isolation_removal.sh
tests/test_worktree_isolation_evidence.sh
tests/test_worktree_isolation_portability.sh
tests/fixtures/worktree_isolation/lib.sh
tests/fixtures/worktree_isolation/git_shim.sh
tests/fixtures/worktree_isolation/strict_find.sh
tests/fixtures/worktree_isolation/strict_sed.sh
tests/fixtures/worktree_isolation/strict_ls.sh
```

The tests are hermetic: temporary repositories, no network, no user Git configuration. Faults (path or proof replaced, lock claimed, worktree modified, removal failing or interrupted) are injected by a test-only Git wrapper placed first in `PATH` by the tests; production code contains no test hook.

## Qualification boundary

D04b-C.1 does not qualify: Flutter execution, SSH transport, mutating remote operations, macOS native execution (the portability tests run on the host that executes them, with strict wrappers, not on macOS), real WSL-to-Mac isolation, reuse of an existing isolation (forbidden), or forced cleanup of a modified worktree.

Known limits: the lock protects against concurrent CBS operations, not against another process of the same user that ignores it; the identity of a directory is its inode, so a directory removed and recreated may reuse it (the non-recursive `rmdir` and the Git invariants still apply, and a non-empty directory is never removed); between the last verification and `git worktree remove` there remains the unavoidable window of any check-then-act sequence (Git itself refuses a modified or locked worktree); a lock left by `SIGKILL` must be removed by the operator; the Git directory back-link is compared with an absolute path, so a Git configured to store relative worktree paths would be refused (safe side).
