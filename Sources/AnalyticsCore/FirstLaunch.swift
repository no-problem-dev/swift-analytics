import Foundation

/// 初回起動の時刻を 1 度だけ刻み、そこからの経過を数える。
///
/// 「その端末で初めて起きたこと」が**何日目に起きたか**は、初回体験の読み方を変える ——
/// その場でやったのか、後日思い出してやったのかで、直すべき場所が違う。
///
/// 状態は `UserDefaults`。消えても最悪もう一度刻むだけで、アプリの動作には影響しない。
public enum FirstLaunch {

    private static let key = "analytics.firstLaunchAt"

    /// 初回起動の時刻を 1 度だけ記録する。**アプリの起動経路で毎回呼んでよい**（2 回目以降は何もしない）。
    ///
    /// - Parameters:
    ///   - defaults: 置き場所
    ///   - now: 現在時刻。テストから固定できるようにしてある
    public static func markIfNeeded(defaults: UserDefaults = .standard, now: Date = Date()) {
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: key)
    }

    /// 初回起動からの日数。記録が無ければ `0`（初日として扱う）。
    public static func daysSince(defaults: UserDefaults = .standard, now: Date = Date()) -> Int {
        let stored = defaults.double(forKey: key)
        guard stored > 0 else { return 0 }
        let elapsed = now.timeIntervalSince1970 - stored
        return max(0, Int(elapsed / 86_400))
    }

    /// 記録を消す（テストと開発メニュー用）。
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
