# Command reference

All market and account operations use the BTC-CFD/JPY product
(`FX_BTC_JPY`). Run `bitflyer help` for the command list or
`bitflyer help COMMAND` for the options of a specific command.

## Read market and account data

| Command | Result |
| --- | --- |
| `bitflyer summary` | Live execution price, net position, spread, and estimated balance. Press Ctrl+C to exit. |
| `bitflyer open_orders` | Active child orders and parent strategies. |
| `bitflyer executions` | Up to 100 recent account fills. Use either `--child-order-id ID` or `--child-order-acceptance-id ID` to filter by order. Add `--all` to page through the full history, and `--export PATH` to write CSV instead of a table. |

## Submit or cancel orders

| Command | Required arguments and options | Effect |
| --- | --- | --- |
| `bitflyer order_by_best` | `--amount` (`-a`), `--type` (`-t`) | Submits a limit buy at the best bid or a limit sell at the best ask. |
| `bitflyer order_by_twap` | `--amount` (`-a`), `--type` (`-t`), `--number-of-times` (`-n`), `--interval` (`-i`) | Submits market orders of the specified size at scheduled intervals. Add `--dry-run` to preview locally. |
| `bitflyer ifdoco_by_range` | `--amount` (`-a`), `--type` (`-t`), `--range` (`-r`), `--percentage` (`-p`) | Places an IFDOCO strategy based on the latest execution price. Add `--dry-run` to fetch the public ticker and preview the three legs. |
| `bitflyer stop_by_range` | `--range` (`-r`) | Places a protective stop based on the current position. |
| `bitflyer counter_trade` | | Submits a market order to offset nonzero net exposure. |
| `bitflyer cancel_order` | `TYPE ID`, plus `--confirm-parent` when `TYPE` is `parent` | Requests cancellation of a child order or a parent strategy and its associated orders. Use `child` or `parent` for `TYPE`. |
| `bitflyer cancel_all` | | Requests cancellation of all child orders for `FX_BTC_JPY`. To cancel a parent strategy, use `bitflyer cancel_order parent ID --confirm-parent`. |

- `--amount` is a positive, finite size in BTC. For TWAP it is the size of
  each slice.
- `--type` accepts `buy` or `sell`.
- TWAP requires a positive whole number of slices. The interval is measured in
  seconds and can range from 0 to 2,147,483,647 inclusive.
- `--range` is a positive price distance in JPY. IFDOCO requires a finite
  range and a percentage strictly between 0 and 100.

## Environment variables

| Variable | Purpose |
| --- | --- |
| `BITFLYER_API_KEY` | API key for private requests. |
| `BITFLYER_API_SECRET` | API secret for private requests. |
| `XDG_STATE_HOME` | Base directory for stop and counter-trade submission records. The subdirectories are `bitflyer-cli/stops` and `bitflyer-cli/counter-trades`. When unset or empty, the base directory is `~/.local/state`. |

Help and both dry-run modes work without API credentials. Order and account
operations require credentials with the relevant bitFlyer permissions.

See [Getting started](getting-started.md) for a read-only walkthrough or
[Troubleshooting](troubleshooting.md) for help with failed requests and
submission records.
