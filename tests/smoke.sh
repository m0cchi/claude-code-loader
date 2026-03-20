#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CCLOADER="${ROOT_DIR}/ccloader"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "${expected}" != "${actual}" ]]; then
    printf 'assertion failed: %s\nexpected: %s\nactual: %s\n' "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_exists() {
  local path="$1"
  if [[ ! -e "${path}" && ! -L "${path}" ]]; then
    printf 'expected path to exist: %s\n' "${path}" >&2
    exit 1
  fi
}

make_repo() {
  local repo_dir="$1"
  mkdir -p "${repo_dir}"
  git init "${repo_dir}" >/dev/null 2>&1
  git -C "${repo_dir}" config user.name "Test User"
  git -C "${repo_dir}" config user.email "test@example.com"
}

commit_all() {
  local repo_dir="$1"
  local message="$2"
  git -C "${repo_dir}" add .
  git -C "${repo_dir}" commit -m "${message}" >/dev/null 2>&1
}

test_add_and_load() {
  local home_dir="${TMP_DIR}/home-add-load"
  local remote_repo="${TMP_DIR}/remote-with-claude"
  local workspace="${TMP_DIR}/workspace"

  mkdir -p "${home_dir}" "${workspace}/project/.claude"
  make_repo "${remote_repo}"
  mkdir -p "${remote_repo}/.claude/skills" "${remote_repo}/.claude/agents"
  printf 'skill body\n' > "${remote_repo}/.claude/skills/demo.md"
  printf 'agent body\n' > "${remote_repo}/.claude/agents/demo.md"
  commit_all "${remote_repo}" "initial"

  HOME="${home_dir}" "${CCLOADER}" add demo "${remote_repo}" >/dev/null
  assert_exists "${home_dir}/.claude-code-loader/repositories/demo/.git"

  (
    cd "${workspace}/project"
    printf '1 2\n' | HOME="${home_dir}" "${CCLOADER}" load demo >/dev/null
  )

  assert_exists "${workspace}/project/.claude/skills"
  assert_exists "${workspace}/project/.claude/agents"
  assert_eq \
    "${home_dir}/.claude-code-loader/repositories/demo/.claude/skills" \
    "$(readlink "${workspace}/project/.claude/skills")" \
    "skills symlink target"
  assert_eq \
    "${home_dir}/.claude-code-loader/repositories/demo/.claude/agents" \
    "$(readlink "${workspace}/project/.claude/agents")" \
    "agents symlink target"
}

test_load_all() {
  local home_dir="${TMP_DIR}/home-load-all"
  local remote_repo="${TMP_DIR}/remote-load-all"
  local workspace="${TMP_DIR}/workspace-load-all"

  mkdir -p "${home_dir}" "${workspace}/project/.claude"
  make_repo "${remote_repo}"
  mkdir -p "${remote_repo}/.claude/skills" "${remote_repo}/.claude/agents"
  printf 'skill body\n' > "${remote_repo}/.claude/skills/demo.md"
  printf 'agent body\n' > "${remote_repo}/.claude/agents/demo.md"
  commit_all "${remote_repo}" "initial"

  HOME="${home_dir}" "${CCLOADER}" add demo "${remote_repo}" >/dev/null
  (
    cd "${workspace}/project"
    HOME="${home_dir}" "${CCLOADER}" load --all demo >/dev/null
  )

  assert_exists "${workspace}/project/.claude/skills"
  assert_exists "${workspace}/project/.claude/agents"
}

test_add_without_claude_warns() {
  local home_dir="${TMP_DIR}/home-no-claude"
  local remote_repo="${TMP_DIR}/remote-no-claude"

  mkdir -p "${home_dir}"
  make_repo "${remote_repo}"
  printf 'plain repo\n' > "${remote_repo}/README.md"
  commit_all "${remote_repo}" "initial"

  local output
  output="$(HOME="${home_dir}" "${CCLOADER}" add plain "${remote_repo}" 2>&1 >/dev/null)"
  assert_exists "${home_dir}/.claude-code-loader/repositories/plain/.git"
  [[ "${output}" == *"does not contain a .claude directory"* ]] || {
    printf 'expected warning output, got: %s\n' "${output}" >&2
    exit 1
  }
}

