import AppKit
import SwiftUI

// Native semantic surfaces keep the same hierarchy in either appearance.
enum SumbarDesign {
    static let blue = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.40, green: 0.69, blue: 1, alpha: 1)
            : NSColor(red: 0.12, green: 0.36, blue: 0.76, alpha: 1)
    })
    static let positive = Color(nsColor: .systemGreen)
    static let negative = Color(nsColor: .systemOrange)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let separator = Color.primary.opacity(0.08)
    static let subtle = Color.primary.opacity(0.045)
}

struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct PreviewOpaqueMaterialKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var previewOpaqueMaterial: Bool {
        get { self[PreviewOpaqueMaterialKey.self] }
        set { self[PreviewOpaqueMaterialKey.self] = newValue }
    }
}

struct ControlGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.previewOpaqueMaterial) private var previewOpaque
    func body(content: Content) -> some View {
        if reduceTransparency || previewOpaque {
            content.background(SumbarDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(SumbarDesign.separator))
        }
    }
}

struct Surface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(SumbarDesign.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SumbarDesign.separator))
    }
}

struct QuietIconButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .frame(width: 32, height: 32)
            .background(SumbarDesign.subtle, in: Circle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

struct DeltaBadge: View {
    let value: Decimal
    var suffix = "%"
    var body: some View {
        let color = value < 0 ? SumbarDesign.negative : SumbarDesign.blue
        Label((value > 0 ? "+" : "") + Money.format(value) + suffix,
              systemImage: value < 0 ? "arrow.down.right" : value > 0 ? "arrow.up.right" : "minus")
            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }
}

struct PanelTabs: View {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    var body: some View {
        HStack(spacing: 4) {
            tab("Валюты", icon: "arrow.left.arrow.right", tag: 0, shortcut: "1")
            tab("Банки", icon: "building.columns", tag: 1, shortcut: "2")
            tab("Ценные бумаги", icon: "chart.line.uptrend.xyaxis", tag: 2, shortcut: "3")
        }.padding(5).modifier(ControlGlass())
            .accessibilityElement(children: .contain).accessibilityLabel("Разделы приложения")
    }
    private func tab(_ name: String, icon: String, tag: Int, shortcut: KeyEquivalent) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.23)) { selection = tag }
        } label: {
            Label(name, systemImage: icon)
                .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(selection == tag ? (scheme == .dark ? Color(white: 0.96) : Color(white: 0.10)) : (scheme == .dark ? Color(white: 0.68) : Color(white: 0.40)))
                .background {
                    if selection == tag {
                        RoundedRectangle(cornerRadius: 11).fill(SumbarDesign.surface)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "selected-tab", in: namespace)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).keyboardShortcut(shortcut, modifiers: .command)
            .accessibilityAddTraits(selection == tag ? .isSelected : [])
    }
}
