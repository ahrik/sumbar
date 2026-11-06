# Sumbar

A native macOS menu bar application for Uzbekistan's currencies and securities. SwiftUI, AppKit and Swift Charts; macOS 14+, no third-party packages. Interface: Russian and Uzbek (Latin), selectable in Settings.

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

- Historical CBU conversion by selected Tashkent date, with the actual effective publication date and Decimal arithmetic. A missing historical quote never falls back to today's rate.
- Currency charts for a week/month (daily requested snapshots) and quarter/year (explicitly labelled weekly samples), with persistent shared archive caching, progress, cancellation and honest partial-data display.
- Securities context: session OHLC/volume/turnover, issuer, bond nominal/coupon/frequency/maturity and source disclosure links. Percent-of-par bond prices are converted using nominal before monetary scenario calculations; unknown price bases cannot silently become cash amounts.
- A resizable floating panel via the header pin or Shift-Command-P, preserving the same hosted view while moving between the popover and the floating window. Escape hides it; closing its window returns to menu-bar mode.

- One-shot CBU and selected-bank threshold alerts, with customer buy/sell side and cash/app/ATM channel. Rules persist before delivery, support pause/delete/manual retry and open the matching quote from a notification. Unknown bank publication times cannot trigger alerts.
- Bank comparison accepts either a foreign-currency amount or UZS budget/target; Decimal division computes the foreign amount at each bank's applicable side.
- Russian/Uzbek interface, menu tooltips and notification text; the language choice persists independently of existing favourites and settings. Bank names, tickers and source diagnostics retain their original text; currency names use the CBU's Uzbek field when available.

- A selected CBU rate, bank buy/sell quote or explicitly labelled securities close directly in the menu bar. Pin buttons and settings select the quote; unavailable or stale data shows a dash, with dates and source in the tooltip.
- Persistent favourite currencies, banks and securities, a favourite-bank filter, restored selections and copyable conversion results. Bank pins retain their own operation/channel independently of browsing.
- Configurable global panel shortcut (default Option-Command-S; alternatives and Off in settings), plus launch at login through macOS settings. Launch at login is available from the built `.app`; it is off until the user enables it.
- Provider scheduling avoids requests on every panel opening. HTTP 429/503 Retry-After is respected across endpoints on that host, and ETag/Last-Modified validators are used when supplied. Currency and per-security history failures stay independent.
- An adaptive native popover anchored to the menu bar, light/dark/system appearance, glass navigation on macOS 26+ and standard material fallback on macOS 14/15.
- Commercial bank comparison: direct Ipak Yuli Bank, Kapitalbank and Hamkorbank rates plus exchange-office offers from Bank.uz. Customer buy/sell direction, channel filters, totals and differences, per-row sources and publication/check times.
- Official CBU rates, all published currencies, correct normalization by `Nominal`, effective dates and selectable historical views.
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

Bank rates are fetched from the official public Ipak Yuli Bank and Kapitalbank pages and the Hamkorbank website’s public API and the Bank.uz exchange-office comparison page. See [BANK_SOURCES.md](BANK_SOURCES.md) for field mappings, coverage and freshness rules. Missing sides remain unknown. Direct bank data takes priority over aggregated data for the same bank/currency/channel; a failed or expired direct source can fall back to a current aggregate quote. These are indicative prices, not executable offers; fees, cash availability, branch differences and limits are not included.

The securities calculator estimates a scenario, not an order. It omits taxes, dividends, accrued coupon and market liquidity; the coupon figure is not yield to maturity. This application does not place trades or access bank accounts.

## Local storage

`~/Library/Application Support/Sumbar/bank-history.json` stores local successful bank-rate observations, kept separately by bank, currency, exchange channel and provider. `~/Library/Application Support/Sumbar/currency-history.json` stores requested-day CBU snapshots with effective dates and successful-check timestamps. `~/Library/Application Support/Sumbar/alerts.json` stores alert rules, crossing/delivery state and the observation that triggered an alert. `~/Library/Application Support/Sumbar/cache.json` contains the last successful data and up to seven days of FX observations. Settings and favourites use macOS UserDefaults (`overviewPreferences`); the original currency and refresh settings migrate on first use. Missing saved instruments and pins are retained as unavailable rather than silently replaced. There are no analytics or user accounts. Internet requests expose the usual connection metadata to CBU, Finmind, Ipak Yuli Bank, Kapitalbank, Hamkorbank and Bank.uz. Bank snapshots share the local cache; older cache files without bank data remain readable.

## Next work

The [competitor research and improvement plan](COMPETITOR_RESEARCH.md) (Russian, 6 November 2026) compares eight products and defines priorities, acceptance criteria and delivery stages.

Stages A+B, the functional work from C and the historical/context/panel work from D are implemented. Public Developer ID signing/notarization and a full manual accessibility audit remain. Stage E now includes local bank-rate observations. Next: additional direct banks, positions, user-data backup and confirmed payout events as demand is validated. A verified bulk CBU history source could later replace the weekly quarter/year sampling.

