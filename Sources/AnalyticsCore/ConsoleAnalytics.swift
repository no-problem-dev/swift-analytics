import Foundation
import os

/// A client that writes each occurrence to the unified log instead of sending it anywhere.
///
/// A destination's own debug view lags behind, so this is what to use to follow what a particular
/// interaction just produced. It does not replace the real send — run both, side by side, with
/// ``MultiplexAnalytics``.
///
/// ```swift
/// #if DEBUG
/// let analytics = MultiplexAnalytics([ConsoleAnalytics(), firebase])
/// #else
/// let analytics = firebase
/// #endif
/// ```
///
/// Everything is logged at the info level with `privacy: .public`. What it carries is limited to
/// enumerated cases and numbers (``AnalyticsValue``), so text a person wrote cannot get in.
public struct ConsoleAnalytics: AnalyticsClient {

    private let logger: Logger

    /// - Parameters:
    ///   - subsystem: Logger subsystem these lines are filed under; pass the app's own identifier
    ///     to have them show up with the rest of its logging
    ///   - category: Logger category, used to narrow a Console filter to measurement alone
    public init(
        subsystem: String = "dev.no-problem.swift-analytics",
        category: String = "analytics"
    ) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func track(_ event: any AnalyticsEvent) {
        logger.info("event \(event.debugLine, privacy: .public)")
    }

    public func setUserProperty(_ property: any AnalyticsUserProperty) {
        logger.info("property \(property.name, privacy: .public)=\(property.value, privacy: .public)")
    }
}
