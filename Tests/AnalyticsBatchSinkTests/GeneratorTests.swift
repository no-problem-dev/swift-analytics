#if os(macOS)
import Foundation
import Testing

/// The generator's own tests (`Scripts/tests/`), run from `swift test` so that the two commands in
/// CONTRIBUTING.md cover the Python side as well.
@Suite("カタログの生成器")
struct GeneratorTests {

    @Test("analytics-gen.py の検査と JSON の出力")
    func generatorUnitTests() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "unittest", "discover", "-s", "Scripts/tests"]
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardError = output
        process.standardOutput = output
        try process.run()
        let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(log)")
    }
}
#endif
