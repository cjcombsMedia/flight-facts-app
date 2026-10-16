import XCTest
import SwiftUI
@testable import Flight_Facts

/// Renders the Lock Screen Live Activity layout to a PNG so it can be checked by
/// eye without a device. Set FLIGHTFACTS_RENDER_DIR to choose where it goes.
@MainActor
final class LockScreenRenderTests: XCTestCase {

    func testRenderLockScreenLayouts() throws {
        let attributes = FlightActivityAttributes(routeTitle: "PHX → MEX", seatLabel: "Left seat")
        var estimated = FlightActivityAttributes.ContentState.preview
        estimated.gpsEstimated = true
        estimated.phaseRaw = "descent"
        estimated.phaseTitle = "Descending"
        estimated.phaseGlyph = "📉"
        estimated.factGlyph = "🎯"
        estimated.factTitle = "Starting down"
        estimated.factBody = "Top of descent. Tray tables up, seat backs forward, belt fastened, and finish that drink."

        let stack = VStack(spacing: 14) {
            ForEach([FlightActivityAttributes.ContentState.preview, estimated], id: \.self) { state in
                FlightLockScreenView(attributes: attributes, state: state)
                    .frame(width: 364)
                    .background(ActivityPalette.ink.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: stack)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 200)

        let dir = ProcessInfo.processInfo.environment["FLIGHTFACTS_RENDER_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("lockscreen.png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("LOCKSCREEN_RENDER \(url.path)")
    }
}
