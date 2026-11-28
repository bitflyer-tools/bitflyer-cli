# Architecture

Start with [`exe/bitflyer`](../exe/bitflyer), the gem's executable. It loads
[`Bitflyer::Cli::Runner`](../lib/bitflyer/cli.rb) and calls `Runner.start`.
The runner declares commands and options with Thor and delegates each
invocation to a class in [`lib/bitflyer/cli/command/`](../lib/bitflyer/cli/command/).

## Clients and commands

- [`HasHTTPClient`](../lib/bitflyer/cli/has_http_client.rb) lazily creates the
  public and private HTTP clients from the `bitflyer` gem.
  [`Authorization`](../lib/bitflyer/cli/authorization.rb) reads the API key
  and secret from the environment for the private client.
- [`OrderByBestCommand`](../lib/bitflyer/cli/command/order_by_best_command.rb)
  shows the HTTP flow. It reads the ticker through the public client and
  submits a limit order through the private client.
- [`SummaryCommand`](../lib/bitflyer/cli/command/summary_command.rb) combines
  execution prices from [`Bitflyer::Cli::RealtimeClient`](../lib/bitflyer/cli/realtime_client.rb)
  with positions and collateral from the private HTTP client to render the
  terminal display. The shared [`Position`](../lib/bitflyer/cli/model/position.rb)
  model aggregates position rows and computes profit at a given price.

  Each `SummaryCommand#run` creates a new realtime client, whose constructor
  starts the WebSocket connection. The command's `subscribe_to_feed` method
  uses `executions_fx_btc_jpy=` to subscribe to `lightning_executions_FX_BTC_JPY`
  and `disconnected=` to clear the last price on disconnect. When the run exits,
  including on Ctrl+C, `restore_display` calls `shutdown` on the client to stop
  the connection monitor and close the WebSocket.

## Submission safety for stop_by_range and counter_trade

`stop_by_range` and `counter_trade` submit orders that must not be duplicated if the
command is interrupted or retried, so each keeps a record under a directory resolved by
[`SubmissionStateDirectory.under`](../lib/bitflyer/cli/submission_state_directory.rb)
(`$XDG_STATE_HOME/bitflyer-cli`) and locks a file through the shared
`SubmissionStateDirectory.synchronize`, which both submissions' own `synchronize` methods
call with their own path, lock path, and failure message, so concurrent runs on the same
machine serialize instead of racing.
[`DurableFile.replace`](../lib/bitflyer/cli/durable_file.rb) writes a record to a
temporary file in the same directory, `fsync`s it, renames it into place, and then
`fsync`s the directory and its ancestors, so a crash cannot leave a torn or missing
record.

- [`StopSubmission`](../lib/bitflyer/cli/stop_submission.rb) backs `stop_by_range`. Its
  `synchronize` locks one of 64 persistent `slot-*.lock` files keyed by a SHA-256 digest
  of the API key and stop parameters, and its record stores the acceptance ID (or
  `unverified`, or a `completed:`-prefixed ID) under the same key.
  [`ActiveStopLookup`](../lib/bitflyer/cli/active_stop_lookup.rb) and
  [`StopOrderMatcher`](../lib/bitflyer/cli/stop_order_matcher.rb) check active parent
  orders before submission to find an existing matching stop or a conflicting one.
- [`CounterTradeSubmission`](../lib/bitflyer/cli/counter_trade_submission.rb) backs
  `counter_trade`, keyed by product code and locked by a sibling `.lock` file. Its
  record stores the exposure being offset and the resulting acceptance ID so a retry can
  confirm the previous order's outcome before sizing another offset.
  [`CounterTradeTerminalOrderLookup`](../lib/bitflyer/cli/counter_trade_terminal_order_lookup.rb)
  fetches that order's terminal state, and
  [`ProtectiveStopCheck`](../lib/bitflyer/cli/protective_stop_check.rb) blocks the trade
  while an active protective stop or IFDOCO exit could conflict with it.
- Both commands page through parent orders with
  [`ParentOrderLookup`](../lib/bitflyer/cli/parent_order_lookup.rb), which raises if the
  exchange's pagination cursor stops decreasing or a lookup exceeds its request limit.
- When a record stays unverified or a lookup cannot confirm the outcome, the command
  exits with status 1 and reports the record path instead of guessing. See the
  [`stop_by_range`](../README.md#set-a-stop-by-range) and
  [`counter_trade`](../README.md#offset-a-position) sections of the README for how to
  resolve a stuck record.

## Where to look when making changes

- For command names, options, and dispatch, start with the
  [runner specs](../spec/bitflyer/cli_spec.rb).
- For exchange requests and command output, start with the
  [command specs](../spec/bitflyer/cli/command/). The
  [client doubles](../spec/support/client_doubles.rb) stub the HTTP connection
  and the realtime client so these specs can run without exchange access.
- For position calculations, start with the
  [position specs](../spec/bitflyer/cli/model/position_spec.rb).
- For submission records, locking, and durability, start with the
  [`stop_by_range`](../spec/bitflyer/cli/command/stop_by_range_command_spec.rb) and
  [`counter_trade`](../spec/bitflyer/cli/command/counter_trade_command_spec.rb) command
  specs, [`stop_submission_spec.rb`](../spec/bitflyer/cli/stop_submission_spec.rb), and the
  [shared unsafe-directory examples](../spec/support/submission_state_examples.rb).
