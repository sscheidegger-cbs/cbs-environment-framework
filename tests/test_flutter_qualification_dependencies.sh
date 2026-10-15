#!/usr/bin/env bash

# D04b-C.2c: preparation of the local Flutter "path:" dependencies of an
# isolated consumer (cbs/qualification/flutter/dependencies.sh).
#
# Hermetic: temporary Git repositories, the real CBS isolation manager (D04b-C.1)
# in temporary isolation roots, no Flutter, no Dart, no network, no user Git
# configuration. Nothing under the real workspace, ~/.cbs or any real consumer
# is read or written. It runs on Linux and is meant to run on macOS with
# /bin/bash 3.2; it is not itself a native macOS run unless executed there.

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="$ROOT/cbs/qualification/flutter/dependencies.sh"
TEST_PREFIX="TEST_FLUTTER_QUALIFICATION_DEPENDENCIES"

source "$ROOT/tests/fixtures/worktree_isolation/lib.sh"

[[ -f "$DEPS" ]] || iso_fail "SCRIPT_MISSING"
bash -n "$DEPS" || iso_fail "SYNTAX"

iso_fixture_init

CONSUMER="$TMP/consumer"
FW="$TMP/fw"
OTHER="$TMP/other"
BAD="$TMP/bad"
CONSUMER_ORIGIN="https://example.invalid/cbs/consumer.git"
FW_ORIGIN="https://example.invalid/cbs/framework.git"
OTHER_ORIGIN="https://example.invalid/cbs/other.git"
BAD_ORIGIN="https://example.invalid/cbs/bad.git"

DEP_OUT=""
DEP_ERR=""
DEP_RC=0

# ---------------------------------------------------------------- helpers

make_repo() {
    # $1 directory, $2 origin
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config user.name "CBS D04b-C.2c Test"
    git -C "$1" config user.email "d04b-c2c-test@example.invalid"
    git -C "$1" remote add origin "$2"
    mkdir -p "$1/.local"
    printf '%s\n' "local-dev-state" > "$1/.local/note.txt"
}

# $1 repository, $2 message, then the paths to stage. Prints the commit.
commit_paths() {
    local repo="$1"
    local message="$2"

    shift 2
    git -C "$repo" add -- "$@"
    git -C "$repo" commit -q --allow-empty -m "$message" >/dev/null
    git -C "$repo" rev-parse HEAD
}

write_package() {
    # $1 repository, $2 package directory, $3 content
    mkdir -p "$1/$2"
    printf '%s' "$3" > "$1/$2/pubspec.yaml"
}

PKG_PLAIN='name: pkg
environment:
  sdk: ^3.0.0
'

new_root() {
    local dir="$TMP/$1"

    iso_make_root "$dir"
    printf '%s' "$dir"
}

# $1 root, $2 isolation id, $3 pubspec content. Commits it in the consumer
# repository and creates the CBS isolation of that commit. Sets CONSUMER_COMMIT.
make_consumer() {
    printf '%s' "$3" > "$CONSUMER/pubspec.yaml"
    CONSUMER_COMMIT="$(commit_paths "$CONSUMER" "manifest for $2" pubspec.yaml packages)"

    iso_run create "$2" "$CONSUMER" "$CONSUMER_ORIGIN" "$CONSUMER_COMMIT" "$1"
    iso_expect_pass "CONSUMER_ISOLATION_$2"

    # The new commit is a fixture action: the consumer state is the reference
    # from here on.
    SNAP_CONSUMER="$(repo_state "$CONSUMER")"
}

dep_run() {
    set +e
    DEP_OUT="$(bash "$DEPS" "$@" 2>"$TMP/deps-stderr")"
    DEP_RC=$?
    set -e
    DEP_ERR="$(cat "$TMP/deps-stderr")"
}

dep_value() {
    printf '%s\n' "$DEP_OUT" | sed -n "s/^CBS_FLUTTER_DEPS_$1=//p" | head -n 1
}

# dep_expect <label> <RESULT> <REASON|NONE> <rc>
dep_expect() {
    local label="$1"
    local result="$2"
    local reason="$3"
    local rc="$4"
    local last

    [[ "$DEP_RC" -eq "$rc" ]] || iso_fail "${label}_RC_EXPECTED_${rc}_GOT_${DEP_RC}_$(dep_value REASON)_$(dep_value DETAIL)"
    [[ "$(dep_value RESULT)" == "$result" ]] || iso_fail "${label}_RESULT_$(dep_value RESULT)_$(dep_value REASON)_$(dep_value DETAIL)"
    [[ "$(dep_value REASON)" == "$reason" ]] || iso_fail "${label}_REASON_EXPECTED_${reason}_GOT_$(dep_value REASON)_$(dep_value DETAIL)"
    [[ "$(dep_value RC)" == "$rc" ]] || iso_fail "${label}_RC_FIELD_$(dep_value RC)"
    [[ "$(dep_value VERSION)" == "1" ]] || iso_fail "${label}_VERSION"

    last="$(printf '%s\n' "$DEP_OUT" | tail -n 1)"
    [[ "$last" == "CBS_FLUTTER_DEPS_RESULT=$result" ]] || iso_fail "${label}_RESULT_NOT_LAST"

    if [[ "$result" == "PASS" ]]; then
        [[ -z "$DEP_ERR" ]] || iso_fail "${label}_STDERR_ON_PASS"
    else
        [[ "$DEP_ERR" == "CBS_FLUTTER_DEPS_ERROR=$reason" ]] || iso_fail "${label}_STDERR_NOT_THE_REASON"
    fi

    # Closed output language, and no path of the host.
    if printf '%s\n' "$DEP_OUT" | grep -v '^CBS_FLUTTER_DEPS_[A-Z0-9_]*=[A-Za-z0-9._-]*$' >/dev/null; then
        iso_fail "${label}_FOREIGN_OUTPUT_LINE"
    fi

    if printf '%s\n%s\n' "$DEP_OUT" "$DEP_ERR" | grep -F -e "$TMP" >/dev/null; then
        iso_fail "${label}_PATH_LEAKED"
    fi
}

