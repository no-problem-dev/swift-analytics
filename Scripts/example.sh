#!/bin/sh
# サンプルアプリ（Example/）を組み立てて動かす。
#
#   ./Scripts/example.sh generate   .xcodeproj を作る（生成物・gitignore 済み）
#   ./Scripts/example.sh run        シミュレータで起動して手で触る
#   ./Scripts/example.sh test       XCUITest を回す（Example/HAZARDS.md の検証）
#
# ユニットテストで書けないもの（SwiftUI が本当に信号を送るか）だけをここで確かめる。
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
project="$here/Example/AnalyticsProbe.xcodeproj"
# **名前ではなく id で指す。** 名前指定は、同じ名前の端末が複数のランタイムに
# あると解決に失敗することがある（この環境で実際に失敗した）。
# SIMULATOR に名前を渡せばそれを優先し、無ければ使える iPhone を 1 つ選ぶ。
device_id=$(
  xcrun simctl list devices available --json |
  python3 -c '
import json, sys, os
want = os.environ.get("SIMULATOR", "iPhone")
data = json.load(sys.stdin)["devices"]
for runtime in sorted(data, reverse=True):
    for d in data[runtime]:
        if want in d["name"]:
            print(d["udid"]); raise SystemExit
raise SystemExit("no simulator matching: " + want)
'
) || { echo "使えるシミュレータが見つかりません（SIMULATOR で名前を指定できます）" >&2; exit 2; }

generate() {
  command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen が要ります: brew install xcodegen" >&2; exit 2; }
  (cd "$here/Example" && xcodegen generate)
}

case "${1:-test}" in
  generate) generate ;;
  run)
    generate
    xcodebuild -project "$project" -scheme AnalyticsProbe \
      -destination "id=$device_id" \
      -derivedDataPath "$here/Example/.build" build
    ;;
  test)
    generate
    xcodebuild test -project "$project" -scheme AnalyticsProbe \
      -destination "id=$device_id" \
      -derivedDataPath "$here/Example/.build"
    ;;
  *) echo "usage: $0 {generate|run|test}" >&2; exit 64 ;;
esac
