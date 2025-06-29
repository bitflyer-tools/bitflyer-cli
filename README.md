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

Set the `BITFLYER_API_TOKEN` and `BITFLYER_API_SECRET` environment variable.

```sh
export BITFLYER_API_TOKEN=your-bitflyer-api-token
export BITFLYER_API_SECRET=your-bitflyer-api-secret
```

## Usage

```
Commands:
  bitflyer cancel_all                                          # cancel all of orders
  bitflyer counter_trade                                       # clear all positions
  bitflyer help [COMMAND]                                      # Describe available commands or one specific command
  bitflyer order_by_best -a=amount -t=buy/sell                 # create limit order by best price in the board
  bitflyer order_by_twap -a=amount -i=second -n=N -t=buy/sell  # trade specified amount N times at specified intervals (TWAP algorithm).
  bitflyer stop_by_range r, --range=price range                # create stop order by range based on current position
  bitflyer summary                                             # show current balance information
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/unhappychoice/bitflyer-cli. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