# dep_state <label> <index> <STATE>
dep_state() {
    [[ "$(dep_value "DEPENDENCY_$2_STATE")" == "$3" ]] ||
        iso_fail "${1}_STATE_$2_EXPECTED_$3_GOT_$(dep_value "DEPENDENCY_$2_STATE")"
}

# Observable state of a source repository (development state to preserve).
repo_state() {
    printf 'HEAD=%s\n' "$(git -C "$1" rev-parse HEAD)"
    printf 'BRANCH=%s\n' "$(git -C "$1" branch --show-current)"
    git -C "$1" for-each-ref
    git -C "$1" status --porcelain
    printf 'NOTE=%s\n' "$(cat "$1/.local/note.txt")"
}

snapshot_sources() {
    SNAP_FW="$(repo_state "$FW")"
    SNAP_OTHER="$(repo_state "$OTHER")"
}

assert_sources_untouched() {
    [[ "$(repo_state "$CONSUMER")" == "$SNAP_CONSUMER" ]] || iso_fail "$1_CONSUMER_SOURCE_CHANGED"
    [[ "$(repo_state "$FW")" == "$SNAP_FW" ]] || iso_fail "$1_FW_SOURCE_CHANGED"
    [[ "$(repo_state "$OTHER")" == "$SNAP_OTHER" ]] || iso_fail "$1_OTHER_SOURCE_CHANGED"
    [[ -f "$FW/.local/note.txt" && -f "$OTHER/.local/note.txt" && -f "$CONSUMER/.local/note.txt" ]] || iso_fail "$1_UNTRACKED_LOST"
}

assert_no_symlink() {
    [[ -z "$(find "$1" -type l -print)" ]] || iso_fail "$2_SYMLINK_FOUND"
}

# ---------------------------------------------------------------- repositories

make_repo "$FW" "$FW_ORIGIN"
printf '%s\n' "framework" > "$FW/README.md"
FW_C0="$(commit_paths "$FW" "no package yet" README.md)"

write_package "$FW" packages/pkg_a 'name: pkg_a
environment:
  sdk: ^3.0.0
dependencies:
  pkg_b:
    path: ../pkg_b
'
write_package "$FW" packages/pkg_b "$PKG_PLAIN"
FW_C1="$(commit_paths "$FW" "packages" packages)"

make_repo "$OTHER" "$OTHER_ORIGIN"
write_package "$OTHER" pkg "$PKG_PLAIN"
OTHER_C1="$(commit_paths "$OTHER" "other package" pkg)"

make_repo "$BAD" "$BAD_ORIGIN"
write_package "$BAD" packages/pkg_n 'name: pkg_n
dependencies:
  elsewhere:
    path: ../../../outside
'
BAD_C1="$(commit_paths "$BAD" "escaping nested path" packages)"

make_repo "$CONSUMER" "$CONSUMER_ORIGIN"
mkdir -p "$CONSUMER/packages/local_pkg"
printf '%s' "$PKG_PLAIN" > "$CONSUMER/packages/local_pkg/pubspec.yaml"

MANIFEST_MAIN='name: consumer_app
description: fixture
environment:
  sdk: ^3.0.0
dependencies:
  flutter:
    sdk: flutter
  # a comment line
  pkg_a:
    path: ../fw/packages/pkg_a   # a trailing comment
  local_pkg:
    path: packages/local_pkg
  hosted_pkg: ^1.0.0
  git_pkg:
    git:
      url: https://example.invalid/x.git
      path: packages/not_local
dev_dependencies:
  flutter_test:
    sdk: flutter
  pkg_b: {path: '"'"'../fw/packages/pkg_b'"'"'}
flutter:
  uses-material-design: true
'

snapshot_sources

echo "${TEST_PREFIX}_FIXTURE=PASS"

# ---------------------------------------------------------------- 1. usage

R1="$(new_root root1)"

dep_run
dep_expect USAGE_NONE BLOCKED USAGE 64

dep_run frobnicate a b c
dep_expect USAGE_UNKNOWN BLOCKED USAGE 64

dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN"
dep_expect USAGE_ARITY BLOCKED USAGE 64

