# bitflyer-cli
[![Gem Version](https://badge.fury.io/rb/bitflyer-cli.svg)](https://badge.fury.io/rb/bitflyer-cli)
[![Circle CI](https://circleci.com/gh/bitflyer-tools/bitflyer-cli.svg?style=shield)](https://circleci.com/gh/bitflyer-tools/bitflyer-cli)
[![Code Climate](https://codeclimate.com/github/bitflyer-tools/bitflyer-cli/badges/gpa.svg)](https://codeclimate.com/github/bitflyer-tools/bitflyer-cli)
![Libraries.io dependency status for GitHub repo](https://img.shields.io/librariesio/github/bitflyer-tools/bitflyer-cli.svg)
![](http://ruby-gem-downloads-badge.herokuapp.com/bitflyer-cli?type=total)
![GitHub](https://img.shields.io/github/license/bitflyer-tools/bitflyer-cli.svg)

bitflyer-cli is a CLI tool for [Bitflyer](https://bitflyer.jp/) FXBTC.

## Installation

```sh
gem install bitflyer-cli
```

Set the `BITFLYER_API_KEY` and `BITFLYER_API_SECRET` environment variables.

```sh
export BITFLYER_API_KEY=your-bitflyer-api-key
export BITFLYER_API_SECRET=your-bitflyer-api-secret
```

## Usage

```
Commands:
  bitflyer cancel_all                                          # cancel all of orders
  bitflyer cancel_order TYPE ID [--confirm-parent]             # request cancellation of one order
  bitflyer counter_trade                                       # clear all positions
  bitflyer help [COMMAND]                                      # Describe available commands or one specific command
  bitflyer open_orders                                         # show active child orders and parent strategies
  bitflyer order_by_best -a=amount -t=buy/sell                 # create limit order by best price in the board
  bitflyer order_by_twap -a=amount -i=second -n=N -t=buy/sell  # trade specified amount N times at specified intervals (TWAP algorithm).
  bitflyer stop_by_range r, --range=price range                # create stop order by range based on current position
  bitflyer summary                                             # show current balance information
```

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
The CLI reports when bitFlyer accepts the request and exits unsuccessfully on
rejection. Run `bitflyer open_orders` again to check the order's status.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/unhappychoice/bitflyer-cli. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).


## Author

[@unhappychoice](https://unhappychoice.com)
