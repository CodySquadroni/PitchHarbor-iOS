// Shared colors, spacing, accessible controls, and the interactive match pitch.
// These components render supplied state and forward actions to their owning screen.

import SwiftUI

/// Central colors, including appearance-aware text/action contrast.
enum Palette {
    static let green = Color(red: 0.043, green: 0.231, blue: 0.18)
    static let action = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.333, green: 0.839, blue: 0.639, alpha: 1)
                : UIColor(red: 0.043, green: 0.231, blue: 0.18, alpha: 1)
        })
    // Keep small supporting text readable on grouped surfaces on older iOS too.
    static let secondaryText = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.72, green: 0.77, blue: 0.74, alpha: 1)
                : UIColor(red: 0.31, green: 0.36, blue: 0.33, alpha: 1)
        })
    static let mint = Color(red: 0.333, green: 0.839, blue: 0.639)
    static let navy = Color(red: 0.063, green: 0.165, blue: 0.263)
    static let amber = Color(red: 0.957, green: 0.725, blue: 0.259)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

/// Shared screen gutters and content width cap; keep edge spacing consistent across tabs.
enum ScreenSpacing {
    static func gutter(for width: CGFloat) -> CGFloat { width >= 700 ? 28 : (width >= 500 ? 24 : 16) }
    static let maximumWidth: CGFloat = 1400
}

/// Editing and navigation actions must remain available after scrolling on Duo's outer display.
struct PersistentNavigationActions: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.toolbarMinimizationBehavior(.never, for: .navigationBar, .bottomBar)
        } else {
            content
        }
    }
}

/// Measures the available safe area, including the system's tab/sidebar space.
/// Grids receive the actual content width so their minimums cannot widen a page.
/// Provides safe horizontal gutters and the usable width for responsive child grids.
struct PageScrollView<Content: View>: View {
    @ViewBuilder var content: (CGFloat) -> Content
    var body: some View {
        GeometryReader { geometry in
            let width = max(
                1,
                min(geometry.size.width, ScreenSpacing.maximumWidth) - 2
                    * ScreenSpacing.gutter(for: geometry.size.width))
            ScrollView {
                content(width)
                    .frame(width: width, alignment: .leading)
                    .padding(.top, 20).padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct PageHeading: View {
    var title: String
    var eyebrow: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(.title, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.045)))
    }
}
struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text).font(.system(.caption2, design: .rounded, weight: .bold)).tracking(0.8).foregroundStyle(
            Palette.secondaryText)
    }
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var color: Color = Palette.green
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded, weight: .bold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity).frame(minHeight: 44)
            .foregroundStyle(enabled ? .white : Palette.secondaryText)
            .background(enabled ? color : Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .opacity(enabled && configuration.isPressed ? 0.75 : 1)
    }
}
struct KitBadge: View {
    var number: Int
    var keeper = false
    var size: CGFloat = 38
    var body: some View {
        Text("\(number)").font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .frame(width: size, height: size)
            .background(keeper ? Palette.amber : Palette.green, in: RoundedRectangle(cornerRadius: size * 0.32))
            .foregroundStyle(keeper ? Palette.navy : .white)
    }
}
struct SectionHeading: View {
    var title: String
    var detail: String?
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                heading.fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 8)
                if let detail { Text(detail).font(.caption).foregroundStyle(Palette.secondaryText).fixedSize() }
            }
            VStack(alignment: .leading, spacing: 4) {
                heading.fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(.caption).foregroundStyle(Palette.secondaryText) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var heading: some View {
        Text(title).font(.system(.title3, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
    }
}

struct PitchMarkings: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            for stripe in 0..<10 where stripe.isMultiple(of: 2) {
                context.fill(
                    Path(CGRect(x: 0, y: CGFloat(stripe) * h / 10, width: w, height: h / 10)),
                    with: .color(.white.opacity(0.025)))
            }
            let inset = w * 0.055, fw = w - 2 * inset, fh = h - 2 * inset
            var path = Path()
            path.addRect(CGRect(x: inset, y: inset, width: fw, height: fh))
            path.move(to: CGPoint(x: inset, y: h / 2))
            path.addLine(to: CGPoint(x: w - inset, y: h / 2))
            path.addEllipse(in: CGRect(x: w / 2 - w * 0.13, y: h / 2 - w * 0.13, width: w * 0.26, height: w * 0.26))
            for top in [true, false] {
                let y = top ? inset : h - inset - h * 0.16
                path.addRect(CGRect(x: w * 0.23, y: y, width: w * 0.54, height: h * 0.16))
                path.addRect(
                    CGRect(x: w * 0.36, y: top ? inset : h - inset - h * 0.06, width: w * 0.28, height: h * 0.06))
                path.addRect(
                    CGRect(x: w * 0.43, y: top ? inset - h * 0.018 : h - inset, width: w * 0.14, height: h * 0.018))
            }
            context.stroke(path, with: .color(.white.opacity(0.38)), lineWidth: 1.2)
            context.fill(
                Path(ellipseIn: CGRect(x: w / 2 - 2, y: h / 2 - 2, width: 4, height: 4)),
                with: .color(.white.opacity(0.6)))
        }
        .background(
            LinearGradient(
                colors: [Palette.green, Color(red: 0.065, green: 0.30, blue: 0.23)], startPoint: .topLeading,
                endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }
}
/// Exports a scoped player token; the destination validates its match/editor context.
struct LineupDragSource: ViewModifier {
    var playerID: UUID
    var contextID: UUID
    var enabled = true
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.draggable(LineupDrag.token(playerID: playerID, contextID: contextID)) } else { content }
    }
}