dep_run cleanup "$R1"
dep_expect USAGE_CLEANUP_NONE BLOCKED USAGE 64

dep_run cleanup "$R1" fw
dep_expect USAGE_CLEANUP_ODD BLOCKED USAGE 64

echo "${TEST_PREFIX}_USAGE=PASS"

# ---------------------------------------------------------------- 2. refusals before any change

make_consumer "$R1" consumer1 "$MANIFEST_MAIN"
C1_COMMIT="$CONSUMER_COMMIT"
BEFORE_ROOT="$(iso_tree_fingerprint "$R1")"

# Declared and not mapped.
dep_run prepare consumer1 "$CONSUMER" "$R1" other "$OTHER" "$OTHER_ORIGIN" "$OTHER_C1"
dep_expect UNMAPPED BLOCKED DEPENDENCY_UNMAPPED 144
[[ "$(iso_tree_fingerprint "$R1")" == "$BEFORE_ROOT" ]] || iso_fail "UNMAPPED_ROOT_CHANGED"

# Mapped and not needed: nothing is guessed, nothing unneeded is materialized.
dep_run prepare consumer1 "$CONSUMER" "$R1" \
    fw "$FW" "$FW_ORIGIN" "$FW_C1" other "$OTHER" "$OTHER_ORIGIN" "$OTHER_C1"
dep_expect UNUSED BLOCKED MAPPING_UNUSED 145
[[ "$(iso_tree_fingerprint "$R1")" == "$BEFORE_ROOT" ]] || iso_fail "UNUSED_ROOT_CHANGED"

# The commit does not hold the package.
dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C0"
dep_expect NO_PACKAGE BLOCKED SOURCE_REJECTED 148
[[ "$(iso_tree_fingerprint "$R1")" == "$BEFORE_ROOT" ]] || iso_fail "NO_PACKAGE_ROOT_CHANGED"

# An unknown commit (valid format, absent locally).
dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "0123456789abcdef0123456789abcdef01234567"
dep_expect UNKNOWN_COMMIT BLOCKED SOURCE_REJECTED 148

# Nothing was prepared yet: verify says so, read-only.
dep_run verify consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect VERIFY_MISSING BLOCKED DEPENDENCY_MISSING 147
dep_state VERIFY_MISSING 1 MISSING
[[ "$(iso_tree_fingerprint "$R1")" == "$BEFORE_ROOT" ]] || iso_fail "VERIFY_MISSING_ROOT_CHANGED"

assert_sources_untouched REFUSALS

echo "${TEST_PREFIX}_REFUSALS=PASS"

# ---------------------------------------------------------------- 3. prepare

dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect PREPARE PASS NONE 0
dep_state PREPARE 1 CREATED
[[ "$(dep_value OPERATION)" == "PREPARE" ]] || iso_fail "PREPARE_OPERATION"
[[ "$(dep_value CONSUMER_ID)" == "consumer1" ]] || iso_fail "PREPARE_CONSUMER_ID"
[[ "$(dep_value CONSUMER_COMMIT)" == "$C1_COMMIT" ]] || iso_fail "PREPARE_CONSUMER_COMMIT"
[[ "$(dep_value EXTERNAL_COUNT)" == "2" ]] || iso_fail "PREPARE_EXTERNAL_COUNT_$(dep_value EXTERNAL_COUNT)"
[[ "$(dep_value INTERNAL_COUNT)" == "1" ]] || iso_fail "PREPARE_INTERNAL_COUNT_$(dep_value INTERNAL_COUNT)"
[[ "$(dep_value DEPENDENCY_COUNT)" == "1" ]] || iso_fail "PREPARE_DEPENDENCY_COUNT"
[[ "$(dep_value DEPENDENCY_1_NAME)" == "fw" ]] || iso_fail "PREPARE_NAME"
[[ "$(dep_value DEPENDENCY_1_COMMIT_EXPECTED)" == "$FW_C1" ]] || iso_fail "PREPARE_COMMIT_EXPECTED"
[[ "$(dep_value DEPENDENCY_1_COMMIT_OBSERVED)" == "$FW_C1" ]] || iso_fail "PREPARE_COMMIT_OBSERVED"
[[ "$(dep_value DEPENDENCY_1_PACKAGE)" == "OK" ]] || iso_fail "PREPARE_PACKAGE"

# Provenance and state of the materialized resource.
[[ -d "$R1/fw" && ! -L "$R1/fw" ]] || iso_fail "PREPARE_NOT_A_DIRECTORY"
[[ "$(git -C "$R1/fw" rev-parse HEAD)" == "$FW_C1" ]] || iso_fail "PREPARE_HEAD"
[[ -z "$(git -C "$R1/fw" symbolic-ref -q HEAD || true)" ]] || iso_fail "PREPARE_NOT_DETACHED"
[[ -z "$(git -C "$R1/fw" status --porcelain)" ]] || iso_fail "PREPARE_NOT_CLEAN"
[[ -f "$R1/.cbs-isolation/fw.proof" ]] || iso_fail "PREPARE_NO_PROOF"
[[ -f "$R1/fw/packages/pkg_a/pubspec.yaml" && -f "$R1/fw/packages/pkg_b/pubspec.yaml" ]] || iso_fail "PREPARE_PACKAGES"
assert_no_symlink "$R1" PREPARE

