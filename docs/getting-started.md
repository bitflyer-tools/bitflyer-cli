# Getting started

Use bitflyer-cli to check your bitFlyer Crypto CFD account and active orders
for the BTC-CFD/JPY market (`FX_BTC_JPY`). The commands in this walkthrough
only read market and account data.

## Install the CLI

With Ruby 3.3 or later, install the gem and check that the executable is
available in your shell.

```sh
gem install bitflyer-cli
bitflyer help
```

## Set up API access

Use a bitFlyer API key with permission to read positions and collateral for
the account summary. To follow the open orders step, also grant permission
to list child and parent orders.

Export the credentials in the shell where you will run the CLI. Replace the
placeholders with your API key and secret.

```sh
export BITFLYER_API_KEY=your-bitflyer-api-key
export BITFLYER_API_SECRET=your-bitflyer-api-secret
```

## Read the live account summary

```sh
bitflyer summary
```

- **Current** shows the latest execution price received from the market feed.
- **Position** shows the average entry price and signed net position size.
- **Spread** shows the live price minus the average entry price, or zero when
  the position is flat.
- **Balance** shows collateral plus the estimated position profit or loss,
  with the profit or loss in parentheses.

The display can show `Current: Stale` while it waits for its first price.
Press `Ctrl+C` to return to the shell.

Add `--notify-webhook URL` with `--alert-price PRICE` and/or
`--alert-balance BALANCE` to get a one-time webhook notification (compatible
with Slack and Discord incoming webhooks) the moment the live price or the
estimated balance crosses that value, so you do not have to keep the terminal
in view to catch it.

```sh
bitflyer summary --notify-webhook https://hooks.slack.com/services/... --alert-balance 50000
```

## Check active orders

```sh
bitflyer open_orders
```

Look under **Child orders** for individual active orders and their remaining
size. Look under **Parent strategies** for active strategies such as STOP or
IFDOCO. Each section shows `None.` when it has no results.

See [Troubleshooting](troubleshooting.md) if a credential is missing, the
price stays stale, or an expected order is missing from the list.
