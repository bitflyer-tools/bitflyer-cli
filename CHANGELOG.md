# Changelog

Notable changes to bitflyer-cli, by release. Dates are UTC and match the
release commit on [GitHub](https://github.com/bitflyer-tools/bitflyer-cli/tags).

## [1.0.3] - 2026-11-07

### Fixed

- `stop_by_range` raised `NoMethodError` because `Position` had no `empty?`
  method.
- `stop_by_range` derived the stop side from the average price, which is
  always positive, so short positions received a `SELL` stop with a negative
  size. The side now follows the sign of the position size.
- `ifdoco_by_range` always raised `ArgumentError` because the parent order
  request was passed as a positional hash instead of keyword arguments.

## [1.0.2] - 2026-02-03

### Changed

- `summary` hides the cursor while it runs and restores it on exit, handles
  `Ctrl+C` cleanly, and reserves enough space for the display so it no longer
  flickers or scrolls.

## [1.0.1] - 2026-02-03

No user-facing changes. Added RuboCop and a lint step in CI.

## [1.0.0] - 2025-06-22

### Changed

- Moved to the `bitflyer` gem's 1.0 API and dropped support for Ruby 2.x.
- Replaced Dependabot's legacy configuration with the GitHub-native format
  and moved CI to GitHub Actions.

## [0.5.0] - 2019-07-14

### Added

- `ifdoco_by_range`: create an IFDOCO strategy (market entry, limit take,
  and stop loss) based on the current ticker price and a range/percentage
  split.

## [0.4.4] - 2019-01-06

### Changed

- Updated the `bitflyer` gem dependency to `~> 0.2.2`.

## [0.4.3] - 2019-01-06

### Fixed

- Updated the `bitflyer` gem dependency to fix the realtime execution feed.

## [0.4.2] - 2018-01-30

### Changed

- Updated the `bitflyer` gem dependency to `~> 0.2.0` and unpinned the
  `rake`/`rspec` development dependency versions.

## [0.4.1] - 2017-08-16

### Fixed

- Fixed flickering in the `summary` display.

## [0.4.0] - 2017-08-12

### Added

- `stop_by_range`: create a protective stop order by range based on the
  current position.

## [0.3.0] - 2017-08-07

### Added

- `order_by_twap`: trade a specified amount a given number of times at
  fixed intervals (TWAP algorithm).

## [0.2.1] - 2017-08-06

### Fixed

- `counter_trade` sent an integer order size instead of a float.
- Fixed the position average price formatting in the `summary` display.

## [0.2.0] - 2017-08-05

### Added

- `cancel_all`: cancel all open orders.

### Changed

- Extracted `HasHTTPClient`, `HasRealtimeClient`, and `Authorization`
  modules shared by the commands.
- Switched position and profit calculations to `BigDecimal`.

## [0.1.2] - 2017-08-04

### Fixed

- `counter_trade` used the signed position size instead of its absolute
  value when sizing the offsetting order.

## [0.1.1] - 2017-08-04

### Fixed

- Rounded the computed position size.

## [0.1.0] - 2017-08-04

### Added

- `order_by_best`: create a limit order at the best bid or ask.
- `counter_trade`: offset the current position with a market order.

## [0.0.2] - 2017-07-28

### Changed

- Updated the `bitflyer` gem dependency to fix the realtime execution feed.

## [0.0.1] - 2017-07-28

### Added

- Initial release: the `summary` command showing live execution price,
  position, and balance.