## Contributing

Open the repository’s root `Package.swift` in Xcode. Run SwiftPM through `bash scripts/swift.sh build` or `bash scripts/swift.sh test`. Build artifacts, caches, previews and temporary checks are written under `temp/` and excluded from Git. The app bundle and zip are in `temp/outputs/`. Keep provider parsing separate from SwiftUI; retain Decimal for money; include synthetic fixtures/tests for schema changes; never commit personal cache data. Validate with `bash scripts/swift.sh test` and a release build. Submit small changes describing visible behavior and validation.

## License

MIT. Source conditions remain separate.

## Startup fix in 0.1.1

The previous release could terminate seconds after launch in `swift::TaskGroup::offer` during the bank-provider task group. Three matching crash reports and the release-mode startup regression reproduced the fault. Bank requests now use explicitly retained concurrent tasks, awaited through completion with cancellation propagation, instead of that nested task group. The launch and manual refresh paths use the same corrected code.

Provider-only tests did not exercise the failing orchestration. `StartupTests` now checks complete refresh and a second refresh in release mode. Avoid relying on a debug build or individual HTTP checks as startup validation.

After building the `.app`, run `python3 scripts/check-launch.py temp/outputs/Sumbar.app --seconds 30` on a Mac desktop. It starts the real release binary normally, with `--preview`, and with `--preview --pin-panel`. It checks the visible panel dimensions and that all three processes remain alive, then terminates only its own child processes.

## Daily overview in 0.2.0

Click the pin beside a currency, bank row or security to show it in the menu bar. A star adds it to favourites. In Settings, choose the menu display, pinned currency/bank/security and the global shortcut. A bank pin stores the customer operation and channel at the time it is pinned; changing the comparison screen does not change that pin. Opening Sumbar from the menu bar or global shortcut returns to the pinned quote.

Menu CBU/security checks become stale after two selected refresh intervals. CBU publication dates also need to be valid, not in the future or more than seven calendar days old. Securities show the actual saved session even if it is old, and always label the value as a close. Bank pins use the same source-failure, channel, side and age rules as the comparison. Cached values remain available in the panel when the menu shows a dash. Automatic checks and keyboard access work only while Sumbar runs; there is no monitoring during sleep or after Quit.

The build helper keeps SwiftPM scratch files, caches and compiler temporary files in `temp/`. Existing `.build`, `outputs` and `work` directories from earlier local builds can be moved to `temp/legacy-build`, `temp/outputs` and `temp/work`; moved compiler caches are not reused because their absolute paths may be invalid. The legacy ignore entries remain as a safeguard for direct SwiftPM/Xcode use.

## Exchange alerts in 0.3.0

Open the bell in the header to create a CBU rule, or the bell on a bank row to prefill that bank, operation and channel. Enter a positive UZS-per-unit threshold and choose at-or-above or at-or-below. By default, a rule first observes a value outside the condition, then signals a crossing. “Notify on first match” also allows a rule whose first eligible value already meets the condition. Equal-to-threshold values meet both inclusive comparisons. Pause/resume waits for a new crossing; triggered rules remain consumed after restart.

The notification permission prompt appears only when the user adds a rule or requests a test, never at launch. Delivery requires the built `.app`, permission in macOS and a running, awake Mac. The app does not reconstruct prices missed during sleep. Bank alerts require both a recent check and a known, eligible publication time; aggregate quotes without publication times remain useful for comparison but do not trigger alerts. The interface displays waiting rules when fresh data is missing.

Alert state is written atomically before delivery. A stable notification identifier is checked against pending/delivered notifications; pending events can recover after restart while still fresh. Expired events are marked expired rather than sent with an old quote. Failed delivery has an explicit retry; a corrupt rules file is preserved and never silently overwritten. The operating system controls banner presentation, sound and Focus suppression; the app records successful handoff to macOS, not proof the person saw the banner.

In the Banks screen choose foreign amount or UZS budget (buying)/UZS target (selling). The latter divides the sum by bank sell/buy respectively. Results and differences are estimates rounded for display; fees, availability, limits and branch differences remain excluded.

Settings → Interface language switches RU/UZ without resetting favourites or pins. Translation resources ship inside `Sumbar_Sumbar.bundle`; the app builder copies them alongside the executable. Optional public signing is available with `SUMBAR_SIGN_IDENTITY` set to a valid Developer ID Application identity. Without it, the builder continues to sign ad hoc for local use. This machine has no such Developer ID identity; public signing/notarization was not performed.

Validation covers thresholds, bank side/channel/time rules, denied delivery, pause/resume, persistence, pending-event recovery, failed writes, corrupt storage, UZS calculations and catalogue/format compatibility. The debug renderer includes both languages and the alert screen. Real system notification permission and banner interaction need a desktop check in the built app; tests use a delivery substitute and never request permission or send notifications.

## History and market context in 0.4.0

