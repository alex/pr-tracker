import SwiftUI

enum Palette {
    static let you = Color(nsColor: .systemOrange)
    static let review = Color(nsColor: .systemBlue)
    static let ci = Color(nsColor: .systemGray)
    static let blocked = Color(nsColor: .systemPurple)
    static let merged = Color(nsColor: .systemGreen)
    static let fail = Color(nsColor: .systemRed)

    static func color(for state: WaitingState) -> Color {
        switch state {
        case .you: you
        case .review: review
        case .ci: ci
        case .blocked: blocked
        case .merged: merged
        }
    }
}

struct CIBadgeView: View {
    let state: CIState

    var body: some View {
        ZStack {
            switch state {
            case .pass:
                Circle().fill(Palette.merged.opacity(0.15))
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.merged)
            case .fail:
                Circle().fill(Palette.fail.opacity(0.12))
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Palette.fail)
            case .running:
                Circle().fill(Color.primary.opacity(0.06))
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            case .none:
                Circle().strokeBorder(.quaternary, lineWidth: 1.5)
            }
        }
        .frame(width: 16, height: 16)
        .help(helpText)
    }

    private var helpText: String {
        switch state {
        case .pass: "Checks passed"
        case .fail: "Checks failed"
        case .running: "Checks running"
        case .none: "No checks"
        }
    }
}

struct AvatarView: View {
    let name: String?
    var size: CGFloat = 22

    private static let colors: [Color] = [
        Color(nsColor: .systemPurple), Color(nsColor: .systemTeal),
        Color(nsColor: .systemBlue), Color(nsColor: .systemPink),
        Color(nsColor: .systemIndigo), Color(nsColor: .systemOrange),
        Color(nsColor: .systemBrown), Color(nsColor: .systemMint),
    ]

    var body: some View {
        if let name, let first = name.first {
            Circle()
                .fill(Self.color(for: name))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(first).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .help(name)
        }
    }

    private static func color(for name: String) -> Color {
        // Deterministic across launches (hashValue is seeded per-process).
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return colors[abs(h) % colors.count]
    }
}

struct ChipView: View {
    let text: String
    var color: Color = .secondary
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(tint ?? color.opacity(0.12)))
            .fixedSize()
    }
}

struct GroupHeaderView: View {
    let state: WaitingState
    let count: Int
    /// Non-nil makes the header a collapse toggle and shows a chevron.
    var collapsed: Bool? = nil
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Palette.color(for: state)).frame(width: 8, height: 8)
            Text(state.label.uppercased())
                .font(.system(size: 11.5, weight: .bold))
                .kerning(0.3)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(count)")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            if let collapsed {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
            }
            Rectangle().fill(.quaternary.opacity(0.5)).frame(height: 1).padding(.leading, 4)
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture { if collapsed != nil { onToggle() } }
    }
}

// Purple elbow connecting a nested (blocked) row to its blocker above.
struct ConnectorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 8))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + 8, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}
