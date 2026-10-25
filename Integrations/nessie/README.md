# Capital One Nessie integration

**Status: built and runnable, not wired into the live iPhone demo yet.** The app still reads its bundled demo orders.

[Nessie](http://nessieisreal.com) is Capital One's mock banking API. This module stores the demo person's purchase history in Nessie and reads it back for Claude's `order_history` tool.

Nessie gives us **what was bought, where, when and for how much**. It has no ingredient lists, so each purchase is joined by product name with our own catalog (`products.json`), which holds the ingredients from the product labels.

## Files

| File | What |
|---|---|
| `nessie.py` | `seed` creates the customer, a card account, the merchant and 30 purchases. `orders` reads them back and joins ingredients. |
| `demo_orders.json` | Douglas's 30 demo orders (dates are shifted so the story ends "today"). Amounts are approximate demo prices. |
| `products.json` | Product catalog: category and ingredient list per item. |

## Run

```bash
export NESSIE_KEY=...                 # log in at nessieisreal.com with GitHub
python3 nessie.py seed                # one time
python3 nessie.py orders --days 30    # JSON in the same shape as Claude's order tool
python3 nessie.py seed --dry-run      # see the API calls without a key
```

## Next step

Call `orders` from the server and point the app's `order_history` tool at it, keeping the bundled data as a fallback when Nessie is unreachable.
