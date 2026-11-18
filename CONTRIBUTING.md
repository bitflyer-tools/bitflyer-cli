# Contributing

## Development setup

Fork `bitflyer-tools/bitflyer-cli` on GitHub and clone your fork. From the
repository root, use Ruby 3.4.4, the version in `.ruby-version`, and install
the Bundler version recorded in `Gemfile.lock`.

```sh
gem install bundler -v 2.6.9
bundle install
```

## Checks

Run the same commands as CI from the repository root.

```sh
bundle exec rspec
bundle exec rubocop
```

The specs use client doubles and run without bitFlyer API credentials.

## Pull requests

Create a branch for your change. Add or update specs when changing behavior,
and update any documentation affected by the change. Run the checks before
pushing your branch to your fork.

Open a pull request against `bitflyer-tools/bitflyer-cli` with a Conventional
Commit title, such as `docs: clarify installation instructions`. Describe what
changed, why, and which checks you ran. Follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
