# Sumbar

A native macOS menu bar application for Uzbekistan's currencies and securities. SwiftUI, AppKit and Swift Charts; macOS 14+, no third-party packages. Interface: Russian.

## Build and run

Install Xcode (or an appropriate Swift toolchain with macOS SDK). From the repository folder, run:

```sh
swift test
bash scripts/build-app.sh
open outputs/Sumbar.app
```

Click the chart icon in the macOS menu bar. The application has no Dock icon. Click outside the panel to dismiss it; it continues checking data while running. Choose Quit in the panel to stop it. `Sumbar.app/Contents/MacOS/Sumbar --preview` opens the panel immediately for review.

The build script creates an application for the build machine's architecture and signs it ad hoc for local use. Public releases still need a Developer ID signature and Apple notarization; this build is not notarized. No binaries or credentials are committed.

## Implemented

- An adaptive native popover anchored to the menu bar, light/dark/system appearance, glass navigation on macOS 26+ and standard material fallback on macOS 14/15.
- Commercial bank comparison: direct Ipak Yuli Bank and Kapitalbank rates plus exchange-office offers from Bank.uz. Customer buy/sell direction, channel filters, totals and differences, per-row sources and publication/check times.
- Official CBU rates, all published currencies, correct normalization by `Nominal`, effective dates, seven-day publication history.
- Intraday FX observations saved during successful checks. This is an observation chart, not a trading feed. A single observation is displayed as a point. A constant CBU rate remains flat, never simulated.
- Automatic checks every 15/30/60 minutes while running, explicit refresh, wake refresh, independent currency/security/bank provider failure messages.
- UZSE stocks and bonds via the public Finmind API, per-instrument trade dates, daily closing-price history, ticker/company search.
- Currency conversion and securities calculator using Decimal: whole quantities, buy/sell scenario, a separately applied commission on both sides, return percentage; annual coupon per bond when nominal and coupon are provided.
- Local cache and settings, source attribution, actual successful-check timestamps. Failed requests preserve cached values and display an error.

## Validation

```sh
swift test
SUMBAR_LIVE_TESTS=1 swift test
```

The opt-in command checks the real CBU, securities and all three bank sources. Normal tests use synthetic fixtures. Never commit downloaded page snapshots from `work/`.

## Interface

The visual system, Apple references, keyboard shortcuts and local preview instructions are in [DESIGN.md](DESIGN.md).

## Data limitations and terms

CBU: <https://cbu.uz/ru/arkhiv-kursov-valyut/veb-masteram/>. Requests always specify the requested Tashkent date. Chart time zone is Asia/Tashkent.

UZSE data is read directly by the client from <https://finmind.uz/developers>. Finmind supplies stored daily closes, not live intraday trades. Changes compare the previous **stored session**, which may be much earlier than yesterday. Missing prices/changes are unknown, never zero. HTTP errors, including 429/503, retain local cached data; automatic checks remain bounded by the chosen interval. Daily charts can refresh during the day but cannot invent intraday prices.

Finmind permits personal use/research and requires written permission for bulk download, resale or redistribution. The app retrieves a catalogue and only the chosen instrument's detail for personal viewing. Do not publish the cache, ship cached quotes in releases, or proxy/redistribute market data without the relevant permission. MIT applies to the code, not market data. No actual quotes are checked into this repository.

Bank rates are fetched from the official public Ipak Yuli Bank and Kapitalbank pages and the Bank.uz exchange-office comparison page. See [BANK_SOURCES.md](BANK_SOURCES.md) for field mappings, coverage and freshness rules. Missing sides remain unknown. Direct bank data takes priority over aggregated data for the same bank/currency/channel; a failed or expired direct source can fall back to a current aggregate quote. These are indicative prices, not executable offers; fees, cash availability, branch differences and limits are not included.

The securities calculator estimates a scenario, not an order. It omits taxes, dividends, accrued coupon and market liquidity; the coupon figure is not yield to maturity. This application does not place trades or access bank accounts.

## Local storage

`~/Library/Application Support/Sumbar/cache.json` contains the last successful data and up to seven days of FX observations. Settings use macOS UserDefaults. There are no analytics or user accounts. Internet requests expose the usual connection metadata to CBU, Finmind, Ipak Yuli Bank, Kapitalbank and Bank.uz. Bank snapshots share the local cache; older cache files without bank data remain readable.

## Next work

1. Additional direct bank providers, branch-specific offers and bank quote history.
2. Licensed UZSE intraday feed, preserving actual trade timestamps and gaps.
3. Provider-specific Retry-After handling, conditional HTTP requests and additional integration tests.
4. Alert rules, favourites, Uzbek localization, accessibility audit, signed/notarized universal releases.

## Contributing

Open the repository’s root `Package.swift` in Xcode. Build artifacts are written to `outputs/` and excluded from Git. Keep provider parsing separate from SwiftUI; retain Decimal for money; include synthetic fixtures/tests for schema changes; never commit personal cache data. Validate with `swift test` and a release build. Submit small changes describing visible behavior and validation.

## License

MIT. Source conditions remain separate.
