import AnalyticsCore
import AnalyticsSwiftUI
import SwiftUI

/// An app that runs the measurement wiring for real so it can be checked, one screen per hazard.
///
/// The hazards are listed in `Example/HAZARDS.md`. What has come out, and how many times, is
/// always on show at the top of the window, and the XCUITests read only that one string.
@main
struct ProbeApp: App {
    @State private var recorder = ProbeRecorder()

    var body: some Scene {
        WindowGroup {
            ProbeRoot(recorder: recorder)
                .analytics(recorder)
        }
    }
}

struct ProbeRoot: View {
    let recorder: ProbeRecorder
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            readout
            TabView(selection: $tab) {
                // H1/H4/H5: reaching a screen, popping back, leaving quickly
                Tab("画面", systemImage: "1.square", value: 0) {
                    ScreenProbe()
                }
                // H3/H6/H8: an element inside a scrolling container
                Tab("一覧", systemImage: "2.square", value: 1) {
                    ListProbe()
                }
                // H2/H7: sheets
                Tab("シート", systemImage: "3.square", value: 2) {
                    SheetProbe()
                }
            }
        }
    }

    /// **The only surface the XCUITests read.** Checked as numbers, not as a picture.
    private var readout: some View {
        HStack {
            Text(recorder.readout)
                .font(.system(.caption, design: .monospaced))
                .accessibilityIdentifier("probe.readout")
            Spacer()
            Button("消す") { recorder.reset() }
                .accessibilityIdentifier("probe.reset")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

// MARK: - H1 / H4 / H5 screens

private struct ScreenProbe: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("計測される画面へ") {
                    Color.teal
                        .ignoresSafeArea()
                        .overlay(Text("計測される画面").foregroundStyle(.white))
                        .navigationTitle("計測される画面")
                        .accessibilityIdentifier("probe.screen.body")
                        .trackScreen(ProbeEvent.screen, dwell: ProbeConfig.dwell)
                }
                .accessibilityIdentifier("probe.screen.push")
            }
            .navigationTitle("画面")
        }
    }
}

// MARK: - H3 / H6 / H8 lists

private struct ListProbe: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<40, id: \.self) { index in
                    row(index)
                }
                // **Placed at the very bottom of the list.** It is reliably off screen on first
                // display. If this reaches 1 or more, visibility notifications are arriving for
                // lazily built rows too, and exposures nobody saw are mixed into the numbers (H3).
                //
                // At the top it would be on screen on first display, where a visibility
                // notification is the correct behaviour — that is how it was written first, and it
                // was nearly mistaken for a bug in the implementation.
                Text("末尾")
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier("probe.offscreen")
                    .trackImpression(ProbeEvent.offscreen, dwell: ProbeConfig.dwell)
            }
            .padding()
        }
        .accessibilityIdentifier("probe.list")
        .navigationTitle("一覧")
    }

    @ViewBuilder
    private func row(_ index: Int) -> some View {
        let content = RoundedRectangle(cornerRadius: 12)
            .fill(index == 30 ? Color.orange : Color.gray.opacity(0.2))
            .frame(height: 120)
            .overlay(Text("row \(index)"))

        if index == 30 {
            // A row reliably off screen on first display; only visible once it is scrolled to.
            // **Give it text so it can be grabbed** — a bare shape is hard to reach from XCUITest
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("probe.row.target")
                .trackImpression(ProbeEvent.row, dwell: ProbeConfig.dwell)
        } else {
            content
        }
    }
}

// MARK: - H2 / H7 sheets

private struct SheetProbe: View {
    @State private var isPresented = false

    var body: some View {
        VStack(spacing: 16) {
            Button("シートを出す") { isPresented = true }
                .accessibilityIdentifier("probe.sheet.present")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isPresented) {
            VStack(spacing: 16) {
                Text("シートの中")
                Button("閉じる") { isPresented = false }
                    .accessibilityIdentifier("probe.sheet.dismiss")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // An identifier on the container merges its children, which hides the button inside
            // from XCUITest. **Measure it, but do not name it.**
            .trackScreen(ProbeEvent.sheet, dwell: ProbeConfig.dwell)
        }
    }
}
