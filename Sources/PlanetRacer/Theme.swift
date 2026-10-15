import SwiftUI

/// Planet Racer's menu look, sampled from the original control-centre screens (sprite 732):
/// yellow Bitsumishi caps on translucent black panels with thin white rounded borders,
/// grey header bands, yellow arrow selectors, black buttons, a dark prompt strip.
enum Theme {
    static let yellow = Color(red: 1, green: 1, blue: 0)
    static let yellowDim = Color(red: 0.71, green: 0.71, blue: 0.16)
    static let white = Color.white
    static let grey = Color(red: 0.67, green: 0.67, blue: 0.73)
    static let panelFill = Color.black.opacity(0.73)
    static let panelBorder = Color(white: 0.92)
    static let band = Color(red: 0.27, green: 0.27, blue: 0.31).opacity(0.86)
    static let bandFocus = Color(red: 0.41, green: 0.41, blue: 0.16).opacity(0.92)
    static let strip = Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.92)
    static let navy = Color(red: 0, green: 0, blue: 0.2)
    // the opponent panel (mcOpponentPanel): lavender glass, green ACCEPT, red DECLINE
    static let rivalPanel = Color(red: 0.42, green: 0.42, blue: 0.56).opacity(0.9)
    static let accept = Color(red: 0.2, green: 0.85, blue: 0.25)
    static let decline = Color(red: 0.95, green: 0.2, blue: 0.15)
    static let border: CGFloat = 1.4
    static let radius: CGFloat = 10
}

/// Fonts registered from the asset pack (falls back to a system font).
struct Fonts {
    static var ui = "Helvetica-Bold"
    static var numbers = "Helvetica-Bold"
}

extension Font {
    static func game(_ size: CGFloat) -> Font { .custom(Fonts.ui, fixedSize: size) }
    static func numbers(_ size: CGFloat) -> Font { .custom(Fonts.numbers, fixedSize: size) }
}

/// Lays out content on the original 550x400 stage, scaled to fit the window (sharp at any size).
struct StageCanvas<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.height / 400, geo.size.width / 550)
            content
                .frame(width: 550, height: 400)
                .scaleEffect(s)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct Panel: View {
    var fill = Theme.panelFill
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.radius)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.panelBorder, lineWidth: Theme.border))
    }
}

struct Arrow: View {
    var right: Bool
    var color: Color
    var body: some View {
        Path { p in
            if right { p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 1, y: 0.5)); p.addLine(to: .init(x: 0, y: 1)) }
            else { p.move(to: .init(x: 1, y: 0)); p.addLine(to: .init(x: 0, y: 0.5)); p.addLine(to: .init(x: 1, y: 1)) }
            p.closeSubpath()
        }
        .applying(CGAffineTransform(scaleX: 10, y: 12))
        .fill(color)
        .frame(width: 10, height: 12)
    }
}

/// "LABEL      < value >" row, like the original garage. Focus = yellow bar, brighter band, yellow value.
struct SelectorRow: View {
    let item: MenuItem
    let focused: Bool
    var labelWidth: CGFloat = 132
    var onFocus: () -> Void
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(item.label).font(.game(13)).foregroundStyle(Theme.yellow)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, 8)
                .contentShape(Rectangle())
                .onTapGesture { onFocus() }
            Arrow(right: false, color: focused ? Theme.yellow : Theme.yellowDim)
                .padding(8).contentShape(Rectangle()).onTapGesture { onChange(-1) }
            Text(item.value ?? "").font(.game(13)).foregroundStyle(focused ? Theme.yellow : Theme.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            Arrow(right: true, color: focused ? Theme.yellow : Theme.yellowDim)
                .padding(8).contentShape(Rectangle()).onTapGesture { onChange(1) }
        }
        .frame(height: 26)
        .background(
            LinearGradient(colors: [focused ? Theme.bandFocus : Theme.band, .clear], startPoint: .leading, endPoint: .trailing)
        )
        .overlay(alignment: .leading) { if focused { Rectangle().fill(Theme.yellow).frame(width: 2.5) } }
        .onHover { if $0 && Input.mouseActive { onFocus() } }
    }
}

struct GameButton: View {
    let label: String
    let focused: Bool
    var size: CGFloat = 14
    var color: Color? = nil          // label colour (e.g. green ACCEPT); yellow by default
    var onFocus: () -> Void
    var onTap: () -> Void
    var body: some View {
        Text(label)
            .font(.game(focused ? size * 1.08 : size))
            .foregroundStyle(color.map { focused ? $0 : $0.opacity(0.75) } ?? (focused ? Theme.yellow : Theme.yellowDim))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(focused ? Color(red: 0.12, green: 0.12, blue: 0).opacity(0.92) : Color.black.opacity(0.88))
            .overlay(Rectangle().stroke(focused ? Theme.yellow : Theme.panelBorder, lineWidth: focused ? 2.2 : 1.2))
            .contentShape(Rectangle())
            .onHover { if $0 && Input.mouseActive { onFocus() } }
            .onTapGesture { onTap() }
    }
}

/// Button prompt glyph matching the input device in use.
struct Glyph: View {
    let text: String
    var body: some View {
        switch text {
        case "A": circle(Color(red: 0.16, green: 0.67, blue: 0.24), "A")
        case "B": circle(Color(red: 0.78, green: 0.2, blue: 0.16), "B")
        case "✕": circle(Color(white: 0.15), "✕", fg: Color(red: 0.5, green: 0.65, blue: 1))
        case "○": circle(Color(white: 0.15), "○", fg: Color(red: 1, green: 0.45, blue: 0.45))
        default:
            Text(text).font(.game(9)).foregroundStyle(Color(white: 0.1))
                .padding(.horizontal, 5).frame(height: 15)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.9)))
        }
    }
    private func circle(_ bg: Color, _ s: String, fg: Color = .white) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy)).foregroundStyle(fg)
            .frame(width: 15, height: 15).background(Circle().fill(bg))
    }
}

/// Bottom strip with button prompts (spans the full window width).
struct PromptStrip: View {
    let items: [(String, String)]
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.height / 400, geo.size.width / 550)
            VStack {
                Spacer()
                HStack(spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                        HStack(spacing: 5) {
                            Glyph(text: it.0)
                            Text(it.1).font(.game(10)).foregroundStyle(.white)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 24)
                .frame(width: geo.size.width / s)
                .background(Theme.strip)
                .scaleEffect(s, anchor: .bottomLeading)
                .frame(width: geo.size.width, height: 24 * s, alignment: .bottomLeading)
            }
        }
    }
}

/// The original menu backdrop (space, planets, the orange surface and glass dome), cover-fit.
struct Backdrop: View {
    let image: NSImage?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Theme.navy
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                        .clipped()
                }
            }
        }
        .ignoresSafeArea()
    }
}
