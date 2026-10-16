import SwiftUI

/// The scrolling chat feed. Auto-follows the newest bubble unless the user has
/// scrolled up to read something, which is the behaviour every chat app has
/// trained people to expect.
struct BubbleFeedView: View {
    @Environment(FlightEngine.self) private var engine

    var collapsed: Bool

    @State private var pinnedToBottom = true
    @State private var filter: Bubble.Kind?

    private var visible: [Bubble] {
        guard let filter else { return engine.bubbles }
        return engine.bubbles.filter { $0.kind == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !collapsed { filterBar }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        Color.clear.frame(height: 2)

                        ForEach(visible) { bubble in
                            BubbleView(bubble: bubble,
                                       isHighlighted: engine.focusBubbleID == bubble.id)
                                .id(bubble.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.94, anchor: .bottomLeading)),
                                    removal: .opacity
                                ))
                        }

                        if visible.isEmpty { emptyState }

                        Color.clear.frame(height: 14).id(bottomAnchor)
                    }
                    .padding(.horizontal, 13)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: visible.count)
                }
                .scrollIndicators(.hidden)
                .onChange(of: engine.bubbles.count) { _, _ in
                    guard pinnedToBottom else { return }
                    withAnimation(.easeOut(duration: 0.4)) {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: engine.focusBubbleID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(id, anchor: .center) }
                    // Clear the highlight after a beat so it reads as a flash.
                    Task {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        engine.focusBubbleID = nil
                    }
                }
                .simultaneousGesture(
                    DragGesture().onChanged { value in
                        // Dragging down = reading history; stop auto-following.
                        if value.translation.height > 24 { pinnedToBottom = false }
                    }
                )
                .onTapGesture(count: 2) {
                    pinnedToBottom = true
                    withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !pinnedToBottom { jumpToLatest }
            }
        }
    }

    private var bottomAnchor: String { "feed-bottom" }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                FilterChip(label: "All", glyph: "✳️",
                           isOn: filter == nil, tint: Theme.slate) { filter = nil }
                ForEach([Bubble.Kind.poi, .aviation, .advice, .milestone, .stat], id: \.rawValue) { kind in
                    let count = engine.bubbles.filter { $0.kind == kind }.count
                    if count > 0 {
                        FilterChip(label: kind.speaker, glyph: kind.glyph,
                                   isOn: filter == kind, tint: kind.tint) {
                            filter = filter == kind ? nil : kind
                        }
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🛰️").font(.system(size: 30))
            Text(filter == nil
                 ? "Watching the ground. First fact incoming."
                 : "Nothing under this filter yet.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.slate)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var jumpToLatest: some View {
        Button {
            pinnedToBottom = true
            engine.focusBubbleID = engine.bubbles.last?.id
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down").font(.system(size: 10, weight: .black))
                Text("Latest").font(Theme.title(12))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Theme.cyan))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 14)
        .padding(.bottom, 10)
        .transition(.scale.combined(with: .opacity))
    }
}

struct FilterChip: View {
    var label: String
    var glyph: String
    var isOn: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(glyph).font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isOn ? Theme.ink : .white.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule().fill(isOn ? tint : Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }
}
