# Commercial bank rates

The application retrieves public pages for personal comparison. It does not proxy or redistribute a shared feed. No actual quotes or downloaded HTML are committed. Code licensing does not change the sources' data terms.

## Providers

| Provider | Page | Coverage and mapping |
| --- | --- | --- |
| Ipak Yuli Bank | https://ru.ipakyulibank.uz/physical/obmen-valyut | Nuxt tables named `В кассе`, `В приложении`, `В банкомате`. `code_name`, `rate.buy`, `rate.sell`; values are in hundredths of a sum and divided by 100. `lastUpdated` is Unix time. |
| Kapitalbank | https://www.kapitalbank.uz/ru/services/exchange-rates-new/ | Nuxt `physicalClients` only, excluding corporate and loan-payment rates. `bankRate`, `applicationRate`, `atmRate`. `buyRate` and `sellRate` already are UZS per unit. `scale` is display precision, not the currency nominal. `lastUpdate` is parsed in Asia/Tashkent. |
| Bank.uz | https://bank.uz/currency | The page's “Лучшие курсы обмена валют в обменных пунктах” section. Separate `best_` currency panels and explicitly named buy/sell columns, linked bank IDs and positive price spans. Cash channel only. USD, EUR, RUB and GBP were present during integration; the adapter also accepts CHF if it appears. The page does not provide individual rate publication timestamps; the UI states this. |

The integration check received 13 channel/currency quotes from Ipak, 17 from Kapitalbank and 95 quotes covering 28 banks from Bank.uz. Coverage varies by currency, channel, source availability and date; these counts are not guarantees. Broader CBU currency coverage never creates bank quotes for unsupported currencies.

These are site adapters rather than stable contractual APIs. A markup/schema change can make a source unavailable. They reject empty results, duplicate quote IDs and responses without USD. Each source refreshes independently, preserving its last successful snapshot on failure.

## Comparison

- Buying foreign currency uses the **bank sell** rate, ascending.
- Selling foreign currency uses the **bank buy** rate, descending.
- The entered amount is in the selected foreign currency; the total is in UZS using Decimal.
- Only the selected cash/app/ATM channel is compared. No currency-cross-rate substitution.
- Unknown/zero sides are unknown, never free offers. Invalid amounts have no calculated total. Ties are ordered deterministically and may have multiple best rows.
- Rates and totals are indicative, without commissions. Branch-specific offers, cash availability and limits may differ.
- Direct and aggregate quotes for the same bank are deduplicated. A current direct quote wins; a failed/old/unusable direct source can fall back to a current aggregate quote. Otherwise the cached row remains visible outside the ranking.

## Time and failures

`observedAt` means a successful retrieval, and `publishedAt` means the source's own update time. A retrieval never overwrites the publication time. All displayed dates use Tashkent time.

A quote is excluded from ranking when the successful retrieval is over 2 hours old, the known publication time is over 48 hours old, the provider's latest request failed, or the required side is missing. Times over five minutes in the future are also excluded. An unknown publication time is explicitly labelled; ranking such a quote means only that it was recently retrieved, not that the bank recently changed it. This is why the UI labels the winner as the best **received** rate and shows source/check information per row.

A single eligible bank is called an available offer, not a comparison winner. Source errors are visible independently. Data updates on the same running-app schedule as the other providers, with manual refresh and wake refresh.

## Tests

Synthetic tests cover buy/sell direction, nominal/unit conversion, channel separation, stale publications, old checks, failed-source fallback, duplicate-bank preference, unknown prices, invalid amounts, legacy cache decoding and relevant page layouts. `SUMBAR_LIVE_TESTS=1 bash scripts/swift.sh test` checks all real sources. For debugging an already-downloaded response, `SUMBAR_BANK_FIXTURES=/absolute/directory` can point the bank integration test at `ipak.html`, `kapital-old.html`, `bankuz.html`; these files must remain outside Git.

Menu bar bank pins use these same comparison rules and retain the selected bank, currency, side and channel independently of browsing. HTTP errors 429/503 impose host-wide Retry-After backoff, including manual refresh. Automatic panel opening respects the provider schedule.

## Budgets and threshold rules

The UZS mode divides the budget/target by the bank's sell rate when the customer buys, and by the bank's buy rate when the customer sells. The ranking order is unchanged; result differences are expressed in the selected foreign currency. The display remains indicative and excludes fees and limits.

Bank alerts use a selected bank, currency, operation and channel. In addition to comparison eligibility, a known publication time is mandatory. A successful download cannot turn an undated aggregate quote into a dated publication. Triggered observations expire at the earlier of check time + 2 hours and publication time + 48 hours; pending expired events are not delivered after restart.
