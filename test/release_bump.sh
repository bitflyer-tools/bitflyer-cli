#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
mkdir -p "$root/tmp"
fixture=$(mktemp -d "$root/tmp/release-test.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

git clone --quiet --local --no-hardlinks "$root" "$fixture"
cd "$fixture"

current_version() {
  ruby -Ilib -rbitflyer/cli/version -e 'puts Bitflyer::Cli::VERSION'
}

version_file=lib/bitflyer/cli/version.rb
IFS=. read -r major minor patch <<< "$(current_version)"

check_bump() {
  local release_type=$1 expected=$2 actual
  bash "$root/.github/release/bump.sh" "$release_type" --no-commit
  actual=$(current_version)
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected $release_type bump to produce $expected, got $actual" >&2
    exit 1
  fi

  git restore -- "$version_file"
}

check_bump major "$((major + 1)).0.0"
check_bump minor "$major.$((minor + 1)).0"
check_bump patch "$major.$minor.$((patch + 1))"
