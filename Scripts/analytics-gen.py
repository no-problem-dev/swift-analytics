#!/usr/bin/env python3
"""計測カタログ（analytics.yaml）から Swift を書き出し、実装とのズレを落とす。

スキーマの仕様は ``Schema/SCHEMA.md``。

    analytics-gen.py generate --schema analytics.yaml --out Generated/AppAnalytics.swift
    analytics-gen.py check    --schema analytics.yaml --out Generated/AppAnalytics.swift
    analytics-gen.py audit    --schema analytics.yaml --sources Sources/

**生成は人の手元で走らせ、生成物をコミットする。** ビルド時に生成しないのは、計測の変更が
「何を測ることにしたか」の変更であり、**差分が唯一のレビュー材料**だから。生成物が
リポジトリに現れない作りにすると、その差分を誰も見られなくなる。

`check` と `audit` を CI に置けば、生成し忘れも配線のズレも落ちる。
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

HEADER = "// このファイルは analytics-gen.py が書き出しています。手で編集しないでください。"

# GA4（Firebase Analytics）の制約。破った送信は成功に見えて捨てられる。
GA4_NAME_LIMIT = 40
GA4_PARAMETER_LIMIT = 25
GA4_VALUE_LIMIT = 100
GA4_RESERVED_PREFIXES = ("firebase_", "google_", "ga_")
GA4_RESERVED_NAMES = {
    "ad_activeview", "ad_click", "ad_exposure", "ad_impression", "ad_query", "ad_reward",
    "adunit_exposure", "app_background", "app_clear_data", "app_exception", "app_remove",
    "app_store_refund", "app_store_subscription_cancel", "app_store_subscription_convert",
    "app_store_subscription_renew", "app_update", "app_upgrade", "dynamic_link_app_open",
    "dynamic_link_app_update", "dynamic_link_first_open", "error", "firebase_campaign",
    "first_open", "first_visit", "in_app_purchase", "notification_dismiss",
    "notification_foreground", "notification_open", "notification_receive", "os_update",
    "session_start", "session_start_with_rollout", "user_engagement",
}

KINDS = {"screen", "impression", "interaction", "outcome"}
SCOPES = {"session", "install", "always"}
PARAM_TYPES = {"enum", "count", "number", "flag", "bucket"}


class SchemaError(Exception):
    """スキーマが仕様に反している。**生成する前に落とす。**"""


# ---------------------------------------------------------------- YAML（部分集合）

# **依存を足さないために、スキーマが使う範囲だけを読む。**
#
# PyYAML を要求すると、最近の macOS では PEP 668 に阻まれて `pip install` が通らず、
# 「まず仮想環境を作る」から始まることになる。カタログを直すたびにその手順を踏ませるのは、
# カタログを直しにくくするのと同じ。
#
# 代わりに、**範囲外の書き方をすべて拒む**厳格な読み取りにしてある。推測はしない
# （アンカー・複数行文字列・入れ子のフロー・タブは、黙って解釈せずエラーにする）。
# 読める形は Schema/SCHEMA.md に書いてあるものが全部。

def parse_yaml(text: str) -> dict:
    lines: list[tuple[int, str, int]] = []
    for number, raw in enumerate(text.splitlines(), start=1):
        if "\t" in raw.split("#")[0]:
            raise SchemaError(f"{number} 行目: タブは使えません（インデントは半角空白 2 つ）")
        stripped = _strip_comment(raw)
        if not stripped.strip():
            continue
        indent = len(stripped) - len(stripped.lstrip(" "))
        if indent % 2 != 0:
            raise SchemaError(f"{number} 行目: インデントは 2 の倍数にしてください")
        lines.append((indent, stripped.strip(), number))
    value, index = _parse_block(lines, 0, 0)
    if index != len(lines):
        raise SchemaError(f"{lines[index][2]} 行目: 解釈できません（{lines[index][1]}）")
    return value if isinstance(value, dict) else {}


def _strip_comment(raw: str) -> str:
    out, quote = [], None
    for char in raw:
        if quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "#":
            break
        out.append(char)
    return "".join(out).rstrip()


def _parse_block(lines, index: int, indent: int):
    if index >= len(lines):
        return None, index
    if lines[index][1].startswith("- "):
        return _parse_list(lines, index, indent)
    return _parse_map(lines, index, indent)


def _parse_map(lines, index: int, indent: int):
    result: dict = {}
    while index < len(lines):
        line_indent, content, number = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent:
            raise SchemaError(f"{number} 行目: 予期しない字下げ（{content}）")
        if content.startswith("- "):
            break
        if ":" not in content:
            raise SchemaError(f"{number} 行目: `鍵: 値` の形にしてください（{content}）")
        key, _, rest = content.partition(":")
        key, rest = key.strip(), rest.strip()
        index += 1
        if rest:
            result[key] = _scalar(rest, number)
        else:
            child, index = _parse_block(lines, index, indent + 2)
            result[key] = child if child is not None else {}
    return result, index


def _parse_list(lines, index: int, indent: int):
    result: list = []
    while index < len(lines):
        line_indent, content, number = lines[index]
        if line_indent < indent or not content.startswith("- "):
            break
        if line_indent > indent:
            raise SchemaError(f"{number} 行目: 予期しない字下げ（{content}）")
        item = content[2:].strip()
        index += 1
        if ":" in item and not item.startswith(("\"", "'", "[")):
            # `- key: value` から始まるマップ。続く行を同じ深さの続きとして読む
            key, _, rest = item.partition(":")
            entry: dict = {}
            if rest.strip():
                entry[key.strip()] = _scalar(rest.strip(), number)
            else:
                child, index = _parse_block(lines, index, indent + 4)
                entry[key.strip()] = child if child is not None else {}
            rest_map, index = _parse_map(lines, index, indent + 2)
            entry.update(rest_map)
            result.append(entry)
        else:
            result.append(_scalar(item, number))
    return result, index


def _scalar(text: str, number: int):
    if text.startswith("[") and text.endswith("]"):
        inner = text[1:-1].strip()
        return [] if not inner else [_scalar(part.strip(), number) for part in inner.split(",")]
    if text.startswith(("\"", "'")) and text.endswith(text[0]) and len(text) >= 2:
        return text[1:-1]
    if text in {"true", "false"}:
        return text == "true"
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if text.startswith(("|", ">", "&", "*", "{")):
        raise SchemaError(f"{number} 行目: この書き方は読みません（{text}）。SCHEMA.md の範囲で書いてください")
    return text


# ---------------------------------------------------------------- 名前の変換

def lower_camel(snake: str) -> str:
    head, *rest = snake.split("_")
    return head + "".join(part.capitalize() for part in rest)


def upper_camel(snake: str) -> str:
    return "".join(part.capitalize() for part in snake.split("_"))


# ---------------------------------------------------------------- スキーマ

@dataclass
class Parameter:
    key: str
    type: str
    values: list[str] = field(default_factory=list)
    edges: list[int] = field(default_factory=list)
    description: str = ""
    type_name: str = ""

    @property
    def swift_label(self) -> str:
        """Swift 側の引数ラベルと束縛名。

        送信先へ渡す鍵は `key`（snake_case）のままだが、**Swift の引数ラベルまで
        snake_case にすると呼び出し側が読みにくくなる**ので、ここで変換する。
        """
        return lower_camel(self.key)

    @property
    def swift_type_name(self) -> str:
        """生成する入れ子 enum の名前。

        既定は鍵から作るが、**複数の出来事が同じ鍵を別の意味で使うことがある**
        （`noti_priming_result.outcome` と `teaser_result.outcome` は値が違う）。
        そのときは `type_name` で名前を分ける。同じ名前で値が違えば生成前に落ちる。
        """
        return self.type_name or upper_camel(self.key)


@dataclass
class Event:
    name: str
    case: str
    kind: str
    dedup: str
    description: str = ""
    trigger: str = ""
    parameters: list[Parameter] = field(default_factory=list)


@dataclass
class UserProperty:
    name: str
    case: str
    type: str
    values: list[str] = field(default_factory=list)
    edges: list[int] = field(default_factory=list)
    description: str = ""
    type_name: str = ""

    @property
    def swift_type_name(self) -> str:
        return self.type_name or upper_camel(self.name)


@dataclass
class Schema:
    event_type: str
    property_type: str
    module: str
    swiftui: bool
    dialect: str
    events: list[Event]
    properties: list[UserProperty]


def load(path: Path) -> Schema:
    raw = parse_yaml(path.read_text(encoding="utf-8"))
    swift = raw.get("swift", {})
    schema = Schema(
        event_type=swift.get("event_type", "AppEvent"),
        property_type=swift.get("property_type", "AppUserProperty"),
        module=swift.get("module", "App"),
        swiftui=bool(swift.get("swiftui", True)),
        dialect=raw.get("dialect", "ga4"),
        events=[_event(item) for item in raw.get("events") or []],
        properties=[_property(item) for item in raw.get("user_properties") or []],
    )
    validate(schema)
    return schema


def _event(item: dict) -> Event:
    name = _require(item, "name")
    kind = _require(item, "kind")
    dedup = _require(item, "dedup")
    return Event(
        name=name,
        case=item.get("case") or lower_camel(name),
        kind=kind,
        dedup=dedup,
        description=item.get("description", ""),
        trigger=item.get("trigger", ""),
        parameters=[_parameter(key, value) for key, value in (item.get("parameters") or {}).items()],
    )


def _parameter(key: str, value: dict) -> Parameter:
    return Parameter(
        key=key,
        type=_require(value, "type", context=key),
        values=list(value.get("values") or []),
        edges=list(value.get("edges") or []),
        description=value.get("description", ""),
        type_name=str(value.get("type_name") or ""),
    )


def _property(item: dict) -> UserProperty:
    name = _require(item, "name")
    return UserProperty(
        name=name,
        case=item.get("case") or lower_camel(name),
        type=_require(item, "type", context=name),
        values=list(item.get("values") or []),
        edges=list(item.get("edges") or []),
        description=item.get("description", ""),
        type_name=str(item.get("type_name") or ""),
    )


def _require(item: dict, key: str, context: str = "") -> str:
    value = item.get(key)
    if not value:
        where = f"（{context}）" if context else ""
        raise SchemaError(f"{key} が要ります{where}: {item}")
    return str(value)


# ---------------------------------------------------------------- 検査

def validate(schema: Schema) -> None:
    problems: list[str] = []
    seen_names: dict[str, str] = {}
    seen_cases: set[str] = set()
    # 値集合は複数の出来事で共有できる。**同じ名前で中身が違うものだけを落とす。**
    value_sets: dict[str, list[str]] = {}

    for event in schema.events:
        if event.kind not in KINDS:
            problems.append(f"{event.name}: kind が {sorted(KINDS)} のどれでもない（{event.kind}）")
        if event.dedup not in SCOPES:
            problems.append(f"{event.name}: dedup が {sorted(SCOPES)} のどれでもない（{event.dedup}）")
        # 表示を 1 露出 1 回に留めるのは trackScreen / trackImpression の仕事で、dedup の役目ではない。
        # 噛み合いの検査は「種別に合った撃ち方をしているか」（audit）へ移した。
        if event.case in seen_cases:
            problems.append(f"{event.case}: Swift の case 名が重複している")
        seen_cases.add(event.case)

        signature = f"{event.name}({','.join(sorted(p.key for p in event.parameters))})"
        if signature in seen_names:
            problems.append(f"{signature}: 同じ出来事が 2 通りに定義されている")
        seen_names[signature] = event.name

        for parameter in event.parameters:
            problems += _validate_parameter(event.name, parameter)
            if parameter.type == "enum":
                name = parameter.swift_type_name
                existing = value_sets.get(name)
                if existing is not None and existing != parameter.values:
                    problems.append(
                        f"{event.name}.{parameter.key}: 値集合 {name} が別の場所と食い違う"
                        f"（{existing} と {parameter.values}）。type_name で名前を分けてください"
                    )
                value_sets[name] = parameter.values

        if schema.dialect == "ga4":
            problems += _validate_ga4_name(event.name, reserved_names=True)
            if len(event.parameters) > GA4_PARAMETER_LIMIT:
                problems.append(f"{event.name}: パラメータが {len(event.parameters)} 個（GA4 の上限 {GA4_PARAMETER_LIMIT}）")

    for prop in schema.properties:
        if prop.type not in PARAM_TYPES:
            problems.append(f"{prop.name}: type が {sorted(PARAM_TYPES)} のどれでもない")
        if prop.type == "enum" and not prop.values:
            problems.append(f"{prop.name}: enum なのに values が無い")
        if prop.type == "bucket" and not prop.edges:
            problems.append(f"{prop.name}: bucket なのに edges が無い")
        if schema.dialect == "ga4":
            problems += _validate_ga4_name(prop.name, reserved_names=False)

    if problems:
        raise SchemaError("スキーマに問題があります:\n  - " + "\n  - ".join(problems))


def _validate_parameter(owner: str, parameter: Parameter) -> list[str]:
    problems: list[str] = []
    if parameter.type not in PARAM_TYPES:
        problems.append(f"{owner}.{parameter.key}: type が {sorted(PARAM_TYPES)} のどれでもない")
        return problems
    if parameter.type == "enum":
        if not parameter.values:
            problems.append(f"{owner}.{parameter.key}: enum なのに values が無い")
        for value in parameter.values:
            if not re.fullmatch(r"[a-z][a-z0-9_]*", value):
                problems.append(f"{owner}.{parameter.key}: 値 {value} が snake_case でない")
            if len(value) > GA4_VALUE_LIMIT:
                problems.append(f"{owner}.{parameter.key}: 値 {value} が {GA4_VALUE_LIMIT} 字を超える")
    if parameter.type == "bucket" and not parameter.edges:
        problems.append(f"{owner}.{parameter.key}: bucket なのに edges が無い")
    return problems


def _validate_ga4_name(name: str, *, reserved_names: bool) -> list[str]:
    problems: list[str] = []
    if len(name) > GA4_NAME_LIMIT:
        problems.append(f"{name}: GA4 の名前は {GA4_NAME_LIMIT} 字まで")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name):
        problems.append(f"{name}: 英字で始まる英数字と _ のみ（GA4）")
    for prefix in GA4_RESERVED_PREFIXES:
        if name.startswith(prefix):
            problems.append(f"{name}: GA4 の予約接頭辞 {prefix}")
    if reserved_names and name in GA4_RESERVED_NAMES:
        problems.append(f"{name}: GA4 の予約イベント名")
    return problems


# ---------------------------------------------------------------- 生成

def render(schema: Schema) -> str:
    out: list[str] = [
        HEADER,
        "//",
        "// 正典は analytics.yaml。**先にそちらを直してから生成する。**",
        "",
        "import AnalyticsCore",
    ]
    if schema.swiftui:
        out += ["import AnalyticsSwiftUI", "import SwiftUI"]
    out += ["", *_render_events(schema), "", *_render_properties(schema)]
    out += ["", *_render_typed_entry_points(schema)]
    return "\n".join(out) + "\n"


def _render_events(schema: Schema) -> list[str]:
    lines = [
        "/// このアプリが送れる出来事の全部。",
        "///",
        "/// 増やすときは analytics.yaml を直してから生成し直す。",
        f"public enum {schema.event_type}: AnalyticsEvent {{",
        "",
    ]
    for event in schema.events:
        if event.description:
            lines.append(f"    /// {event.description}")
        if event.trigger:
            lines.append(f"    ///")
            lines.append(f"    /// 撃つ場所: {event.trigger}")
        lines.append(f"    case {event.case}{_case_payload(event)}")
        lines.append("")

    # 値集合。**共有されているものは 1 度だけ出す**（同名で中身が違うものは validate が落とす）。
    emitted: set[str] = set()
    for event in schema.events:
        for parameter in (p for p in event.parameters if p.type == "enum"):
            if parameter.swift_type_name in emitted:
                continue
            emitted.add(parameter.swift_type_name)
            lines.append(f"    /// `{event.name}.{parameter.key}` の値。" + (parameter.description or ""))
            lines.append(f"    public enum {parameter.swift_type_name}: String, Sendable, CaseIterable {{")
            for value in parameter.values:
                case_name = lower_camel(value)
                raw = f' = "{value}"' if case_name != value else ""
                lines.append(f"        case {case_name}{raw}")
            lines.append("    }")
            lines.append("")

    lines += _render_switch("name", schema.events, lambda e: f'"{e.name}"')
    lines += _render_switch("kind", schema.events, lambda e: f".{e.kind}", type_name="EventKind")
    lines += _render_switch("dedup", schema.events, lambda e: f".{e.dedup}", type_name="DedupScope")
    lines += _render_parameters(schema.events)
    lines.append("}")
    return lines


def _case_payload(event: Event) -> str:
    if not event.parameters:
        return ""
    parts = [f"{p.swift_label}: {_swift_type(p)}" for p in event.parameters]
    return "(" + ", ".join(parts) + ")"


def _swift_type(parameter: Parameter) -> str:
    return {
        "enum": parameter.swift_type_name,
        "count": "Int",
        "number": "Double",
        "flag": "Bool",
        "bucket": "Int",
    }[parameter.type]


def _binding(event: Event) -> str:
    """`case let .x(a, b)` の束縛部分。

    `let` は `case let` 側に 1 つだけ置く —— 各要素にも付けると
    `'let' cannot appear nested inside another 'var' or 'let' pattern` で落ちる。
    """
    if not event.parameters:
        return ""
    return "(" + ", ".join(p.swift_label for p in event.parameters) + ")"


def _render_switch(name: str, events: list[Event], value, type_name: str = "String") -> list[str]:
    lines = ["", f"    public var {name}: {type_name} {{", "        switch self {"]
    for event in events:
        binding = "" if not event.parameters else "(_" + ", _" * (len(event.parameters) - 1) + ")"
        lines.append(f"        case .{event.case}{binding}: return {value(event)}")
    lines += ["        }", "    }"]
    return lines


def _render_parameters(events: list[Event]) -> list[str]:
    lines = ["", "    public var parameters: [String: AnalyticsValue] {", "        switch self {"]
    for event in events:
        if not event.parameters:
            lines.append(f"        case .{event.case}: return [:]")
            continue
        binding = _binding(event)
        entries = ", ".join(f'"{p.key}": {_value_expression(p)}' for p in event.parameters)
        lines.append(f"        case let .{event.case}{binding}: return [{entries}]")
    lines += ["        }", "    }"]
    return lines


def _value_expression(parameter: Parameter) -> str:
    key = parameter.swift_label
    return {
        "enum": f".text({key}.rawValue)",
        "count": f".count({key})",
        "number": f".number({key})",
        "flag": f".flag({key})",
        "bucket": f".bucket({key}, edges: {parameter.edges})",
    }[parameter.type]


def _render_properties(schema: Schema) -> list[str]:
    lines = [
        "/// このアプリが置ける属性の全部。",
        f"public enum {schema.property_type}: AnalyticsUserProperty {{",
        "",
    ]
    for prop in schema.properties:
        if prop.description:
            lines.append(f"    /// {prop.description}")
        payload = f"({_property_payload(prop)})" if prop.type != "flag" or True else ""
        lines.append(f"    case {prop.case}{payload}")
        lines.append("")
    for prop in (p for p in schema.properties if p.type == "enum"):
        lines.append(f"    /// `{prop.name}` の値。")
        lines.append(f"    public enum {prop.swift_type_name}: String, Sendable, CaseIterable {{")
        for value in prop.values:
            case_name = lower_camel(value)
            raw = f' = "{value}"' if case_name != value else ""
            lines.append(f"        case {case_name}{raw}")
        lines.append("    }")
        lines.append("")

    lines += ["    public var name: String {", "        switch self {"]
    for prop in schema.properties:
        lines.append(f'        case .{prop.case}: return "{prop.name}"')
    lines += ["        }", "    }", ""]

    lines += ["    public var value: String {", "        switch self {"]
    for prop in schema.properties:
        if prop.type == "enum":
            lines.append(f"        case let .{prop.case}(value): return value.rawValue")
        elif prop.type == "bucket":
            lines.append(
                f"        case let .{prop.case}(value): return AnalyticsValue.bucket(value, edges: {prop.edges}).description"
            )
        else:
            lines.append(f"        case let .{prop.case}(value): return String(describing: value)")
    lines += ["        }", "    }", "}"]
    return lines


def _property_payload(prop: UserProperty) -> str:
    return {
        "enum": prop.swift_type_name,
        "count": "Int",
        "number": "Double",
        "flag": "Bool",
        "bucket": "Int",
    }[prop.type]


def _render_typed_entry_points(schema: Schema) -> list[str]:
    """型付きの入口。**これが無いと呼び出し側で先頭ドットの省略が効かなくなる。**

    ポートは `any AnalyticsEvent` を受け取るので、`analytics.track(.tutorialBegin)` は
    そのままでは型を推論できない。生成した型を受ける薄い overload を足して、
    発火点の書き味を保つ（Ampli / Avo の codegen wrapper と同じ役割）。
    """
    lines = [
        "// MARK: - 型付きの入口",
        "//",
        "// ポートは `any AnalyticsEvent` を受け取るので、これが無いと発火点で先頭ドットが使えない。",
        "",
        "public extension AnalyticsClient {",
        "",
        f"    func track(_ event: {schema.event_type}) {{",
        "        track(event as any AnalyticsEvent)",
        "    }",
        "",
        f"    func setUserProperty(_ property: {schema.property_type}) {{",
        "        setUserProperty(property as any AnalyticsUserProperty)",
        "    }",
        "}",
    ]
    if not schema.swiftui:
        return lines
    lines += [
        "",
        "public extension View {",
        "",
        f"    func trackScreen(_ event: {schema.event_type}) -> some View {{",
        "        trackScreen(event as any AnalyticsEvent)",
        "    }",
        "",
        "    @available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)",
        f"    func trackImpression(_ event: {schema.event_type}) -> some View {{",
        "        trackImpression(event as any AnalyticsEvent)",
        "    }",
        "}",
    ]
    return lines


# ---------------------------------------------------------------- 配線の監査

ENTRY_POINTS = ("trackScreen", "trackImpression", "track", "setUserProperty")


def audit(schema: Schema, roots: list[Path]) -> list[str]:
    sites = _collect_sites(roots)
    corpus = "\n".join(expression for _, expression, _ in sites)
    problems: list[str] = []

    for event in schema.events:
        if not re.search(rf"\.{event.case}\b", corpus):
            problems.append(f"{event.name}（.{event.case}）を撃っている場所が無い")
            continue
        for parameter in (p for p in event.parameters if p.type == "enum"):
            literal = [v for v in parameter.values if re.search(rf"\.{lower_camel(v)}\b", corpus)]
            if not literal:
                # 値をすべて計算式で渡している。静的には確かめられないので落とさない。
                continue
            for value in parameter.values:
                if value not in [v for v in literal]:
                    problems.append(f"{event.name}.{parameter.key} = {value} を撃っている場所が無い")

    problems += _audit_firing_mechanism(schema, sites)

    for prop in schema.properties:
        if not re.search(rf"\.{prop.case}\b", corpus):
            problems.append(f"属性 {prop.name}（.{prop.case}）を置いている場所が無い")

    # 同じ発火（引数まで込みで同じもの）が 2 箇所以上に無いか
    appearances: dict[str, list[str]] = {}
    for kind, expression, location in sites:
        if kind in {"trackScreen", "trackImpression"}:
            appearances.setdefault(f"{kind}({expression})", []).append(location)
    for signature, locations in sorted(appearances.items()):
        if len(locations) > 1:
            problems.append(f"{signature} が {len(locations)} 箇所から出る: " + " / ".join(locations))

    return problems


# kind が撃ち方を決める。表示を 1 露出 1 回に留めているのは trackScreen / trackImpression
# だけなので、screen / impression を track() で撃つと、その規則がどこにも掛からないまま通る。
# **dedup にはもう表現できない規則**（DedupScope から episode を外した）ので、ここで落とす。
MECHANISM_FOR_KIND = {
    "screen": "trackScreen",
    "impression": "trackImpression",
    "interaction": "track",
    "outcome": "track",
}


def _audit_firing_mechanism(schema: Schema, sites: list[tuple[str, str, str]]) -> list[str]:
    problems: list[str] = []
    for event in schema.events:
        expected = MECHANISM_FOR_KIND[event.kind]
        for entry, expression, location in sites:
            if entry == "setUserProperty" or not re.search(rf"\.{event.case}\b", expression):
                continue
            if entry != expected:
                problems.append(
                    f"{event.name}: kind が {event.kind} なのに {entry}() で撃っている"
                    f"（{expected}() を使う）: {location}"
                )
    return problems


def _collect_sites(roots: list[Path]) -> list[tuple[str, str, str]]:
    sites: list[tuple[str, str, str]] = []
    for root in roots:
        for path in sorted(root.rglob("*.swift")):
            if ".build" in path.parts or path.name.endswith("+Generated.swift"):
                continue
            text = path.read_text(encoding="utf-8")
            for match in re.finditer(rf"\.({'|'.join(ENTRY_POINTS)})\(", text):
                body = _balanced(text, match.end() - 1)
                if body is None:
                    continue
                line = text.count("\n", 0, match.start()) + 1
                sites.append((match.group(1), re.sub(r"\s+", "", body), f"{path}:{line}"))
    return sites


def _balanced(text: str, open_index: int) -> str | None:
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[open_index + 1:i]
    return None


# ---------------------------------------------------------------- 入口

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    for name in ("generate", "check"):
        p = sub.add_parser(name)
        p.add_argument("--schema", type=Path, required=True)
        p.add_argument("--out", type=Path, required=True)

    p = sub.add_parser("audit")
    p.add_argument("--schema", type=Path, required=True)
    p.add_argument("--sources", type=Path, nargs="+", required=True)

    args = parser.parse_args()

    try:
        schema = load(args.schema)
    except SchemaError as error:
        print(str(error), file=sys.stderr)
        return 1

    if args.command == "generate":
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(render(schema), encoding="utf-8")
        print(f"生成: {args.out}（出来事 {len(schema.events)} / 属性 {len(schema.properties)}）")
        return 0

    if args.command == "check":
        expected = render(schema)
        actual = args.out.read_text(encoding="utf-8") if args.out.exists() else ""
        if expected != actual:
            print(
                f"生成物がスキーマとずれています: {args.out}\n"
                f"  analytics-gen.py generate --schema {args.schema} --out {args.out} を実行してコミットしてください",
                file=sys.stderr,
            )
            return 1
        print(f"生成物は最新です: {args.out}")
        return 0

    problems = audit(schema, args.sources)
    if problems:
        print("計測の配線がカタログと合っていません:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    print(f"配線 OK: 出来事 {len(schema.events)} / 属性 {len(schema.properties)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