/// Accepts only a player token from this context and forwards the requested placement.
struct LineupDropTarget: ViewModifier {
    var contextID: UUID
    var action: ((UUID) -> Bool)?
    @State private var targeted = false
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 12).stroke(targeted ? Palette.mint : .clear, lineWidth: 3))
            .dropDestination(for: String.self) { items, _ in
                guard items.count == 1, let id = LineupDrag.player(in: items[0], contextID: contextID) else {
                    return false
                }
                return action?(id) ?? false
            } isTargeted: {
                targeted = $0 && action != nil
            }
    }
}

/// Renders formation slots from a Match snapshot and forwards tap/drop callbacks.
/// Selection and mutations belong to the caller; this view can also display a lineup draft.
struct LivePitch: View {
    var match: Match
    var elapsed: Double
    var landscape = false
    var fillSpace = false
    var onDropPlayer: ((UUID, Int) -> Bool)?
    var onSelectSlot: ((Int) -> Void)?
    var onSelect: (UUID) -> Void
    var selectedPlayerID: UUID?
    var tapToSwap = false
    var body: some View {
        if fillSpace { pitch } else { pitch.aspectRatio(landscape ? 1.4 : 0.72, contentMode: .fit) }
    }
    private var pitch: some View {
        GeometryReader { geo in
            let positions = Formation.positions(for: match.format, id: match.formationID)
            ZStack {
                if landscape {
                    PitchMarkings().frame(width: geo.size.height, height: geo.size.width).rotationEffect(.degrees(90))
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    PitchMarkings()
                }
                ForEach(positions.indices, id: \.self) { slot in
                    let p = positions[slot]
                    let row = positions.filter { abs($0.y - p.y) < 0.001 }
                    let rowCount = row.count
                    let left = row.map(\.x).min() ?? p.x, right = row.map(\.x).max() ?? p.x
                    let compactCross =
                        right > left
                        ? 22 + (p.x - left) * max(0, geo.size.height - 44) / (right - left) : geo.size.height / 2
                    let staggered =
                        Formation.option(for: match.format, id: match.formationID).map {
                            $0.shapeID == "4-3-3" && $0.id != "4-3-3" && $0.id != "4-3-3:wide"
                        } ?? false
                    let member = match.players.first { $0.slot == slot }
                    let role =
                        member.map { match.position(of: $0) }
                        ?? Formation.roles(for: match.format, id: match.formationID)[slot]
                    if member != nil || onSelectSlot != nil {
                        Button {
                            if let onSelectSlot { onSelectSlot(slot) } else if let member { onSelect(member.id) }
                        } label: {
                            if let member {
                                let compatible = member.player.playablePositions.contains(role)
                                if (landscape && geo.size.height < 320) || (!landscape && geo.size.height < 420) {
                                    HStack(spacing: 4) {
                                        KitBadge(number: member.player.number, keeper: role == "GK", size: 30)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9).stroke(
                                                    compatible ? .white.opacity(0.8) : Palette.amber, lineWidth: 1))
                                        VStack(spacing: 1) {
                                            Text(member.player.name).font(.system(size: 10, weight: .semibold))
                                                .lineLimit(1)
                                            Text(match.positionLabel(role)).font(.system(size: 9, weight: .bold))
                                                .lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(
                                                    compatible ? .white.opacity(0.8) : Palette.amber)
                                        }.foregroundStyle(.white)
                                    }.padding(.horizontal, 4).frame(minWidth: 44, minHeight: 44)
                                        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                        .contentShape(Rectangle())
                                } else {
                                    VStack(spacing: 2) {
                                        KitBadge(
                                            number: member.player.number, keeper: role == "GK",
                                            size: geo.size.width > 350 ? 40 : 33
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12).stroke(
                                                compatible ? .white.opacity(0.8) : Palette.amber, lineWidth: 1.5))
                                        Text(member.player.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(.black.opacity(0.16), in: Capsule())
                                        Text(match.positionLabel(role)).font(.system(size: 9, weight: .bold)).lineLimit(
                                            1
                                        ).minimumScaleFactor(0.65).foregroundStyle(
                                            compatible ? .white.opacity(0.8) : Palette.amber)
                                    }.frame(minWidth: 44, minHeight: 64).contentShape(Rectangle())
                                }
                            } else {
                                VStack(spacing: 2) {
                                    Image(systemName: "plus.circle.dashed").font(.title2)
                                    Text(match.positionLabel(role)).font(.caption.bold()).lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                }.foregroundStyle(.white).frame(width: 54, height: 54)
                                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }.buttonStyle(.plain)
                            .frame(
                                width: landscape
                                    ? min(130, max(44, geo.size.width * (staggered ? 0.16 : 0.20)))
                                    : min(90, max(44, geo.size.width / CGFloat(rowCount + 1) - 6))
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 12).fill(
                                    member != nil && member?.id == selectedPlayerID
                                        ? Palette.mint.opacity(0.25) : .clear)
                            )
                            .overlay {
                                if let member, member.id == selectedPlayerID {
                                    RoundedRectangle(cornerRadius: 12).stroke(Palette.mint, lineWidth: 3)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "checkmark.circle.fill").font(
                                                .system(size: 16, weight: .bold)
                                            )
                                            .foregroundStyle(Palette.green, Palette.mint).offset(x: 4, y: -4)
                                        }.allowsHitTesting(false)
                                }
                            }
                            .modifier(
                                LineupDragSource(
                                    playerID: member?.id ?? match.id, contextID: match.id,
                                    enabled: member != nil && onDropPlayer != nil)
                            )
                            .modifier(
                                LineupDropTarget(
                                    contextID: match.id,
                                    action: onDropPlayer.map { handler in { id in handler(id, slot) } })
                            )
                            .position(
                                x: (landscape ? 1 - p.y : p.x) * geo.size.width,
                                y: landscape && geo.size.height < 320
                                    ? compactCross : (landscape ? p.x : p.y) * geo.size.height
                            )
                            .accessibilityIdentifier("pitchSlot-\(slot)")
                            .accessibilityLabel(
                                member.map {
                                    "\($0.player.name), number \($0.player.number), \(match.positionLabel(role)), \(Int($0.played(at:elapsed)/60)) minutes"
                                } ?? "Open \(match.positionLabel(role)) Position"
                            )
                            .accessibilityValue(member != nil && member?.id == selectedPlayerID ? "Selected" : "")
                            .accessibilityAddTraits(member != nil && member?.id == selectedPlayerID ? .isSelected : [])
                            .accessibilityHint(
                                tapToSwap
                                    ? "Tap to select, then tap another player to swap. Tap again to cancel."
                                    : onSelectSlot != nil
                                        ? "Choose a player for this position. You can also drag a player here."
                                        : "Select to substitute")
                    }
                }
                VStack {
                    HStack {
                        Label("Attack", systemImage: landscape ? "arrow.right" : "arrow.up").font(
                            .system(size: 9, weight: .bold)
                        ).tracking(2)
                        Spacer()

                        Text(Formation.title(for: match.format, id: match.formationID)).font(
                            .system(size: 10, weight: .bold))
                    }
                    Spacer()
                }.foregroundStyle(.white.opacity(0.7)).padding(13).allowsHitTesting(false)
            }
        }
    }
}

