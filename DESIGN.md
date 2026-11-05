# Sumbar interface

## Direction

A compact native financial instrument for the macOS menu bar. Let the current quote, its source date and the chart lead; navigation stays visually distinct from financial content. The panel uses a restrained blue accent, SF system typography and native AppKit materials.

## Apple guidance reviewed

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos): precise pointer controls, keyboard shortcuts and appropriate information density.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): Liquid Glass for navigation and controls; standard materials for content, sufficient contrast, respect accessibility preferences.
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): use a small number of glass effects, including a regular glass navigation vessel. macOS 26+ only; regular materials on macOS 14/15.

## Layout and typography

- 520-point popover, up to 760 points tall. Height is capped by the available display space. The body scrolls, keeping navigation and status accessible.
- Header with a restrained brand mark, refresh and settings. Two main tabs; settings is a separate view with a Done action.
- Currency quick selectors, a primary quote with units and effective date, history, converter, then provider details.
- Securities use the same hierarchy: instrument selection, current stored close, session date, chart and scenario calculator.
- System SF for text; rounded system figures for the primary quote and calculations. Monospaced digits prevent number alignment jumps. Supporting labels are at least 11 points.

## Materials and color

Native `windowBackgroundColor`, `controlBackgroundColor` and system label colors provide the content hierarchy in both appearances. A dynamically resolved financial blue is approximately #66B0FF in dark and #1F5CC2 in light. Labels, arrows and numbers accompany color-coded changes. Color does not assert that a rising exchange rate benefits the user.

Liquid Glass is limited to the navigation vessel. Calculator and settings content use quiet standard surfaces. There are no glass charts or simulated price motion.

System appearance is the default. Users may choose Light or Dark in settings. Reduce Transparency uses opaque control surfaces; Reduce Motion disables custom tab and press animations. Native keyboard focus remains intact.

## Interaction

- Command-1 / Command-2: currencies / securities.
- Command-R: refresh; Command-comma: settings.
- Chart selection reveals the nearest observed price and Tashkent timestamp.
- Hover help and accessibility names identify icon-only actions.
- Empty states offer refresh, provider failures retain explicit warnings, and unknown market values remain unknown.

## Visual verification

The debug-only renderer produces actual SwiftUI view images without opening a UI window, contacting providers or saving market data. All fixtures are synthetic and labelled in the header.

```sh
swift build
.build/debug/Sumbar --render-design outputs/design-review
```

Review the currency screen in Light and Dark, securities, settings and a shorter panel with opaque materials. The renderer cannot reproduce the compositing of the live desktop behind Liquid Glass; inspect that effect on a supported Mac. Demo values do not enter release builds.
