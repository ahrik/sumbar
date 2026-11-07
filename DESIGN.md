# Sumbar interface

## Direction

A compact native financial instrument for the macOS menu bar. Let the current quote, its source date and the chart lead; navigation stays visually distinct from financial content. The panel uses a restrained blue accent, SF system typography and native AppKit materials.

## Apple guidance reviewed

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos): precise pointer controls, keyboard shortcuts and appropriate information density.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): Liquid Glass for navigation and controls; standard materials for content, sufficient contrast, respect accessibility preferences.
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): use a small number of glass effects, including a regular glass navigation vessel. macOS 26+ only; regular materials on macOS 14/15.

## Layout and typography

- 520-point popover, up to 760 points tall. Height is capped by the available display space. The body scrolls, keeping navigation and status accessible.
- Header with a restrained brand mark, refresh and settings. Three main tabs (currencies, banks, securities); settings is a separate view with a Done action.
- Currency quick selectors, a primary quote with units and effective date, history, converter, then provider details.
- Bank comparison separates the customer’s operation from bank buy/sell prices, shows a common foreign-currency amount, and ranks only comparable channels. Quote sources and dates remain attached to each bank row.
- Securities use the same hierarchy: instrument selection, current stored close, session date, chart and scenario calculator.
- System SF for text; rounded system figures for the primary quote and calculations. Monospaced digits prevent number alignment jumps. Supporting labels are at least 11 points.

## Materials and color

Native `windowBackgroundColor`, `controlBackgroundColor` and system label colors provide the content hierarchy in both appearances. A dynamically resolved financial blue is approximately #66B0FF in dark and #1F5CC2 in light. Labels, arrows and numbers accompany color-coded changes. Color does not assert that a rising exchange rate benefits the user.

Liquid Glass is limited to the navigation vessel. Calculator and settings content use quiet standard surfaces. There are no glass charts or simulated price motion.

System appearance is the default. Users may choose Light or Dark in settings. Reduce Transparency uses opaque control surfaces; Reduce Motion disables custom tab and press animations. Native keyboard focus remains intact.

## Interaction

- Command-1 / Command-2 / Command-3: currencies / banks / securities.
- Command-R: refresh; Command-comma: settings.
- Chart selection reveals the nearest observed price and Tashkent timestamp.
- Hover help and accessibility names identify icon-only actions.
- Empty states offer refresh, provider failures retain explicit warnings, and unknown market values remain unknown.

## Visual verification

The debug-only renderer produces actual SwiftUI view images without opening a UI window, contacting providers or saving market data. All fixtures are synthetic and labelled in the header.

```sh
bash scripts/swift.sh build
temp/build/debug/Sumbar --render-design temp/design-review
```

Review the currency screen in Light and Dark, securities, settings and a shorter panel with opaque materials. The renderer cannot reproduce the compositing of the live desktop behind Liquid Glass; inspect that effect on a supported Mac. Demo values do not enter release builds.

## Daily overview

The existing SF typography, semantic system surfaces and blue accent extend to favourites and pin actions. Horizontal favourite currency cards scroll when the list exceeds the panel width. Stars mark favourites; pins select a single menu bar quote. The bank filter explicitly limits comparison to favourite banks. Settings use native pickers and retain unavailable saved selections visibly.

Option-Command-S opens or closes the panel globally by default. Settings offer Control-Option-S, Shift-Command-S and Off; conflicts are reported there. Launch at login is an explicit user toggle backed by Service Management. Copy writes the formatted conversion result and currency without reading the clipboard.

## Exchange alerts and language

The header bell opens a focused alert editor. Bank-row bells prefill the selected bank/channel/operation. Native pickers and a labelled positive-threshold field define inclusive conditions; the first-match checkbox explains the initial-state behavior. Rules show active/paused/triggered status and delivery separately. The alert page scrolls while retaining the header and footer. A notification route opens the requested bank with an explicit filter and a way back to all banks.

The UZS budget/target selector retains the customer operation above it. Result captions name whether the user receives currency, pays UZS or needs to sell currency. Differences carry their own unit.

RU/UZ comes from matching string catalogues with interpolation arguments kept separate from translated formats. Underlying selection IDs and parsing labels remain stable. The bank adapter still matches the original source labels. Semantic controls retain keyboard focus and explicit labels for amount, threshold, pin and bell actions; translations are visually checked in both appearances. VoiceOver interaction and real system banners still require manual desktop validation.

## History and floating presentation

The converter adds an explicit current/historical mode with a calendar date field, load action and source/effective/check dates. A missing selected-date rate disables the result and clipboard action. The chart exposes day/week/month/quarter/year; weekly samples and partial loads are visibly points, with coverage and stop/resume actions. The long axis includes the year and keeps edge labels inside the plot.

The header panel pin (Shift-Command-P) is distinct from quote pins. It moves the same hosting controller into a resizable floating NSPanel rather than replacing the selected view. The popover restores its original dimensions when unpinned. The launch checker also validates nonzero visible layout dimensions in popover and floating modes.

Security context uses quiet source-labelled rows for session metrics and bond fields, followed by up to five source links. Unknown values remain dashes. Monetary bond calculations explicitly require a known price basis and, for percent-of-par quotes, nominal.


## Bank observation history

The clock action on each bank row opens a focused history sheet with bank/currency/channel identity, a source selector, week/month periods, two bank-side point series and the last numeric observation. No connecting line spans intervals without checks. Both source publication and local observation time are shown separately; Bank.uz’s missing publication time remains explicit. Empty history explains that collection starts with successful updates. Storage errors appear both beside the bank list and inside the sheet. RU/UZ use the existing catalogues.

## macOS widgets

WidgetKit provides a small/medium single-currency card and a medium/large rates list. The system owns placement, margins, background treatment and appearance. Cards use the existing SF typography, rounded primary figures, monospaced digits and blue accent. The small card abbreviates the saved-state caption to fit its width. Publication dates and the successful check time remain separate.

Each instance selects its currency and language through App Intents. A single card opens its selected currency; list rows open their respective currencies. These routes preserve the menu-bar pin. Live entries use fetched or cached data; gallery fixtures remain confined to previews.

Run `bash scripts/render-widgets.sh` to render all sizes, RU/UZ, light/dark and missing/saved states into `temp/widget-previews/`. Documentation examples in `web/assets/widgets/` come from this renderer and are labelled as demonstration values in the [widget guide](docs/WIDGETS.md). After visual changes, refresh the examples and run the documentation checks. Actual gallery placement, widget editing and system scheduling require a desktop check with an installed `.app`.
