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

## Usage

```
Commands:
  bitflyer cancel_all                                          # cancel all of orders
  bitflyer cancel_order TYPE ID [--confirm-parent]             # request cancellation of one order
  bitflyer counter_trade                                       # offset nonzero net exposure with a market order
  bitflyer help [COMMAND]                                      # Describe available commands or one specific command
  bitflyer ifdoco_by_range --amount=0.01 --type=buy --range=10000 --percentage=60  # create IFDOCO order by range based on current price
  bitflyer open_orders                                         # show active child orders and parent strategies
  bitflyer order_by_best -a=amount -t=buy/sell                 # create limit order by best price in the board
  bitflyer order_by_twap -a=amount -i=second -n=N -t=buy/sell  # trade specified amount N times at specified intervals (TWAP algorithm).
  bitflyer stop_by_range --range=5000                          # create stop order by range based on current position
  bitflyer summary                                             # show current balance information
```

`stop_by_range` checks active parent orders before submitting. If it finds a
standalone stop for the same market, side, trigger price, and size, it prints
the existing stop and its parent order ID.

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

For help with credentials, missing prices, and order status, see
[Troubleshooting](docs/troubleshooting.md).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/unhappychoice/bitflyer-cli. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


## Author

[@unhappychoice](https://unhappychoice.com)
