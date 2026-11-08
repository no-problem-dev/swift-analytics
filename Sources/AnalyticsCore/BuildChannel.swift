import Foundation

/// Where this build came from: the developer's machine, TestFlight, or the App Store.
///
/// It goes into every batch as `channel` (`Schema/common/ENVELOPE.md`), so the receiver can keep
/// test builds out of the numbers without anyone remembering to.
///
/// ``current`` reads the running app. The decision itself is ``resolve(isDebugBuild:isSimulator:hasEmbeddedProvisioningProfile:receiptName:)``,
/// a pure function, so it can be checked on a Mac with no app around it.
public enum BuildChannel: String, Sendable, CaseIterable, Codable {

    /// A Debug build, a simulator, or a build signed for development or ad hoc — anything not
    /// handed out by Apple.
    case debug

    /// Installed from TestFlight (the App Store receipt is a sandbox one).
    case testflight

    /// Installed from the App Store.
    case appstore

    /// Decides the channel from what the running app can see.
    ///
    /// - Parameters:
    ///   - isDebugBuild: Compiled with `DEBUG`
    ///   - isSimulator: Running in a simulator
    ///   - hasEmbeddedProvisioningProfile: The bundle carries `embedded.mobileprovision`. Apple
    ///     strips it from builds it distributes, so its presence means development or ad hoc
    ///   - receiptName: The last path component of `Bundle.appStoreReceiptURL`. TestFlight
    ///     installs get `sandboxReceipt`, the App Store gets `receipt`
    public static func resolve(
        isDebugBuild: Bool,
        isSimulator: Bool,
        hasEmbeddedProvisioningProfile: Bool,
        receiptName: String?
    ) -> BuildChannel {
        if isDebugBuild || isSimulator || hasEmbeddedProvisioningProfile { return .debug }
        if receiptName == "sandboxReceipt" { return .testflight }
        return .appstore
    }

    /// The channel of the running app, worked out once.
    public static let current: BuildChannel = {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return resolve(
            isDebugBuild: isDebugBuild,
            isSimulator: isSimulator,
            hasEmbeddedProvisioningProfile: Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil,
            receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent
        )
    }()
}
