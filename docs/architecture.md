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

## Where to look when making changes

- For command names, options, and dispatch, start with the
  [runner specs](../spec/bitflyer/cli_spec.rb).
- For exchange requests and command output, start with the
  [command specs](../spec/bitflyer/cli/command/). The
  [client doubles](../spec/support/client_doubles.rb) stub the HTTP connection
  and the realtime client so these specs can run without exchange access.
- For position calculations, start with the
  [position specs](../spec/bitflyer/cli/model/position_spec.rb).
