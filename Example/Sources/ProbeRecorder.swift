import AnalyticsCore
import Foundation
import Observation

/// A client that only counts what came out and puts the counts on screen.
///
/// **This is the number the XCUITests read.** Eyeballing a screenshot cannot find a difference in
/// counts — "twice where once was meant" and "came back but never counted again" both look
/// identical in a picture.
@MainActor
@Observable
final class ProbeRecorder: AnalyticsClient {
    private(set) var counts: [String: Int] = [:]

    nonisolated func track(_ event: any AnalyticsEvent) {
        let name = event.name
        Task { @MainActor in counts[name, default: 0] += 1 }
    }

    nonisolated func setUserProperty(_ property: any AnalyticsUserProperty) {}

    func reset() { counts.removeAll() }

    /// One line holding the count for every case, and the only thing the XCUITests look at.
    ///
    /// Rendered as `screen=1 sheet=0 row=0 offscreen=0`.
    var readout: String {
        ProbeEvent.allCases
            .map { "\($0.rawValue)=\(counts[$0.rawValue] ?? 0)" }
            .joined(separator: " ")
    }
}

/// Settings that can be changed from the launch arguments.
///
/// Checking "leaving before a second has passed does not count" needs **a guarantee that the
/// test's interaction finishes faster than the dwell**. Simulator transition animations stretch
/// with the device and the load, so that one case extends the dwell to be sure of arriving in
/// time.
enum ProbeConfig {
    static var dwell: TimeInterval {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-dwell"), index + 1 < arguments.count,
              let value = Double(arguments[index + 1]) else { return 1.0 }
        return value
    }
}
