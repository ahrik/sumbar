# Sumbar

A native macOS menu bar application for Uzbekistan's currencies and securities. SwiftUI, AppKit and Swift Charts; macOS 14+, no third-party packages. Interface: Russian.

## Build and run

Install Xcode (or an appropriate Swift toolchain with macOS SDK). From the repository folder, run:

```sh
bash scripts/swift.sh test
bash scripts/build-app.sh
open temp/outputs/Sumbar.app
```

Click the chart icon in the macOS menu bar. The application has no Dock icon. Click outside the panel to dismiss it; it continues checking data while running. Choose Quit in the panel to stop it. `Sumbar.app/Contents/MacOS/Sumbar --preview` opens the panel immediately for review.

The build script creates an application for the build machine's architecture and signs it ad hoc for local use. Public releases still need a Developer ID signature and Apple notarization; this build is not notarized. No binaries or credentials are committed.

## Implemented

- A selected CBU rate, bank buy/sell quote or explicitly labelled securities close directly in the menu bar. Pin buttons and settings select the quote; unavailable or stale data shows a dash, with dates and source in the tooltip.
- Persistent favourite currencies, banks and securities, a favourite-bank filter, restored selections and copyable conversion results. Bank pins retain their own operation/channel independently of browsing.
- Configurable global panel shortcut (default Option-Command-S; alternatives and Off in settings), plus launch at login through macOS settings. Launch at login is available from the built `.app`; it is off until the user enables it.
- Provider scheduling avoids requests on every panel opening. HTTP 429/503 Retry-After is respected across endpoints on that host, and ETag/Last-Modified validators are used when supplied. Currency and per-security history failures stay independent.
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
bash scripts/swift.sh test
SUMBAR_LIVE_TESTS=1 bash scripts/swift.sh test -c release
```

The opt-in command checks the real CBU, securities and all three bank sources, plus complete startup and repeated refresh in an optimized release build. Normal tests use synthetic fixtures. Never commit downloaded page snapshots from `temp/work/`.

## Interface

The visual system, Apple references, keyboard shortcuts and local preview instructions are in [DESIGN.md](DESIGN.md).

## Data limitations and terms

CBU: <https://cbu.uz/ru/arkhiv-kursov-valyut/veb-masteram/>. Requests always specify the requested Tashkent date. Chart time zone is Asia/Tashkent.

UZSE data is read directly by the client from <https://finmind.uz/developers>. Finmind supplies stored daily closes, not live intraday trades. Changes compare the previous **stored session**, which may be much earlier than yesterday. Missing prices/changes are unknown, never zero. HTTP errors, including 429/503, retain local cached data; automatic checks remain bounded by the chosen interval. Daily charts can refresh during the day but cannot invent intraday prices.

Finmind permits personal use/research and requires written permission for bulk download, resale or redistribution. The app retrieves a catalogue and only the chosen instrument's detail for personal viewing. Do not publish the cache, ship cached quotes in releases, or proxy/redistribute market data without the relevant permission. MIT applies to the code, not market data. No actual quotes are checked into this repository.

Bank rates are fetched from the official public Ipak Yuli Bank and Kapitalbank pages and the Bank.uz exchange-office comparison page. See [BANK_SOURCES.md](BANK_SOURCES.md) for field mappings, coverage and freshness rules. Missing sides remain unknown. Direct bank data takes priority over aggregated data for the same bank/currency/channel; a failed or expired direct source can fall back to a current aggregate quote. These are indicative prices, not executable offers; fees, cash availability, branch differences and limits are not included.

The securities calculator estimates a scenario, not an order. It omits taxes, dividends, accrued coupon and market liquidity; the coupon figure is not yield to maturity. This application does not place trades or access bank accounts.

## Local storage

`~/Library/Application Support/Sumbar/cache.json` contains the last successful data and up to seven days of FX observations. Settings and favourites use macOS UserDefaults (`overviewPreferences`); the original currency and refresh settings migrate on first use. Missing saved instruments and pins are retained as unavailable rather than silently replaced. There are no analytics or user accounts. Internet requests expose the usual connection metadata to CBU, Finmind, Ipak Yuli Bank, Kapitalbank and Bank.uz. Bank snapshots share the local cache; older cache files without bank data remain readable.

## Next work

The [competitor research and improvement plan](COMPETITOR_RESEARCH.md) (Russian, 6 November 2026) compares eight products and defines priorities, acceptance criteria and delivery stages.

The first milestone (stages A+B) is implemented. Next: threshold alerts, bank comparison by UZS budget, Uzbek localization and signed/notarized distribution. Historical conversion, richer securities details, additional direct banks and a local portfolio follow as demand is validated.

## Contributing

Open the repository’s root `Package.swift` in Xcode. Run SwiftPM through `bash scripts/swift.sh build` or `bash scripts/swift.sh test`. Build artifacts, caches, previews and temporary checks are written under `temp/` and excluded from Git. The app bundle and zip are in `temp/outputs/`. Keep provider parsing separate from SwiftUI; retain Decimal for money; include synthetic fixtures/tests for schema changes; never commit personal cache data. Validate with `bash scripts/swift.sh test` and a release build. Submit small changes describing visible behavior and validation.

## License

MIT. Source conditions remain separate.

## Startup fix in 0.1.1

The previous release could terminate seconds after launch in `swift::TaskGroup::offer` during the bank-provider task group. Three matching crash reports and the release-mode startup regression reproduced the fault. Bank requests now use explicitly retained concurrent tasks, awaited through completion with cancellation propagation, instead of that nested task group. The launch and manual refresh paths use the same corrected code.

Provider-only tests did not exercise the failing orchestration. `StartupTests` now checks complete refresh and a second refresh in release mode. Avoid relying on a debug build or individual HTTP checks as startup validation.

After building the `.app`, run `python3 scripts/check-launch.py temp/outputs/Sumbar.app --seconds 30` on a Mac desktop. It starts the real release binary normally and with `--preview`, checks that both remain alive, then terminates only its own child processes.

## Daily overview in 0.2.0

Click the pin beside a currency, bank row or security to show it in the menu bar. A star adds it to favourites. In Settings, choose the menu display, pinned currency/bank/security and the global shortcut. A bank pin stores the customer operation and channel at the time it is pinned; changing the comparison screen does not change that pin. Opening Sumbar from the menu bar or global shortcut returns to the pinned quote.

Menu CBU/security checks become stale after two selected refresh intervals. CBU publication dates also need to be valid, not in the future or more than seven calendar days old. Securities show the actual saved session even if it is old, and always label the value as a close. Bank pins use the same source-failure, channel, side and age rules as the comparison. Cached values remain available in the panel when the menu shows a dash. Automatic checks and keyboard access work only while Sumbar runs; there is no monitoring during sleep or after Quit.

The build helper keeps SwiftPM scratch files, caches and compiler temporary files in `temp/`. Existing `.build`, `outputs` and `work` directories from earlier local builds can be moved to `temp/legacy-build`, `temp/outputs` and `temp/work`; moved compiler caches are not reused because their absolute paths may be invalid. The legacy ignore entries remain as a safeguard for direct SwiftPM/Xcode use.