# The relative path of the manifest resolves, as Flutter resolves it, from the
# isolated checkout to the materialized package.
RESOLVED="$(cd "$R1/consumer1" && cd ../fw/packages/pkg_a && pwd -P)"
[[ "$RESOLVED" == "$R1/fw/packages/pkg_a" ]] || iso_fail "PREPARE_RELATIVE_PATH_DOES_NOT_RESOLVE"

# The consumer checkout is untouched, the source repositories are preserved.
[[ -z "$(git -C "$R1/consumer1" status --porcelain)" ]] || iso_fail "PREPARE_CONSUMER_DIRTY"
assert_sources_untouched PREPARE

echo "${TEST_PREFIX}_PREPARE=PASS"

# ---------------------------------------------------------------- 4. idempotence, verify

AFTER_PREPARE="$(iso_tree_fingerprint "$R1")"

dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect REPREPARE PASS NONE 0
dep_state REPREPARE 1 REUSED
[[ "$(iso_tree_fingerprint "$R1")" == "$AFTER_PREPARE" ]] || iso_fail "REPREPARE_ROOT_CHANGED"

dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect REPREPARE_TWICE PASS NONE 0
dep_state REPREPARE_TWICE 1 REUSED

dep_run verify consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect VERIFY PASS NONE 0
dep_state VERIFY 1 PRESENT
[[ "$(dep_value OPERATION)" == "VERIFY" ]] || iso_fail "VERIFY_OPERATION"
[[ "$(iso_tree_fingerprint "$R1")" == "$AFTER_PREPARE" ]] || iso_fail "VERIFY_ROOT_CHANGED"

assert_sources_untouched IDEMPOTENCE

echo "${TEST_PREFIX}_IDEMPOTENCE=PASS"

# ---------------------------------------------------------------- 5. what is present is verified, never repaired

# Another commit or origin than the one materialized: conflict, left as found.
dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C0"
dep_expect OTHER_COMMIT BLOCKED SOURCE_REJECTED 148

FW_C2="$FW_C1"
printf '%s\n' "later" >> "$FW/README.md"
FW_C3="$(commit_paths "$FW" "later" README.md)"
snapshot_sources

dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C3"
dep_expect COMMIT_CONFLICT BLOCKED DEPENDENCY_CONFLICT 146
dep_state COMMIT_CONFLICT 1 CONFLICT
[[ "$(git -C "$R1/fw" rev-parse HEAD)" == "$FW_C2" ]] || iso_fail "COMMIT_CONFLICT_RESOURCE_MOVED"

dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "https://example.invalid/cbs/elsewhere.git" "$FW_C1"
dep_expect ORIGIN_CONFLICT BLOCKED DEPENDENCY_CONFLICT 146

[[ "$(iso_tree_fingerprint "$R1")" == "$AFTER_PREPARE" ]] || iso_fail "CONFLICTS_ROOT_CHANGED"

# A modified worktree is a conflict, never cleaned: the file stays.
printf '%s\n' "operator data" > "$R1/fw/untracked.txt"

dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect DIRTY_PREPARE BLOCKED DEPENDENCY_CONFLICT 146
dep_run verify consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect DIRTY_VERIFY BLOCKED DEPENDENCY_CONFLICT 146
dep_run cleanup "$R1" fw "$FW"
dep_expect DIRTY_CLEANUP BLOCKED CLEANUP_REFUSED 149
[[ "$(cat "$R1/fw/untracked.txt")" == "operator data" ]] || iso_fail "DIRTY_FILE_LOST"
[[ -d "$R1/fw" ]] || iso_fail "DIRTY_RESOURCE_REMOVED"

rm -f "$R1/fw/untracked.txt"

dep_run verify consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect VERIFY_AFTER_DIRTY PASS NONE 0
assert_sources_untouched CONFLICTS

echo "${TEST_PREFIX}_CONFLICTS=PASS"

# ---------------------------------------------------------------- 6. cleanup

# Only what the preparation materialized, nothing else: an unknown identifier,
# a directory without CBS proof and a symbolic link are refused untouched.
mkdir "$R1/mine"
printf '%s\n' "preexisting" > "$R1/mine/data.txt"
ln -s "$R1/mine" "$R1/linked"
BEFORE_FOREIGN="$(iso_tree_fingerprint "$R1/mine")"

dep_run cleanup "$R1" mine "$FW"
dep_expect CLEANUP_NO_PROOF BLOCKED CLEANUP_REFUSED 149
dep_run cleanup "$R1" linked "$FW"
dep_expect CLEANUP_SYMLINK BLOCKED CLEANUP_REFUSED 149
dep_run cleanup "$R1" ghost "$FW"
dep_expect CLEANUP_UNKNOWN BLOCKED CLEANUP_REFUSED 149