In the converter select “On a selected date”, choose a date and load the rate. The selected date, source publication/effective date and successful retrieval time stay separate. Weekends may use an earlier publication, but a publication after the requested day is rejected. Unsupported currency/date pairs show no result; conversion and clipboard output cannot silently use today's quote. The historical converter is independent of current menu-bar prices and alert evaluation.

Long charts use the documented date-specific CBU JSON endpoint; a verified bulk range endpoint was not established. A month requests at most 32 daily snapshots; a quarter requests at most 16 and a year at most 55 anchored weekly/end-point snapshots. Weekly samples and incomplete series use points without invented connecting prices. The axis retains the selected range, and year views show the year. Coverage counts report successful requested snapshots. Multiple weekend requests for the same effective publication produce one plotted point.

Snapshots contain all returned currencies, so changing currencies reuses the same dates. Past successful snapshots persist across restarts; today's snapshot can refresh after 15 minutes. Successful current-rate refreshes also seed today's archive entry without another request. Requests for the same date coalesce, range loads serialize and cancellation stops additional dates after the current shared request completes. An error stops the batch and retains successful points. Per-date failures have a short retry delay, and the existing HTTP Retry-After rules still apply. Corrupt archive files are preserved rather than overwritten.

The securities card keeps each metric attached to its source session date. Empty coupon frequency is unknown, not an inferred calendar. Only HTTPS disclosure links under openinfo.uz, uzse.uz or finmind.uz are shown, with source-language titles. Bond `amount_per_bond` and `percent_of_par` are handled separately; a percentage quote requires a known nominal to produce a monetary scenario. These are still stored session data, not realtime trading prices or yield-to-maturity estimates.

The header pin creates a floating, resizable native window. It stays above other windows while switching applications. The window's close button returns its content to the popover; Escape hides it and the global shortcut shows/hides the active presentation. Pinning is a session preference and does not change which quote is pinned to the menu bar.

During initial validation on 6 November 2026, CBU HTTPS requests failed certificate verification on both the bare and www hosts. The connection presented a self-signed Bitrix certificate. Later that day both hosts returned a trusted certificate and current/historical API requests succeeded, before any application code changed. Certificate verification was never bypassed.

## CBU connection recovery in 0.4.1

If a CBU request fails because of DNS, a connection timeout or a server TLS/certificate error, Sumbar makes one additional HTTPS attempt through the official `www.cbu.uz` alias. The exact requested Tashkent date is preserved; the alternate response passes the same decoding and nominal normalization. Both attempts use the existing URLSession client with its normal certificate and hostname checks. No fixed server IP, third-party rate feed, DNS configuration change or trust exception is used.

HTTP errors (including 429/503 and Retry-After), invalid payloads, cancellation and offline status do not trigger the alternate attempt. A failed alternate attempt stops the request and retains saved data. Certificate and general TLS failures now identify the CBU source and suggest retrying later or checking the network/VPN, in Russian and Uzbek. This retry can help when only one official alias works; it cannot repair a certificate failure on both aliases.

Validation includes selective failover, exact historical dates, Decimal normalization, cancellation between attempts, both-host certificate failure, HTTP backoff preservation and current/historical CBU integration checks.


## Bank observations in 0.5.0

Use the clock button beside a bank to open its observed buy/sell rates for the last 7 or 31 days. Both sides use the bank’s direction (the bank buys / the bank sells), in UZS per foreign unit. The source selector keeps direct-bank and Bank.uz observations separate, including their publication times when known. The chart displays points only, so missing checks are never presented as known prices. The latest observation also has a readable numeric summary and separate check/publication timestamps in Tashkent time.

History starts with successful checks after this update; old cache entries are not backfilled. It collects while the application is running, using the existing refresh schedule without additional network requests. Each stream records at most one observation per minute, retains unchanged rates on later checks, and keeps a rolling 31 days. Closed-app intervals, failed providers, invalid prices, future checks and stale quotes create no observations. Unknown publication time stays unknown. Local observations do not change current rankings or alert freshness rules.

History persists atomically in its own file. Read failures preserve the original file and prevent overwriting it; write failures remain visible on the bank screen and history sheet. In-memory samples remain usable after a storage error. Tests cover source/channel/currency isolation, Decimal round trips, gaps, deduplication, retention, stale/future samples, partial provider failures and storage failures.


## Hamkorbank in 0.5.1

The third direct bank source uses the public API referenced by [Hamkorbank’s exchange page](https://hamkorbank.uz/exchange-rate/). It provides cash and app quotes for supported currencies without copying cash prices into missing app/ATM channels. Rates use the bank’s buy/sell direction, are normalized from hundredths of UZS with Decimal, and retain their own publication and local check times. Amount-conditioned tiers, precious metals, unknown channels and not-yet-effective rates are excluded. These quotes automatically participate in comparison, favourites, menu pins, bank alerts and local history under the existing freshness rules.

The bank ID remains `hamkorbank`, matching older Bank.uz snapshots, so saved favourites/pins/rules/history retain their identity. Direct and aggregate streams stay separate; a failed or stale direct source can still use a current aggregate quote for ranking. Actual API responses and website scripts used for field verification remain under ignored `temp/`.
