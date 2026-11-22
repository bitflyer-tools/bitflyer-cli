# bitflyer-cli
[![Gem Version](https://badge.fury.io/rb/bitflyer-cli.svg)](https://badge.fury.io/rb/bitflyer-cli)
[![test](https://github.com/bitflyer-tools/bitflyer-cli/actions/workflows/test.yml/badge.svg)](https://github.com/bitflyer-tools/bitflyer-cli/actions/workflows/test.yml)
[![Code Climate](https://codeclimate.com/github/bitflyer-tools/bitflyer-cli/badges/gpa.svg)](https://codeclimate.com/github/bitflyer-tools/bitflyer-cli)
![Libraries.io dependency status for GitHub repo](https://img.shields.io/librariesio/github/bitflyer-tools/bitflyer-cli.svg)
![](http://ruby-gem-downloads-badge.herokuapp.com/bitflyer-cli?type=total)
![GitHub](https://img.shields.io/github/license/bitflyer-tools/bitflyer-cli.svg)

bitflyer-cli is a command-line tool for the BTC-CFD/JPY market on
[bitFlyer Crypto CFD](https://lightning.bitflyer.com/docs?lang=en#api-documentation).
This market uses `FX_BTC_JPY` as its API product code.

## Installation

Requires Ruby 3.3 or later.

```sh
gem install bitflyer-cli
```

## Quick start

Set the `BITFLYER_API_KEY` and `BITFLYER_API_SECRET` environment variables
using a bitFlyer API key with permission to read positions and collateral.

```sh
export BITFLYER_API_KEY=your-bitflyer-api-key
export BITFLYER_API_SECRET=your-bitflyer-api-secret
```

Run the account summary to view your position and balance alongside the live
`FX_BTC_JPY` execution price. This command only reads market and account data.

```sh
bitflyer summary
```

Press `Ctrl+C` to exit the live display.

See [Getting started](docs/getting-started.md) for a walkthrough of the
summary display and open orders.

## Usage

```
Commands:
  bitflyer cancel_all                                          # cancel all of orders
  bitflyer cancel_order TYPE ID [--confirm-parent]             # request cancellation of one order
  bitflyer counter_trade                                       # offset nonzero net exposure with a market order
  bitflyer executions                                          # show recent account executions
  bitflyer help [COMMAND]                                      # Describe available commands or one specific command
  bitflyer ifdoco_by_range --amount=0.01 --type=buy --range=10000 --percentage=60  # create IFDOCO order by range based on current price
  bitflyer open_orders                                         # show active child orders and parent strategies
  bitflyer order_by_best -a=amount -t=buy/sell                 # create limit order by best price in the board
  bitflyer order_by_twap -a=amount -i=second -n=N -t=buy/sell  # trade specified amount N times at specified intervals (TWAP algorithm).
  bitflyer stop_by_range --range=5000                          # create stop order by range based on current position
  bitflyer summary                                             # show current balance information
```

### Preview an order plan

```sh
bitflyer ifdoco_by_range --amount=0.01 --type=buy --range=10000 --percentage=60 --dry-run
bitflyer order_by_twap --amount=0.01 --type=buy --number-of-times=3 --interval=10 --dry-run
```

Both commands validate the inputs and print a local plan without trading
credentials or order submission. IFDOCO reads the current public ticker and
shows the reference price and all three legs, including the rounded exit prices.
A later invocation fetches a fresh ticker and may calculate different prices.
TWAP shows the side, size per slice, slice count, total BTC, interval, and planned
time between the first and last slices. It runs without network access or waits.

### Set a stop by range

`stop_by_range` checks active parent orders before submitting. If it finds a
standalone stop for the same market, side, trigger price, and size, it prints
the existing stop and its parent order ID.

Runs on the same machine and OS account coordinate when they use the same API
key and stop parameters. The CLI tracks accepted stops in a local submission
record. It stores records under
`$XDG_STATE_HOME/bitflyer-cli/stops` (default `~/.local/state/bitflyer-cli/stops`).
If a connection error or HTTP 5xx response leaves acceptance unverified, the CLI
exits with status 1 and prints the submission record's path. A retry also exits
with status 1 while acceptance remains unverified and suppresses resubmission.
Check the order in bitFlyer before retrying. Once you confirm the outcome, remove
the unverified record at the path shown by the CLI. Keep the `.lock` files in place.

The CLI retains a completed stop's record so that a stale position snapshot
cannot trigger a duplicate order with the same parameters. If a new position
needs a stop with those same parameters, verify the new position and the old
stop's completion in bitFlyer, then remove the completed record at the path
shown by the CLI while no `stop_by_range` commands are running.

When reconciling a recorded acceptance ID, the CLI makes up to 10 requests
across terminal parent-order states. If the limit prevents confirmation, the
CLI exits with status 1, reports the record path, and keeps the record to
prevent resubmission.

### Offset a position

`bitflyer counter_trade` coordinates runs for each product on the same machine
when they share an OS account and state directory. The command saves a record
under `$XDG_STATE_HOME/bitflyer-cli/counter-trades` (default
`~/.local/state/bitflyer-cli/counter-trades`) before sending the market order.
A later run uses the original API key to check the previous order and waits for
the position to reflect its fills before sizing another offset. While a record
is pending, runs using other API keys are blocked for that product as well.

If the CLI cannot confirm acceptance, the final order state, or the resulting
exposure, it exits with status 1 and shows the record path. Retry to check the
order and position again. If automatic reconciliation cannot complete, check
in bitFlyer that the order was never accepted or is no longer live and that
the current position reflects all fills. Once confirmed, remove the JSON record
at the displayed path while no `counter_trade` commands are running. Keep the
`.lock` file in place.

### List and cancel open orders

Run `bitflyer open_orders` to see active orders for `FX_BTC_JPY`. The child order list
shows the remaining size after any partial fills. The parent strategy list shows
the strategy type, such as STOP or IFDOCO, and the order date. The list uses the
exchange's default result limit.

Copy the order ID from the relevant section and specify its type explicitly.

```sh
bitflyer cancel_order child JOR20150707-084555-022523
bitflyer cancel_order parent JCO20150925-055555-022222 --confirm-parent
```

Canceling a parent strategy also cancels its associated orders. The required
`--confirm-parent` flag works in scripts without an interactive prompt.
The CLI reports when bitFlyer accepts or rejects the request. Network errors
and HTTP 5xx responses leave acceptance unverified. Rejected and unverified
requests exit unsuccessfully. Run `bitflyer open_orders` again to check the
order's status.

### Review account executions

Run `bitflyer executions` with an API key that has permission to list executions.
The terminal table shows up to 100 recent fills for `FX_BTC_JPY`, with one row
per fill. Each row includes the execution time, side, price, size, commission,
child order ID, and acceptance ID.

Copy the Order ID from the Child orders section of `bitflyer open_orders`, or
copy the `child_order_acceptance_id` printed for an accepted TWAP slice. Pass
one of the IDs to limit the page to fills for that order, even after it leaves
the active order list.

```sh
bitflyer executions
bitflyer executions --child-order-id JOR20150707-084555-022523
bitflyer executions --child-order-acceptance-id JRF20150707-050237-639234
```

An empty page prints `No executions found.` A failed lookup prints an error
to stderr and exits unsuccessfully.

## Troubleshooting

For help with credentials, missing prices, and order status, see
[Troubleshooting](docs/troubleshooting.md).

### TWAP submission results

`--interval` must be finite and between 0 and 2,147,483,647 seconds, inclusive.
The command rejects invalid intervals before sending any slices.

`bitflyer order_by_twap` reports the number of slices accepted, rejected,
unverified, and unattempted. If a transport error, gateway error, or malformed
response leaves a slice's acceptance unverified, the command stops the schedule
without retrying that slice and exits with status 1.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/unhappychoice/bitflyer-cli. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


## Author

[@unhappychoice](https://unhappychoice.com)