# One refused resource refuses everything: fw stays.
dep_run cleanup "$R1" fw "$FW" mine "$FW"
dep_expect CLEANUP_ALL_OR_NOTHING BLOCKED CLEANUP_REFUSED 149
[[ -d "$R1/fw" ]] || iso_fail "CLEANUP_ALL_OR_NOTHING_REMOVED"

[[ "$(iso_tree_fingerprint "$R1/mine")" == "$BEFORE_FOREIGN" ]] || iso_fail "FOREIGN_DIRECTORY_CHANGED"
[[ -L "$R1/linked" && "$(cat "$R1/mine/data.txt")" == "preexisting" ]] || iso_fail "FOREIGN_LINK_CHANGED"

dep_run cleanup "$R1" fw "$FW"
dep_expect CLEANUP PASS NONE 0
dep_state CLEANUP 1 REMOVED
[[ ! -e "$R1/fw" && ! -L "$R1/fw" ]] || iso_fail "CLEANUP_NOT_REMOVED"
[[ -f "$R1/.cbs-isolation/fw.proof" && -f "$R1/.cbs-isolation/fw.cleaned" ]] || iso_fail "CLEANUP_EVIDENCE"
[[ -d "$R1/consumer1" ]] || iso_fail "CLEANUP_CONSUMER_REMOVED"
[[ -z "$(git -C "$FW" worktree list --porcelain | grep -F "$R1/fw" || true)" ]] || iso_fail "CLEANUP_WORKTREE_STILL_REGISTERED"
assert_sources_untouched CLEANUP

# The identifier is burnt (isolation contract): refused before any creation.
dep_run prepare consumer1 "$CONSUMER" "$R1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect BURNT BLOCKED DEPENDENCY_CONFLICT 146
[[ ! -e "$R1/fw" && ! -L "$R1/fw" ]] || iso_fail "BURNT_CREATED"

# The consumer isolation is cleaned by the manager, as before.
iso_run cleanup consumer1 "$CONSUMER" "$R1"
iso_expect_pass "CONSUMER_CLEANUP"
assert_sources_untouched CONSUMER_CLEANUP

echo "${TEST_PREFIX}_CLEANUP=PASS"

# ---------------------------------------------------------------- 7. several repositories, partial failure

MANIFEST_TWO='name: consumer_app
dependencies:
  pkg_a:
    path: ../fw/packages/pkg_a
  other_pkg:
    path: ../other/pkg
'

R2="$(new_root root2)"
make_consumer "$R2" consumer2 "$MANIFEST_TWO"

dep_run prepare consumer2 "$CONSUMER" "$R2" \
    fw "$FW" "$FW_ORIGIN" "$FW_C1" other "$OTHER" "$OTHER_ORIGIN" "$OTHER_C1"
dep_expect TWO PASS NONE 0
dep_state TWO 1 CREATED
dep_state TWO 2 CREATED
[[ "$(dep_value DEPENDENCY_COUNT)" == "2" ]] || iso_fail "TWO_COUNT"
[[ -f "$R2/fw/packages/pkg_a/pubspec.yaml" && -f "$R2/other/pkg/pubspec.yaml" ]] || iso_fail "TWO_PACKAGES"
assert_no_symlink "$R2" TWO

AFTER_TWO="$(iso_tree_fingerprint "$R2")"
dep_run prepare consumer2 "$CONSUMER" "$R2" \
    fw "$FW" "$FW_ORIGIN" "$FW_C1" other "$OTHER" "$OTHER_ORIGIN" "$OTHER_C1"
dep_expect TWO_AGAIN PASS NONE 0
dep_state TWO_AGAIN 1 REUSED
dep_state TWO_AGAIN 2 REUSED
[[ "$(iso_tree_fingerprint "$R2")" == "$AFTER_TWO" ]] || iso_fail "TWO_AGAIN_ROOT_CHANGED"

dep_run cleanup "$R2" fw "$FW" other "$OTHER"
dep_expect TWO_CLEANUP PASS NONE 0
dep_state TWO_CLEANUP 1 REMOVED
dep_state TWO_CLEANUP 2 REMOVED
[[ ! -e "$R2/fw" && ! -e "$R2/other" ]] || iso_fail "TWO_CLEANUP_LEFT"
iso_run cleanup consumer2 "$CONSUMER" "$R2"
iso_expect_pass "TWO_CONSUMER_CLEANUP"

# Partial failure: the second repository cannot be materialized (wrong origin).
R3="$(new_root root3)"
make_consumer "$R3" consumer3 "$MANIFEST_TWO"

dep_run prepare consumer3 "$CONSUMER" "$R3" \
    fw "$FW" "$FW_ORIGIN" "$FW_C1" other "$OTHER" "https://example.invalid/cbs/wrong.git" "$OTHER_C1"
dep_expect PARTIAL FAIL MATERIALIZATION_FAILED 151
dep_state PARTIAL 1 CREATED
dep_state PARTIAL 2 MISSING
[[ -d "$R3/fw" && ! -e "$R3/other" && ! -L "$R3/other" ]] || iso_fail "PARTIAL_STATE"

# Rerun with the right origin: what exists is reused, the rest is created.
dep_run prepare consumer3 "$CONSUMER" "$R3" \
    fw "$FW" "$FW_ORIGIN" "$FW_C1" other "$OTHER" "$OTHER_ORIGIN" "$OTHER_C1"
