import AnalyticsCore
import AnalyticsSwiftUI
import SwiftUI

/// 計測の繋ぎを実際に動かして確かめるためのアプリ。**危険ごとに 1 画面**（`Example/HAZARDS.md`）。
///
/// 画面の一番上に「いま何が何回出たか」を常に出しておき、XCUITest はその文字列だけを読む。
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
                // H1/H4/H5: 画面の到達・押し戻り・素早い離脱
                Tab("画面", systemImage: "1.square", value: 0) {
                    ScreenProbe()
                }
                // H3/H6/H8: スクロールの中の要素
                Tab("一覧", systemImage: "2.square", value: 1) {
                    ListProbe()
                }
                // H2/H7: シート
                Tab("シート", systemImage: "3.square", value: 2) {
                    SheetProbe()
                }
            }
        }
    }

    /// **XCUITest が読む唯一の面。** 絵ではなく数字で確かめる。
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

// MARK: - H1 / H4 / H5 画面

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

// MARK: - H3 / H6 / H8 一覧

private struct ListProbe: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<40, id: \.self) { index in
                    row(index)
                }
                // **一覧のいちばん下に置く。** 初期表示では確実に画面の外にある。
                // ここが 1 以上になったら、遅延生成の行にも可視の通知が来ているということで、
                // 数字に「見ていない露出」が混ざる（H3）。
                //
                // 先頭に置くと初期表示で画面内に入ってしまい、可視通知が来るのが正しくなる
                // —— 最初はそれで書いて、実装のバグと取り違えかけた。
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
            // 初期表示では確実に画面の外にある行。スクロールして初めて見える。
            // **文字を持たせて掴めるようにする** —— 図形だけだと XCUITest から引きにくい
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("probe.row.target")
                .trackImpression(ProbeEvent.row, dwell: ProbeConfig.dwell)
        } else {
            content
        }
    }
}

// MARK: - H2 / H7 シート

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
            // コンテナに identifier を付けると子要素が集約されて、中のボタンが
            // XCUITest から見えなくなる。**計測は付けるが、名前は付けない。**
            .trackScreen(ProbeEvent.sheet, dwell: ProbeConfig.dwell)
        }
    }
}
