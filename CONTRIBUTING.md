# Contributing

## Development setup

Fork `bitflyer-tools/bitflyer-cli` on GitHub and clone your fork. From the
repository root, use the Ruby version in `.ruby-version` and install
the Bundler version recorded in `Gemfile.lock`.

```sh
gem install bundler -v 4.1.0
bundle install
```

## Checks

Run the same commands as CI from the repository root.

```sh
bundle exec rspec
bundle exec rubocop
gem build bitflyer-cli.gemspec
```

The specs use client doubles and run without bitFlyer API credentials.

CI runs RSpec on Ruby 3.3 with the default bundle. To run the
coverage check used on Ruby 3.3 and 3.4, use the coverage Gemfile:

```sh
BUNDLE_GEMFILE=gemfiles/with_coverage/Gemfile bundle install
BUNDLE_GEMFILE=gemfiles/with_coverage/Gemfile COVERAGE=true bundle exec rspec
```

When changing shared dependencies, update both lockfiles.

## Pull requests

Create a branch for your change. Add or update specs when changing behavior,
and update any documentation affected by the change. Run the checks before
pushing your branch to your fork.

Open a pull request against `bitflyer-tools/bitflyer-cli` with a Conventional
Commit title, such as `docs: clarify installation instructions`. Describe what
changed, why, and which checks you ran. Follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