test_update_reports_failures() {
  local home_dir="${TMP_DIR}/home-update"
  local remote_repo="${TMP_DIR}/remote-update"
  local clone_dir="${home_dir}/.claude-code-loader/repositories/demo"

  mkdir -p "${home_dir}"
  make_repo "${remote_repo}"
  mkdir -p "${remote_repo}/.claude/skills"
  printf 'v1\n' > "${remote_repo}/.claude/skills/demo.md"
  commit_all "${remote_repo}" "initial"

  HOME="${home_dir}" "${CCLOADER}" add demo "${remote_repo}" >/dev/null

  mkdir -p "${home_dir}/.claude-code-loader/repositories/not-a-repo"

  local output
  set +e
  output="$(HOME="${home_dir}" "${CCLOADER}" update 2>&1)"
  local status=$?
  set -e

  assert_eq "1" "${status}" "update exit code with failure"
  [[ "${output}" == *"Updated: demo"* ]] || {
    printf 'expected success summary, got: %s\n' "${output}" >&2
    exit 1
  }
  [[ "${output}" == *"not-a-repo"* ]] || {
    printf 'expected failure summary, got: %s\n' "${output}" >&2
    exit 1
  }

  assert_exists "${clone_dir}/.git"
}

test_load_conflict_fails_without_partial_links() {
  local home_dir="${TMP_DIR}/home-conflict"
  local remote_repo="${TMP_DIR}/remote-conflict"
  local workspace="${TMP_DIR}/workspace-conflict"

  mkdir -p "${home_dir}" "${workspace}/project/.claude"
  make_repo "${remote_repo}"
  mkdir -p "${remote_repo}/.claude/skills" "${remote_repo}/.claude/agents"
  printf 'skill body\n' > "${remote_repo}/.claude/skills/demo.md"
  printf 'agent body\n' > "${remote_repo}/.claude/agents/demo.md"
  commit_all "${remote_repo}" "initial"

  HOME="${home_dir}" "${CCLOADER}" add demo "${remote_repo}" >/dev/null
  mkdir -p "${workspace}/project/.claude/skills"

  local output
  set +e
  output="$(
    cd "${workspace}/project" &&
      printf '1 2\n' | HOME="${home_dir}" "${CCLOADER}" load demo 2>&1
  )"
  local status=$?
  set -e

  assert_eq "1" "${status}" "load exit code on conflict"
  [[ "${output}" == *"Target already exists"* ]] || {
    printf 'expected conflict output, got: %s\n' "${output}" >&2
    exit 1
  }
  if [[ -L "${workspace}/project/.claude/agents" ]]; then
    printf 'expected agents link not to be created on conflict\n' >&2
    exit 1
  fi
}

test_load_without_target_claude_fails() {
  local home_dir="${TMP_DIR}/home-no-target"
  local remote_repo="${TMP_DIR}/remote-no-target"
  local workspace="${TMP_DIR}/workspace-no-target"

  mkdir -p "${home_dir}" "${workspace}/project"
  make_repo "${remote_repo}"
  mkdir -p "${remote_repo}/.claude/skills"
  printf 'skill body\n' > "${remote_repo}/.claude/skills/demo.md"
  commit_all "${remote_repo}" "initial"

  HOME="${home_dir}" "${CCLOADER}" add demo "${remote_repo}" >/dev/null

  local output
  set +e
  output="$(
    cd "${workspace}/project" &&
      printf '1\n' | HOME="${home_dir}" "${CCLOADER}" load demo 2>&1
  )"
  local status=$?
  set -e

  assert_eq "1" "${status}" "load exit code without target .claude"
  [[ "${output}" == *"No .claude directory found"* ]] || {
    printf 'expected no-target output, got: %s\n' "${output}" >&2
    exit 1
  }
}

test_load_without_entries_fails() {
  local home_dir="${TMP_DIR}/home-no-entries"
  local remote_repo="${TMP_DIR}/remote-no-entries"
  local workspace="${TMP_DIR}/workspace-no-entries"

  mkdir -p "${home_dir}" "${workspace}/project/.claude"
  make_repo "${remote_repo}"
  mkdir -p "${remote_repo}/.claude/.gitkeep-dir"
  printf 'keep\n' > "${remote_repo}/.claude/.gitkeep-dir/keep.txt"
  commit_all "${remote_repo}" "initial"

  HOME="${home_dir}" "${CCLOADER}" add demo "${remote_repo}" >/dev/null

  local output
  set +e
  output="$(
    cd "${workspace}/project" &&
      HOME="${home_dir}" "${CCLOADER}" load --all demo 2>&1
  )"
  local status=$?
  set -e

  assert_eq "1" "${status}" "load exit code without entries"
  [[ "${output}" == *"No entries found"* ]] || {
    printf 'expected no-entries output, got: %s\n' "${output}" >&2
    exit 1
  }
}

test_add_and_load
test_load_all
test_add_without_claude_warns
test_update_reports_failures
test_load_conflict_fails_without_partial_links
test_load_without_target_claude_fails
test_load_without_entries_fails

printf 'smoke tests passed\n'
