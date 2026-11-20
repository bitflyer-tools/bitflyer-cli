# Troubleshooting

## Why does the CLI say an API credential is missing?

Export both `BITFLYER_API_KEY` and `BITFLYER_API_SECRET` in the shell that
launches `bitflyer`. If you run the CLI from a script, make sure both variables
are available to that process. Run `bitflyer open_orders` to check private API
access without placing or canceling an order.

## Why does `summary` show `Current: Stale`?

The display needs a recent execution price from the realtime feed for
`FX_BTC_JPY`. It shows `Current: Stale` and displays `N/A` for spread and
balance while waiting for the first price, after a disconnect, or when the last
price is at least 30 seconds old. If the display stays stale, check your network
connection and wait for a new execution price.

## Why does `open_orders` show `None.`?

`None.` applies to the section immediately above it. The CLI lists active child
orders and active parent strategies for `FX_BTC_JPY` in separate sections.
Check both sections and confirm that the order belongs to that market. If you
need to look up a filled or canceled order, check your order history on bitFlyer.

## What should I do if cancellation acceptance could not be verified?

A connection failure or an HTTP 5xx response can leave the outcome of
`cancel_order` unknown. Run `bitflyer open_orders` again and look for the ID in
the relevant section before retrying. If you need to confirm the final state,
check the order on bitFlyer. The CLI lists only active orders and uses the
exchange's default result limit.