/// Compact visual chrome with a minimum 44-point touch target.
struct CompactActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var prominent = false
    var translucent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.caption, design: .rounded, weight: .semibold))
            .labelStyle(CompactControlLabelStyle()).multilineTextAlignment(.center)
            .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(prominent ? .white : (translucent ? Color.primary : Palette.action))
            .background(
                prominent
                    ? Palette.green
                    : (translucent && !reduceTransparency ? Color.primary.opacity(0.045) : Palette.background),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

/// Shared translucent toolbar treatment, with an opaque accessibility fallback.
struct FloatingToolbarSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 18).fill(Palette.card)
            } else {
                RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
    }
}

struct RevealToolsButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: "slider.horizontal.3") }
            .buttonStyle(CompactActionStyle(translucent: true)).fixedSize()
            .padding(4).modifier(FloatingToolbarSurface())
            .accessibilityHint("Show the toolbar without changing the game or board")
    }
}

private struct CompactControlLabelStyle: LabelStyle {
    @Environment(\.dynamicTypeSize) private var typeSize
    func makeBody(configuration: Configuration) -> some View {
        if typeSize.isAccessibilitySize {
            configuration.title
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    configuration.icon
                    configuration.title
                }.fixedSize(horizontal: true, vertical: false)
                configuration.title.fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Shared visible and VoiceOver selection for match-day bench controls.
struct MatchPlayerSelection: ViewModifier {
    var selected: Bool
    func body(content: Content) -> some View {
        content
            .background(selected ? Palette.mint.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.mint : .clear, lineWidth: 3)
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green, Palette.mint)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityValue(selected ? "Selected" : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("Tap to select, then tap a field player to swap. Tap again to cancel.")
    }
}