dep_expect PARTIAL_RERUN PASS NONE 0
dep_state PARTIAL_RERUN 1 REUSED
dep_state PARTIAL_RERUN 2 CREATED

dep_run cleanup "$R3" fw "$FW" other "$OTHER"
dep_expect PARTIAL_CLEANUP PASS NONE 0
iso_run cleanup consumer3 "$CONSUMER" "$R3"
iso_expect_pass "PARTIAL_CONSUMER_CLEANUP"
assert_sources_untouched MULTI

echo "${TEST_PREFIX}_MULTIPLE=PASS"

# ---------------------------------------------------------------- 8. preexisting data at the sibling path

R4="$(new_root root4)"
make_consumer "$R4" consumer4 "$MANIFEST_MAIN"

mkdir "$R4/fw"
printf '%s\n' "preexisting" > "$R4/fw/keep.txt"
BEFORE_FOREIGN="$(iso_tree_fingerprint "$R4/fw")"

dep_run prepare consumer4 "$CONSUMER" "$R4" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect FOREIGN_DIR BLOCKED DEPENDENCY_CONFLICT 146
dep_state FOREIGN_DIR 1 CONFLICT
dep_run cleanup "$R4" fw "$FW"
dep_expect FOREIGN_DIR_CLEANUP BLOCKED CLEANUP_REFUSED 149
[[ "$(iso_tree_fingerprint "$R4/fw")" == "$BEFORE_FOREIGN" ]] || iso_fail "FOREIGN_DIR_CHANGED"

rm -f "$R4/fw/keep.txt"
rmdir "$R4/fw"

mkdir "$TMP/outside-target"
printf '%s\n' "outside" > "$TMP/outside-target/data.txt"
ln -s "$TMP/outside-target" "$R4/fw"

dep_run prepare consumer4 "$CONSUMER" "$R4" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect FOREIGN_LINK BLOCKED DEPENDENCY_CONFLICT 146
[[ -L "$R4/fw" && "$(cat "$TMP/outside-target/data.txt")" == "outside" ]] || iso_fail "FOREIGN_LINK_CHANGED"

# A dangling link counts as existing too.
rm -f "$R4/fw"
ln -s "$TMP/does-not-exist" "$R4/fw"
dep_run prepare consumer4 "$CONSUMER" "$R4" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect DANGLING_LINK BLOCKED DEPENDENCY_CONFLICT 146
[[ -L "$R4/fw" ]] || iso_fail "DANGLING_LINK_CHANGED"
rm -f "$R4/fw"

iso_run cleanup consumer4 "$CONSUMER" "$R4"
iso_expect_pass "FOREIGN_CONSUMER_CLEANUP"
assert_sources_untouched FOREIGN

echo "${TEST_PREFIX}_PREEXISTING_DATA=PASS"

# ---------------------------------------------------------------- 9. manifests that are refused or need nothing

R5="$(new_root root5)"

manifest_case() {
    # $1 label, $2 pubspec content, $3 RESULT, $4 REASON, $5 rc, remaining: extra arguments
    local label="$1"
    local content="$2"
    local result="$3"
    local reason="$4"
    local rc="$5"

    shift 5
    make_consumer "$R5" "iso-$label" "$content"
    BEFORE_ROOT="$(iso_tree_fingerprint "$R5")"

    if [[ "$#" -gt 0 ]]; then
        dep_run prepare "iso-$label" "$CONSUMER" "$R5" "$@"
    else
        dep_run prepare "iso-$label" "$CONSUMER" "$R5" fw "$FW" "$FW_ORIGIN" "$FW_C1"
    fi

    dep_expect "MANIFEST_$label" "$result" "$reason" "$rc"
    [[ "$(iso_tree_fingerprint "$R5")" == "$BEFORE_ROOT" ]] || iso_fail "MANIFEST_${label}_ROOT_CHANGED"
}

manifest_case outside 'name: app
dependencies:
  x:
    path: ../../outside/pkg
' BLOCKED MANIFEST_UNSUPPORTED 143

manifest_case absolute 'name: app
dependencies:
  x:
    path: /opt/pkg
' BLOCKED MANIFEST_UNSUPPORTED 143

manifest_case flow 'name: app
dependencies: {x: {path: ../fw/packages/pkg_a}}
' BLOCKED MANIFEST_UNSUPPORTED 143

manifest_case emptypath 'name: app
dependencies:
  x:
    path:
' BLOCKED MANIFEST_UNSUPPORTED 143

manifest_case charset 'name: app
dependencies:
  x:
    path: "../fw/pk g"
' BLOCKED MANIFEST_UNSUPPORTED 143

manifest_case internalmissing 'name: app
dependencies:
  x:
    path: packages/missing
' FAIL PACKAGE_INVALID 150

BEFORE_ROOT="$(iso_tree_fingerprint "$R5")"

# No external path: nothing to prepare, nothing created, a PASS that says so.
make_consumer "$R5" iso-none 'name: app
dependencies:
  flutter:
    sdk: flutter
  local_pkg:
    path: packages/local_pkg
