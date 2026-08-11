import AnalyticsCore
import SwiftUI

private struct AnalyticsClientKey: EnvironmentKey {
    static let defaultValue: any AnalyticsClient = NoopAnalytics()
}

public extension EnvironmentValues {

    /// The way a view reaches measurement.
    ///
    /// The default is ``AnalyticsCore/NoopAnalytics``, so previews and tests run with nothing
    /// wired up.
    ///
    /// It sits in the environment rather than in a store because firing points are view events —
    /// a screen appeared, a button was pressed. Held in a store, a screen with no state of its own
    /// would need one purely in order to measure.
    var analytics: any AnalyticsClient {
        get { self[AnalyticsClientKey.self] }
        set { self[AnalyticsClientKey.self] = newValue }
    }
}

public extension View {

    /// Hands the real client to this view and everything below it.
    ///
    /// **The composition root does this once, at the root.**
    func analytics(_ client: any AnalyticsClient) -> some View {
        environment(\.analytics, client)
    }
}
