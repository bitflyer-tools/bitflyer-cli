#!/usr/bin/env bash
set -euo pipefail

release_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
version=$1
shift

export BUNDLE_GEMFILE="$release_dir/Gemfile"
export BUNDLE_PATH="$release_dir/../../tmp/release-bundle"
export BUNDLE_FROZEN=true

bundle install
bundle exec gem bump --version "$version" "$@"