'
dep_run prepare iso-none "$CONSUMER" "$R5"
dep_expect NOTHING_TO_PREPARE PASS NONE 0
[[ "$(dep_value DEPENDENCY_COUNT)" == "0" && "$(dep_value EXTERNAL_COUNT)" == "0" && "$(dep_value INTERNAL_COUNT)" == "1" ]] || iso_fail "NOTHING_COUNTS"
dep_run verify iso-none "$CONSUMER" "$R5"
dep_expect NOTHING_TO_VERIFY PASS NONE 0

# A mapping given while nothing is needed is refused.
dep_run prepare iso-none "$CONSUMER" "$R5" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect NOTHING_UNUSED BLOCKED MAPPING_UNUSED 145
[[ ! -e "$R5/fw" ]] || iso_fail "NOTHING_UNUSED_CREATED"

echo "${TEST_PREFIX}_MANIFESTS=PASS"

# ---------------------------------------------------------------- 10. a package whose own path dependency escapes

MANIFEST_BAD='name: app
dependencies:
  pkg_n:
    path: ../bad/packages/pkg_n
'

R6="$(new_root root6)"
make_consumer "$R6" consumer6 "$MANIFEST_BAD"

dep_run prepare consumer6 "$CONSUMER" "$R6" bad "$BAD" "$BAD_ORIGIN" "$BAD_C1"
dep_expect NESTED FAIL PACKAGE_INVALID 150
[[ "$(dep_value DETAIL)" == "NESTED_PATH_NOT_RESOLVABLE" ]] || iso_fail "NESTED_DETAIL_$(dep_value DETAIL)"

# The resource stays (owned, clean) and is cleaned explicitly.
dep_run cleanup "$R6" bad "$BAD"
dep_expect NESTED_CLEANUP PASS NONE 0
iso_run cleanup consumer6 "$CONSUMER" "$R6"
iso_expect_pass "NESTED_CONSUMER_CLEANUP"

echo "${TEST_PREFIX}_NESTED_PATHS=PASS"

# ---------------------------------------------------------------- 11. the consumer is verified, not trusted

R7="$(new_root root7)"
make_consumer "$R7" consumer7 "$MANIFEST_MAIN"

dep_run prepare unknown-consumer "$CONSUMER" "$R7" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect CONSUMER_UNKNOWN BLOCKED CONSUMER_REJECTED 142

printf '%s\n' "dirt" > "$R7/consumer7/untracked.txt"
dep_run prepare consumer7 "$CONSUMER" "$R7" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect CONSUMER_DIRTY BLOCKED CONSUMER_REJECTED 142
[[ ! -e "$R7/fw" && "$(cat "$R7/consumer7/untracked.txt")" == "dirt" ]] || iso_fail "CONSUMER_DIRTY_EFFECT"
rm -f "$R7/consumer7/untracked.txt"

# A manifest modified after the isolation is refused (dirty checkout).
printf '%s\n' "# edited" >> "$R7/consumer7/pubspec.yaml"
dep_run prepare consumer7 "$CONSUMER" "$R7" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect CONSUMER_EDITED BLOCKED CONSUMER_REJECTED 142
git -C "$R7/consumer7" checkout -q -- pubspec.yaml

dep_run prepare consumer7 "$CONSUMER" "$R7" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect CONSUMER_RESTORED PASS NONE 0
dep_run cleanup "$R7" fw "$FW"
dep_expect CONSUMER_RESTORED_CLEANUP PASS NONE 0
iso_run cleanup consumer7 "$CONSUMER" "$R7"
iso_expect_pass "CONSUMER_RESTORED_CONSUMER_CLEANUP"

echo "${TEST_PREFIX}_CONSUMER_GATE=PASS"

# ---------------------------------------------------------------- 12. arguments are data

R8="$(new_root root8)"
make_consumer "$R8" consumer8 "$MANIFEST_MAIN"
BEFORE_ROOT="$(iso_tree_fingerprint "$R8")"
SECRET_ORIGIN="https://builder:hunter2secret@example.invalid/cbs/framework.git"

dep_run prepare consumer8 "$CONSUMER" "$R8" fw "$FW" "$SECRET_ORIGIN" "$FW_C1"
dep_expect SECRET_ORIGIN BLOCKED INPUT_INVALID 140
if printf '%s\n%s\n' "$DEP_OUT" "$DEP_ERR" | grep -F -e "hunter2secret" -e "builder" >/dev/null; then
    iso_fail "SECRET_ECHOED"
fi

dep_run prepare consumer8 "$CONSUMER" "$R8" fw "$FW" "$FW_ORIGIN" "abc123"
dep_expect SHORT_COMMIT BLOCKED INPUT_INVALID 140

dep_run prepare consumer8 "$CONSUMER" "$R8" fw "$FW" "$FW_ORIGIN" "$(printf '%s' "$FW_C1" | tr 'a-f' 'A-F')"
dep_expect UPPER_COMMIT BLOCKED INPUT_INVALID 140

dep_run prepare consumer8 "$CONSUMER" "$R8" "../fw" "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect NAME_TRAVERSAL BLOCKED INPUT_INVALID 140

dep_run prepare consumer8 "$CONSUMER" "$R8" 'fw;touch$IFS/tmp/pwned' "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect NAME_INJECTION BLOCKED INPUT_INVALID 140
[[ ! -e /tmp/pwned ]] || iso_fail "INJECTION_EXECUTED"

dep_run prepare consumer8 "$CONSUMER" "$R8" consumer8 "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect NAME_IS_CONSUMER BLOCKED INPUT_INVALID 140

dep_run prepare consumer8 "$CONSUMER" "$R8" fw "$FW" "$FW_ORIGIN" "$FW_C1" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect NAME_DUPLICATE BLOCKED INPUT_INVALID 140

dep_run prepare consumer8 "$CONSUMER" "relative/root" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect ROOT_RELATIVE BLOCKED INPUT_INVALID 140

dep_run prepare consumer8 "$CONSUMER" "$R8/../root8" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect ROOT_DOTDOT BLOCKED INPUT_INVALID 140

ln -s "$R8" "$TMP/root8-link"
dep_run prepare consumer8 "$CONSUMER" "$TMP/root8-link" fw "$FW" "$FW_ORIGIN" "$FW_C1"
dep_expect ROOT_SYMLINK BLOCKED INPUT_INVALID 140

dep_run prepare consumer8 "$CONSUMER" "$R8" fw "$R8/inside" "$FW_ORIGIN" "$FW_C1"
dep_expect SOURCE_INSIDE_ROOT BLOCKED INPUT_INVALID 140

dep_run prepare consumer8 "$CONSUMER" "$R8" fw "$FW" "$FW_ORIGIN" ""
dep_expect EMPTY_COMMIT BLOCKED INPUT_INVALID 140

# Nothing was created by any refused request.
[[ "$(iso_tree_fingerprint "$R8")" == "$BEFORE_ROOT" ]] || iso_fail "ARGUMENTS_ROOT_CHANGED"

dep_run cleanup "relative/root" fw "$FW"
dep_expect CLEANUP_ROOT_RELATIVE BLOCKED INPUT_INVALID 140
dep_run cleanup "$R8" "../fw" "$FW"
dep_expect CLEANUP_NAME_TRAVERSAL BLOCKED INPUT_INVALID 140

iso_run cleanup consumer8 "$CONSUMER" "$R8"
iso_expect_pass "ARGUMENTS_CONSUMER_CLEANUP"

echo "${TEST_PREFIX}_ARGUMENTS=PASS"

# ---------------------------------------------------------------- 13. structure of the script

SCRIPT_CODE="$(grep -Ev '^[[:space:]]*#' "$DEPS" || true)"

forbid() {
    if printf '%s\n' "$SCRIPT_CODE" | grep -E -e "$2" >/dev/null; then
        iso_fail "STRUCTURE_$1"
    fi
}

forbid SYMLINK '(^|[^A-Za-z_])ln[[:space:]]'
forbid RECURSIVE_DELETE 'rm[[:space:]]+-[a-zA-Z]*[rR]'
forbid ANY_DELETE '(^|[;&|({[:space:]])(rm|rmdir|unlink|shred)[[:space:]]'
forbid GIT_RESET_CLEAN 'git[^|]*[[:space:]](reset|clean|checkout|stash|gc|prune|push|fetch|pull|clone|remote[[:space:]]+(add|set-url|remove))'
forbid FORCE 'git[^|]*[[:space:]](--force|-f|-ff)([[:space:]]|$)'
forbid NETWORK '(^|[^A-Za-z_])(curl|wget|ssh|scp|rsync|nc)[[:space:]]'
forbid EVAL '(^|[;&|({[:space:]])eval[[:space:]]'
forbid FLUTTER_TOOLS '(^|[^A-Za-z_])(flutter|dart|pub|xcodebuild|xcrun)[[:space:]]'
forbid MKDIR_OR_COPY '(^|[;&|({[:space:]])(mkdir|cp|mv|touch|install|chmod|chown)[[:space:]]'

# The only file sourced is the qualification contract of this directory.
SOURCES="$(printf '%s\n' "$SCRIPT_CODE" | grep -E '^[[:space:]]*(source|\.)[[:space:]]' || true)"
[[ "$SOURCES" == '    '*'source "$CBS_FLUTTER_DEPS_DIR/contract.sh"' || "$SOURCES" == 'source "$CBS_FLUTTER_DEPS_DIR/contract.sh"' ]] ||
    iso_fail "STRUCTURE_SOURCES_$SOURCES"

# The isolation manager is the only way to create or remove a resource.
printf '%s\n' "$SCRIPT_CODE" | grep -F 'isolation_manager.sh' >/dev/null || iso_fail "STRUCTURE_NO_MANAGER"
printf '%s\n' "$SCRIPT_CODE" | grep -E 'worktree[[:space:]]+(add|remove)' >/dev/null && iso_fail "STRUCTURE_DIRECT_WORKTREE"
echo "${TEST_PREFIX}_STRUCTURE=PASS"

echo "${TEST_PREFIX}_RESULT=PASS"
