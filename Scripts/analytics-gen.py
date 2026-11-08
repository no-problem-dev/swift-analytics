#!/usr/bin/env python3
"""計測カタログ（analytics.yaml）から Swift を書き出し、実装とのズレを落とす。

スキーマの仕様は ``Schema/SCHEMA.md``。

    analytics-gen.py generate --schema analytics.yaml --out Generated/AppAnalytics.swift [--json catalog.json] [--ts catalog.ts]
    analytics-gen.py check    --schema analytics.yaml --out Generated/AppAnalytics.swift [--json catalog.json] [--ts catalog.ts]
    analytics-gen.py audit    --schema analytics.yaml --sources Sources/

`include: common` のカタログは、このパッケージの ``Schema/common/common.yaml`` を取り込む。
別の場所のものを使うときは ``--common <path>``。

**生成は人の手元で走らせ、生成物をコミットする。** ビルド時に生成しないのは、計測の変更が
「何を測ることにしたか」の変更であり、**差分が唯一のレビュー材料**だから。生成物が
リポジトリに現れない作りにすると、その差分を誰も見られなくなる。

`check` と `audit` を CI に置けば、生成し忘れも配線のズレも落ちる。
"""

from __future__ import annotations

import argparse
import json
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

# 自前の受け口（first_party）の制約。受け口の列の割り当てに収まる形にする。
#
# - 次元（enum・flag・bucket）は 4 つまで、数（count・number）は 1 つまで、token は 2 つまで。
#   受け口は 1 件を「名前・種別・次元 4 つ・token 2 つ・数 1 つ」の列に書く
# - 値（enum の値・token の長さ）は 64 字まで
FIRST_PARTY_NAME_LIMIT = 40
FIRST_PARTY_DIMENSION_LIMIT = 4
FIRST_PARTY_NUMBER_LIMIT = 1
FIRST_PARTY_TOKEN_LIMIT = 2
FIRST_PARTY_VALUE_LIMIT = 64

# 固定の封筒（Schema/common/ENVELOPE.md）で送る受け口。`props` は JSON の 1 段のマップなので、
# 列の割り当てから来る数の上限（first_party）は無い。名前と値の形は first_party と同じ。
ENVELOPE_VALUE_LIMIT = 64

DIALECTS = {"ga4", "first_party", "envelope"}
VALUE_LIMITS = {"ga4": GA4_VALUE_LIMIT, "first_party": FIRST_PARTY_VALUE_LIMIT, "envelope": ENVELOPE_VALUE_LIMIT}

# `include:` で取り込めるカタログ。名前からパッケージの中の場所を引く（`--common` で替えられる）。
PACKAGE_ROOT = Path(__file__).resolve().parent.parent
INCLUDABLE = {"common": PACKAGE_ROOT / "Schema" / "common" / "common.yaml"}

# 共通の出来事のうち、パッケージ（AnalyticsCore）が自分で送るもの。アプリの Swift には出さない。
SENT_BY = {"app", "package"}

KINDS = {"screen", "impression", "interaction", "outcome"}
SCOPES = {"session", "install", "always"}
PARAM_TYPES = {"enum", "count", "number", "flag", "bucket"}
# token はサーバーが作った不透明な値と、意味で決めたキーのためだけにある。属性には使えない。
EVENT_PARAM_TYPES = PARAM_TYPES | {"token"}
DIMENSION_TYPES = {"enum", "flag", "bucket"}
NUMBER_TYPES = {"count", "number"}

# 引数の名前に、人を指す値や人が書いた文を思わせる語を使わせない。`_` で区切った語ごとに見る
# （`placement` は通し、`place_name` は落とす）。
FORBIDDEN_PARAMETER_WORDS = {"name", "email", "place", "text", "title", "address"}

JSON_FORMAT = 1


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
    out, quote, escaped = [], None, False
    for char in raw:
        if quote:
            if escaped:
                escaped = False
            elif quote == '"' and char == "\\":
                escaped = True
            elif char == quote:
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


def _put(result: dict, key: str, value, number: int) -> None:
    if key in result:
        raise SchemaError(f"{number} 行目: 鍵 {key} が同じ場所に 2 回ある")
    result[key] = value


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
            _put(result, key, _scalar(rest, number), number)
        else:
            child, index = _parse_block(lines, index, indent + 2)
            _put(result, key, child if child is not None else {}, number)
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
        if ":" in item and not item.startswith(("\"", "'", "[", "{")):
            # `- key: value` から始まるマップ。続く行を同じ深さの続きとして読む
            key, _, rest = item.partition(":")
            entry: dict = {}
            if rest.strip():
                entry[key.strip()] = _scalar(rest.strip(), number)
            else:
                child, index = _parse_block(lines, index, indent + 4)
                entry[key.strip()] = child if child is not None else {}
            rest_map, index = _parse_map(lines, index, indent + 2)
            for rest_key, rest_value in rest_map.items():
                _put(entry, rest_key, rest_value, number)
            result.append(entry)
        else:
            result.append(_scalar(item, number))
    return result, index


def _scalar(text: str, number: int):
    """1 行に収まる値。流れ形式（`[a, b]`・`{ k: v }`）と引用符もここで読む。"""
    if text.startswith(("[", "{", "\"", "'")):
        value, end = _flow_value(text, 0, number, in_flow=False)
        if text[end:].strip():
            raise SchemaError(f"{number} 行目: 値の後ろに余りがある（{text[end:].strip()}）")
        return value
    return _plain(text, number)


def _plain(text: str, number: int):
    if text.startswith(("|", ">", "&", "*", "!", "%", "@", "`")):
        raise SchemaError(f"{number} 行目: この書き方は読みません（{text}）。SCHEMA.md の範囲で書いてください")
    if text in {"true", "false"}:
        return text == "true"
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    return text


# 二重引用符の中で読むエスケープ。ほかの `\x` は推測せず落とす。
_ESCAPES = {"\\": "\\", "\"": "\""}


def _quoted(text: str, index: int, number: int) -> tuple[str, int]:
    quote = text[index]
    out: list[str] = []
    index += 1
    while index < len(text):
        char = text[index]
        if quote == '"' and char == "\\":
            following = text[index + 1:index + 2]
            if following not in _ESCAPES:
                raise SchemaError(
                    f"{number} 行目: 二重引用符の中で読めるエスケープは \\\\ と \\\" だけ（\\{following}）"
                )
            out.append(_ESCAPES[following])
            index += 2
            continue
        if char == quote:
            if quote == "'" and text[index + 1:index + 2] == "'":
                out.append("'")
                index += 2
                continue
            return "".join(out), index + 1
        out.append(char)
        index += 1
    raise SchemaError(f"{number} 行目: 引用符が閉じていない（{text}）")


def _skip_spaces(text: str, index: int) -> int:
    while index < len(text) and text[index] == " ":
        index += 1
    return index


def _flow_value(text: str, index: int, number: int, *, in_flow: bool = True):
    """流れ形式の値を 1 つ読み、続きの位置を返す。`[...]` と `{...}` は入れ子にできる。"""
    index = _skip_spaces(text, index)
    if index >= len(text):
        raise SchemaError(f"{number} 行目: 値が途中で終わっている（{text}）")
    char = text[index]
    if char == "[":
        return _flow_sequence(text, index, number)
    if char == "{":
        return _flow_mapping(text, index, number)
    if char in "\"'":
        return _quoted(text, index, number)
    if not in_flow:
        return _plain(text[index:].strip(), number), len(text)
    end = index
    while end < len(text) and text[end] not in ",[]{}":
        end += 1
    plain = text[index:end].strip()
    if not plain:
        raise SchemaError(f"{number} 行目: 空の値がある（{text}）")
    if ": " in plain or plain.endswith(":"):
        raise SchemaError(f"{number} 行目: 流れ形式の値の中に `鍵: 値` がある（{plain}）")
    return _plain(plain, number), end


def _flow_sequence(text: str, index: int, number: int):
    items: list = []
    index = _skip_spaces(text, index + 1)
    if text[index:index + 1] == "]":
        return items, index + 1
    while True:
        value, index = _flow_value(text, index, number)
        items.append(value)
        index = _skip_spaces(text, index)
        separator = text[index:index + 1]
        if separator == ",":
            index += 1
            continue
        if separator == "]":
            return items, index + 1
        raise SchemaError(f"{number} 行目: `[` が閉じていない（{text}）")


def _flow_mapping(text: str, index: int, number: int):
    result: dict = {}
    index = _skip_spaces(text, index + 1)
    if text[index:index + 1] == "}":
        return result, index + 1
    while True:
        index = _skip_spaces(text, index)
        if text[index:index + 1] in ("\"", "'"):
            key, index = _quoted(text, index, number)
        else:
            end = index
            while end < len(text) and text[end] not in ":,[]{}":
                end += 1
            key = text[index:end].strip()
            index = end
        if not key or text[index:index + 1] != ":":
            raise SchemaError(f"{number} 行目: `{{ 鍵: 値 }}` の形にしてください（{text}）")
        value, index = _flow_value(text, index + 1, number)
        _put(result, key, value, number)
        index = _skip_spaces(text, index)
        separator = text[index:index + 1]
        if separator == ",":
            index += 1
            continue
        if separator == "}":
            return result, index + 1
        raise SchemaError(f"{number} 行目: `{{` が閉じていない（{text}）")


# ---------------------------------------------------------------- 名前の変換

def lower_camel(snake: str) -> str:
    head, *rest = snake.split("_")
    return head + "".join(part.capitalize() for part in rest)


# 値から作った case の名前が Swift の予約語になるときは `` で囲む（`import` など）。呼び出し側の `.import` は囲まなくてよい。
SWIFT_KEYWORDS = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout",
    "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public", "rethrows", "static",
    "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue", "default", "defer", "do", "else",
    "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw", "switch", "where", "while", "as", "false",
    "is", "nil", "self", "super", "throws", "true", "try", "await", "async", "any", "some", "consume", "copy",
}


def swift_case(value: str) -> str:
    """値集合の 1 つの値の `case` 宣言（名前と、名前と違うときの生の値）。"""
    name = lower_camel(value)
    declared = f"`{name}`" if name in SWIFT_KEYWORDS else name
    raw = f' = "{value}"' if name != value else ""
    return f"{declared}{raw}"


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
    pattern: str = ""
    max_length: int = 0
    extensible: bool = False
    origin: str = "app"
    # 共通の enum にアプリが足した値（`extend:`）。共通の値は `values` の頭に残る
    app_values: list[str] = field(default_factory=list)

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
    origin: str = "app"
    sent_by: str = "app"

    @property
    def fired_by_app(self) -> bool:
        return self.sent_by == "app"


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
class Fact:
    name: str
    source: str = ""
    query: str = ""
    description: str = ""


@dataclass
class Schema:
    event_type: str
    property_type: str
    module: str
    swiftui: bool
    dialect: str
    events: list[Event]
    properties: list[UserProperty]
    version: int = 1
    facts: list[Fact] = field(default_factory=list)
    # 取り込んだカタログ（名前と版）。今は common だけ
    includes: list[tuple[str, int]] = field(default_factory=list)

    @property
    def value_limit(self) -> int:
        return VALUE_LIMITS.get(self.dialect, GA4_VALUE_LIMIT)

    @property
    def app_fired_events(self) -> list[Event]:
        """アプリが撃つ出来事。Swift の生成と配線の監査はこれだけを見る。"""
        return [event for event in self.events if event.fired_by_app]


def load(path: Path, common: Path | None = None) -> Schema:
    """カタログを読み、`include:` と `extend:` を解いてから検査する。

    `common` は `include: common` で読むファイル。省くとこのパッケージの `Schema/common/common.yaml`。
    """
    raw = parse_yaml(path.read_text(encoding="utf-8"))
    _reject_unknown_keys(raw, {"version", "name", "dialect", "swift", "include", "extend", "events",
                               "user_properties", "facts"}, "カタログの頭")
    swift = raw.get("swift", {})
    dialect = raw.get("dialect", "ga4")

    included_events: list[Event] = []
    includes: list[tuple[str, int]] = []
    for name in _include_names(raw.get("include")):
        if dialect != "envelope":
            raise SchemaError(
                f"include: {name} は dialect: envelope のカタログでだけ使える（いまは {dialect}）。"
                "共通の出来事は固定の封筒で送る前提で、ga4 の予約名（first_open）や first_party の列の数に収まらない"
            )
        included_raw = parse_yaml(_include_path(name, common).read_text(encoding="utf-8"))
        if included_raw.get("include") or included_raw.get("extend"):
            raise SchemaError(f"{name}: 取り込まれるカタログは include / extend を持てない")
        if included_raw.get("dialect", "envelope") != "envelope":
            raise SchemaError(f"{name}: 取り込まれるカタログの dialect は envelope")
        included_events += [_event(item, origin=name) for item in included_raw.get("events") or []]
        includes.append((name, included_raw.get("version", 1)))

    # 取り込まれる側のカタログ（common.yaml）をそのまま読んだときは、出来事をその名前の物として扱う
    own_origin = raw["name"] if raw.get("name") in INCLUDABLE else "app"
    own_events = [_event(item, origin=own_origin) for item in raw.get("events") or []]
    included_names = {event.name for event in included_events}
    clashing = sorted(included_names.intersection(event.name for event in own_events))
    if clashing:
        raise SchemaError(
            f"{', '.join(clashing)}: 共通カタログにある出来事は events に書けない。値や引数を足すときは extend に書く"
        )
    if raw.get("extend") and not included_events:
        raise SchemaError("extend は include したカタログの出来事にだけ書ける")
    _apply_extend(raw.get("extend") or [], included_events)
    events = included_events + own_events
    _inherit_shared_enums(events)

    schema = Schema(
        event_type=swift.get("event_type", "AppEvent"),
        property_type=swift.get("property_type", "AppUserProperty"),
        module=swift.get("module", "App"),
        swiftui=bool(swift.get("swiftui", True)),
        dialect=dialect,
        events=events,
        properties=[_property(item) for item in raw.get("user_properties") or []],
        version=raw.get("version", 1),
        facts=[_fact(item) for item in raw.get("facts") or []],
        includes=includes,
    )
    for event in schema.events:
        for parameter in event.parameters:
            if parameter.type == "token" and not parameter.max_length:
                parameter.max_length = schema.value_limit
    validate(schema)
    return schema


def _include_names(value) -> list[str]:
    if value is None:
        return []
    names = [value] if isinstance(value, str) else value
    if not isinstance(names, list) or not all(isinstance(name, str) for name in names):
        raise SchemaError(f"include は名前か名前の並び（{value}）")
    unknown = sorted(set(names) - set(INCLUDABLE))
    if unknown:
        raise SchemaError(f"include できるのは {sorted(INCLUDABLE)} だけ（{', '.join(unknown)}）")
    if len(set(names)) != len(names):
        raise SchemaError(f"include に同じ名前が 2 回ある（{names}）")
    return names


def _include_path(name: str, common: Path | None) -> Path:
    path = common if (name == "common" and common) else INCLUDABLE[name]
    if not path.exists():
        raise SchemaError(f"include: {name} のファイルが無い（{path}）。--common で場所を渡せる")
    return path


def _reject_unknown_keys(item: dict, allowed: set[str], where: str) -> None:
    unknown = sorted(set(item) - allowed)
    if unknown:
        raise SchemaError(f"{where}: 知らない鍵 {', '.join(unknown)}（使える鍵は {', '.join(sorted(allowed))}）")


def _apply_extend(items, included: list[Event]) -> None:
    """共通の出来事に、enum の値と引数を足す。**共通の物は消せず、型も変えられない。**

    値は型（`type_name`）ごとに足す。`ScreenName` は `screen_viewed` と `tapped` の両方が使うので、
    片方に足した値はもう片方にも入る（同じ型名で値が違う状態を作らない）。
    """
    if not isinstance(items, list):
        raise SchemaError("extend は `- name: 出来事` の並び")
    by_name = {event.name: event for event in included}
    added: dict[str, list[str]] = {}
    seen: set[str] = set()
    for item in items:
        if not isinstance(item, dict):
            raise SchemaError(f"extend の 1 件は `name` と `parameters` のマップ（{item}）")
        name = _require(item, "name")
        _reject_unknown_keys(item, {"name", "parameters"}, f"extend の {name}")
        if name in seen:
            raise SchemaError(f"extend: {name} が 2 回ある。1 つにまとめてください")
        seen.add(name)
        event = by_name.get(name)
        if event is None:
            raise SchemaError(f"extend: {name} は共通カタログに無い。アプリの出来事なら events に書く")
        for key, spec in (item.get("parameters") or {}).items():
            existing = next((p for p in event.parameters if p.key == key), None)
            if existing is None:
                if not isinstance(spec, dict):
                    raise SchemaError(f"extend: {name}.{key} は引数の定義（type など）のマップ")
                parameter = _parameter(key, spec)
                parameter.origin = "app"
                event.parameters.append(parameter)
                continue
            where = f"extend: {name}.{key}"
            if not isinstance(spec, dict):
                raise SchemaError(f"{where} は `values: [...]` のマップ")
            changed = sorted(set(spec) - {"values"})
            if changed:
                raise SchemaError(
                    f"{where}: 共通の引数の {', '.join(changed)} は変えられない（足せるのは extensible な enum の values だけ）"
                )
            if existing.type != "enum" or not existing.extensible:
                raise SchemaError(f"{where}: extensible: true の enum でないので値を足せない")
            values = spec.get("values")
            if not isinstance(values, list) or not values:
                raise SchemaError(f"{where}: values に足す値を 1 つ以上書く")
            bucket = added.setdefault(existing.swift_type_name, [])
            for value in values:
                if value in existing.values:
                    raise SchemaError(f"{where}: {value} は共通の値として既にある")
                if value in bucket:
                    raise SchemaError(f"{where}: {value} を 2 回足している（{existing.swift_type_name} の値）")
                bucket.append(value)
    for event in included:
        for parameter in event.parameters:
            extra = added.get(parameter.swift_type_name, []) if parameter.type == "enum" else []
            if extra and parameter.origin != "app":
                parameter.values = parameter.values + extra
                parameter.app_values = list(extra)


def _inherit_shared_enums(events: list[Event]) -> None:
    """アプリの出来事が共通の enum の型名を `values` なしで書いたら、その値（足した値を含む）を使う。"""
    shared = {
        p.swift_type_name: p for e in events if e.origin != "app" for p in e.parameters
        if p.type == "enum" and p.origin != "app"
    }
    for event in events:
        if event.origin != "app":
            continue
        for parameter in event.parameters:
            source = shared.get(parameter.type_name)
            if parameter.type == "enum" and source and not parameter.values:
                parameter.values = list(source.values)
                parameter.extensible = source.extensible


def _fact(item: dict) -> Fact:
    return Fact(
        name=_require(item, "name"),
        source=str(item.get("source", "")),
        query=str(item.get("query", "")),
        description=str(item.get("description", "")),
    )


def _event(item: dict, origin: str = "app") -> Event:
    name = _require(item, "name")
    kind = _require(item, "kind")
    dedup = _require(item, "dedup")
    sent_by = str(item.get("sent_by", "app"))
    if sent_by not in SENT_BY:
        raise SchemaError(f"{name}: sent_by が {sorted(SENT_BY)} のどれでもない（{sent_by}）")
    if sent_by == "package" and origin == "app":
        raise SchemaError(f"{name}: sent_by: package は共通カタログの出来事にだけ書ける")
    parameters = [_parameter(key, value) for key, value in (item.get("parameters") or {}).items()]
    for parameter in parameters:
        parameter.origin = origin
    return Event(
        name=name,
        case=item.get("case") or lower_camel(name),
        kind=kind,
        dedup=dedup,
        description=item.get("description", ""),
        trigger=item.get("trigger", ""),
        parameters=parameters,
        origin=origin,
        sent_by=sent_by,
    )


def _parameter(key: str, value: dict) -> Parameter:
    if not isinstance(value, dict):
        raise SchemaError(f"{key}: 引数は `type` などのマップ（{value}）")
    extensible = value.get("extensible", False)
    if not isinstance(extensible, bool):
        raise SchemaError(f"{key}: extensible は true か false（{extensible}）")
    if extensible and value.get("type") != "enum":
        raise SchemaError(f"{key}: extensible は enum にだけ書ける")
    return Parameter(
        extensible=extensible,
        key=key,
        type=_require(value, "type", context=key),
        values=list(value.get("values") or []),
        edges=list(value.get("edges") or []),
        description=value.get("description", ""),
        type_name=str(value.get("type_name") or ""),
        pattern=str(value.get("pattern") or ""),
        max_length=int(value.get("max_length") or 0),
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
    token_shapes: dict[str, tuple[str, int]] = {}
    extensible_flags: dict[str, bool] = {}

    if schema.dialect not in DIALECTS:
        problems.append(f"dialect が {sorted(DIALECTS)} のどれでもない（{schema.dialect}）")
    if not isinstance(schema.version, int) or schema.version < 1:
        problems.append(f"version は 1 以上の整数（{schema.version}）")

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
            problems += _validate_parameter(event.name, parameter, value_limit=schema.value_limit)
            if parameter.type == "token":
                name = parameter.swift_type_name
                shape = (parameter.pattern, parameter.max_length)
                existing_shape = token_shapes.get(name)
                if existing_shape is not None and existing_shape != shape:
                    problems.append(
                        f"{event.name}.{parameter.key}: token の型 {name} の形が別の場所と食い違う"
                        f"（{existing_shape} と {shape}）。type_name で名前を分けてください"
                    )
                token_shapes[name] = shape
                if name in value_sets:
                    problems.append(f"{event.name}.{parameter.key}: 型名 {name} が enum と token の両方に使われている")
            if parameter.type == "enum":
                if parameter.swift_type_name in token_shapes:
                    problems.append(
                        f"{event.name}.{parameter.key}: 型名 {parameter.swift_type_name} が enum と token の両方に使われている"
                    )
                name = parameter.swift_type_name
                existing = value_sets.get(name)
                if existing is not None and existing != parameter.values:
                    problems.append(
                        f"{event.name}.{parameter.key}: 値集合 {name} が別の場所と食い違う"
                        f"（{existing} と {parameter.values}）。type_name で名前を分けてください"
                    )
                value_sets[name] = parameter.values
                flag = extensible_flags.setdefault(name, parameter.extensible)
                if flag != parameter.extensible:
                    problems.append(f"{event.name}.{parameter.key}: 値集合 {name} の extensible が別の場所と食い違う")

        if schema.dialect == "ga4":
            problems += _validate_ga4_name(event.name, reserved_names=True)
            if len(event.parameters) > GA4_PARAMETER_LIMIT:
                problems.append(f"{event.name}: パラメータが {len(event.parameters)} 個（GA4 の上限 {GA4_PARAMETER_LIMIT}）")
        if schema.dialect == "first_party":
            problems += _validate_first_party_event(event)
        if schema.dialect == "envelope":
            problems += _validate_envelope_event(event)

    for prop in schema.properties:
        if prop.type not in PARAM_TYPES:
            problems.append(f"{prop.name}: type が {sorted(PARAM_TYPES)} のどれでもない")
        if prop.type == "enum" and not prop.values:
            problems.append(f"{prop.name}: enum なのに values が無い")
        if prop.type == "bucket" and not prop.edges:
            problems.append(f"{prop.name}: bucket なのに edges が無い")
        if schema.dialect == "ga4":
            problems += _validate_ga4_name(prop.name, reserved_names=False)
        if schema.dialect in ("first_party", "envelope"):
            problems += _validate_first_party_name(prop.name, what="属性の名前")
        for value in prop.values:
            if len(value) > schema.value_limit:
                problems.append(f"{prop.name}: 値 {value} が {schema.value_limit} 字を超える")

    if problems:
        raise SchemaError("スキーマに問題があります:\n  - " + "\n  - ".join(problems))


def _validate_parameter(owner: str, parameter: Parameter, *, value_limit: int) -> list[str]:
    problems: list[str] = []
    if parameter.type not in EVENT_PARAM_TYPES:
        problems.append(f"{owner}.{parameter.key}: type が {sorted(EVENT_PARAM_TYPES)} のどれでもない")
        return problems
    forbidden = sorted(FORBIDDEN_PARAMETER_WORDS.intersection(parameter.key.split("_")))
    if forbidden:
        problems.append(
            f"{owner}.{parameter.key}: 引数の名前に {', '.join(forbidden)} は使えない"
            "（人を指す値・人が書いた文を送らない）"
        )
    if parameter.type == "enum":
        if not parameter.values:
            problems.append(f"{owner}.{parameter.key}: enum なのに values が無い")
        for value in parameter.values:
            if not re.fullmatch(r"[a-z][a-z0-9_]*", value):
                problems.append(f"{owner}.{parameter.key}: 値 {value} が snake_case でない")
            if len(value) > value_limit:
                problems.append(f"{owner}.{parameter.key}: 値 {value} が {value_limit} 字を超える")
    if parameter.type == "bucket" and not parameter.edges:
        problems.append(f"{owner}.{parameter.key}: bucket なのに edges が無い")
    if parameter.type == "token":
        problems += _validate_token(owner, parameter, value_limit=value_limit)
    elif parameter.pattern or parameter.max_length:
        problems.append(f"{owner}.{parameter.key}: pattern と max_length は token にだけ書ける")
    return problems


def _validate_token(owner: str, parameter: Parameter, *, value_limit: int) -> list[str]:
    """token は自由な文字列ではない。**形を正規表現で閉じたものだけ**を通す。"""
    problems: list[str] = []
    where = f"{owner}.{parameter.key}"
    if not parameter.pattern:
        problems.append(f"{where}: token には pattern（値の全体が合う正規表現）が要る")
        return problems
    if '"""' in parameter.pattern or "\n" in parameter.pattern:
        problems.append(f"{where}: pattern に改行や三重引用符は書けない")
    try:
        compiled = re.compile(parameter.pattern)
    except re.error as error:
        problems.append(f"{where}: pattern が正規表現として読めない（{error}）")
        return problems
    if compiled.fullmatch(""):
        problems.append(f"{where}: pattern が空の文字列に合う。1 字以上を要求してください")
    if parameter.max_length < 1 or parameter.max_length > value_limit:
        problems.append(f"{where}: max_length は 1〜{value_limit}（{parameter.max_length}）")
    return problems


def _validate_first_party_name(name: str, *, what: str) -> list[str]:
    problems: list[str] = []
    if len(name) > FIRST_PARTY_NAME_LIMIT:
        problems.append(f"{name}: {what}は {FIRST_PARTY_NAME_LIMIT} 字まで（first_party）")
    if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
        problems.append(f"{name}: {what}は snake_case（first_party）")
    return problems


def _validate_first_party_event(event: Event) -> list[str]:
    problems = _validate_first_party_name(event.name, what="出来事の名前")
    for parameter in event.parameters:
        problems += [
            f"{event.name}.{problem}"
            for problem in _validate_first_party_name(parameter.key, what="引数の名前")
        ]
    counts = {
        "次元（enum・flag・bucket）": (sum(p.type in DIMENSION_TYPES for p in event.parameters), FIRST_PARTY_DIMENSION_LIMIT),
        "数（count・number）": (sum(p.type in NUMBER_TYPES for p in event.parameters), FIRST_PARTY_NUMBER_LIMIT),
        "token": (sum(p.type == "token" for p in event.parameters), FIRST_PARTY_TOKEN_LIMIT),
    }
    for label, (count, limit) in counts.items():
        if count > limit:
            problems.append(f"{event.name}: {label}の引数が {count} 個（first_party の上限 {limit}）")
    return problems


def _validate_envelope_event(event: Event) -> list[str]:
    problems = [p.replace("first_party", "envelope") for p in _validate_first_party_name(event.name, what="出来事の名前")]
    for parameter in event.parameters:
        problems += [
            f"{event.name}.{problem.replace('first_party', 'envelope')}"
            for problem in _validate_first_party_name(parameter.key, what="引数の名前")
        ]
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
        "// 元は analytics.yaml。**先にそちらを直してから生成する。**",
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
    events = schema.app_fired_events
    for event in events:
        if event.description:
            lines.append(f"    /// {event.description}")
        if event.origin != "app":
            lines.append("    ///")
            lines.append(f"    /// 共通カタログ（{event.origin}）の出来事。名前と共通の引数はアプリで変えない。")
        if event.trigger:
            lines.append(f"    ///")
            lines.append(f"    /// 撃つ場所: {event.trigger}")
        lines.append(f"    case {event.case}{_case_payload(event)}")
        lines.append("")

    # 値集合。**共有されているものは 1 度だけ出す**（同名で中身が違うものは validate が落とす）。
    emitted: set[str] = set()
    for event in events:
        for parameter in (p for p in event.parameters if p.type == "enum"):
            if parameter.swift_type_name in emitted:
                continue
            emitted.add(parameter.swift_type_name)
            lines.append(f"    /// `{event.name}.{parameter.key}` の値。" + (parameter.description or ""))
            lines.append(f"    public enum {parameter.swift_type_name}: String, Sendable, CaseIterable {{")
            for value in parameter.values:
                lines.append(f"        case {swift_case(value)}")
            lines.append("    }")
            lines.append("")

    for event in events:
        for parameter in (p for p in event.parameters if p.type == "token"):
            if parameter.swift_type_name in emitted:
                continue
            emitted.add(parameter.swift_type_name)
            lines += _render_token(event, parameter)

    lines += _render_switch("name", events, lambda e: f'"{e.name}"')
    lines += _render_switch("kind", events, lambda e: f".{e.kind}", type_name="EventKind")
    lines += _render_switch("dedup", events, lambda e: f".{e.dedup}", type_name="DedupScope")
    lines += _render_parameters(events)
    lines.append("}")
    return lines


def _render_token(event: Event, parameter: Parameter) -> list[str]:
    """形の決まった文字列の型。**作れたものだけが送れる**ので、発火点に検査を書かせない。"""
    hashes = "#"
    while f'"{hashes}' in parameter.pattern:
        hashes += "#"
    literal = f'{hashes}"{parameter.pattern}"{hashes}'
    lines = [
        f"    /// `{event.name}.{parameter.key}` の値。" + (parameter.description or ""),
        "    ///",
        f"    /// 値の全体が `{parameter.pattern}` に合い、{parameter.max_length} 字までのものだけを作れる。",
        f"    public struct {parameter.swift_type_name}: Sendable, Hashable, CustomStringConvertible {{",
        "",
        "        public let rawValue: String",
        "",
        "        /// 形に合わなければ nil。**送らずに済ませる**（形の違う値を送るより、送らない方が数を壊さない）。",
        "        public init?(_ rawValue: String) {",
        f"            guard rawValue.count <= {parameter.max_length},",
        f"                  let pattern = try? Regex({literal}),",
        "                  (try? pattern.wholeMatch(in: rawValue)) != nil",
        "            else { return nil }",
        "            self.rawValue = rawValue",
        "        }",
        "",
        "        public var description: String { rawValue }",
        "    }",
        "",
    ]
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
        "token": parameter.swift_type_name,
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
        "token": f".text({key}.rawValue)",
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
            lines.append(f"        case {swift_case(value)}")
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
        "// MARK: - 型付きの track と setUserProperty",
        "//",
        "// ポートは `any AnalyticsEvent` を受け取るので、これが無いと発火点で先頭ドットが使えない。",
        "",
        "public extension AnalyticsClient {",
        "",
        f"    func track(_ event: {schema.event_type}) {{",
        "        track(event as any AnalyticsEvent)",
        "    }",
    ]
    if schema.properties:
        # 属性が無いと型に値が無く、本文が「実行されない」と警告になる
        lines += [
            "",
            f"    func setUserProperty(_ property: {schema.property_type}) {{",
            "        setUserProperty(property as any AnalyticsUserProperty)",
            "    }",
        ]
    lines += ["}"]
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


# ---------------------------------------------------------------- 受け口のための JSON

def bucket_labels(edges: list[int]) -> list[str]:
    """`AnalyticsValue.bucket(_:edges:)` が返しうる帯の名前の全部（同じ規則で作る）。"""
    ordered = sorted(edges)
    if not ordered:
        return ["0"]
    labels = [str(ordered[0] - 1)]
    for index, lower in enumerate(ordered):
        upper = ordered[index + 1] if index + 1 < len(ordered) else None
        labels.append(f"{lower}_plus" if upper is None else f"{lower}_{upper - 1}")
    return labels


def _json_value_shape(type_: str, values: list[str], edges: list[int], parameter: Parameter | None = None) -> dict:
    shape: dict = {"type": type_}
    if type_ == "enum":
        shape["values"] = list(values)
        if parameter is not None:
            shape["extensible"] = parameter.extensible
            if parameter.origin != "app":
                shape["appValues"] = list(parameter.app_values)
    elif type_ == "bucket":
        shape["edges"] = sorted(edges)
        shape["values"] = bucket_labels(edges)
    elif type_ == "token" and parameter is not None:
        shape["pattern"] = parameter.pattern
        shape["maxLength"] = parameter.max_length
    return shape


def render_json(schema: Schema) -> str:
    """受け口（サーバー）が照らし合わせに使うカタログ。形は SCHEMA.md の「--json の形」。"""
    limits: dict = {"value": schema.value_limit}
    if schema.dialect == "first_party":
        limits.update({
            "name": FIRST_PARTY_NAME_LIMIT,
            "dimensions": FIRST_PARTY_DIMENSION_LIMIT,
            "numbers": FIRST_PARTY_NUMBER_LIMIT,
            "tokens": FIRST_PARTY_TOKEN_LIMIT,
        })
    elif schema.dialect == "envelope":
        limits.update({"name": FIRST_PARTY_NAME_LIMIT})
    else:
        limits.update({"name": GA4_NAME_LIMIT, "parameters": GA4_PARAMETER_LIMIT})
    document = {
        "format": JSON_FORMAT,
        "generator": "swift-analytics/Scripts/analytics-gen.py",
        "catalogVersion": schema.version,
        "dialect": schema.dialect,
        "limits": limits,
        "includes": [{"name": name, "version": version} for name, version in schema.includes],
        "events": [
            {
                "name": event.name,
                "kind": event.kind,
                "dedup": event.dedup,
                "origin": event.origin,
                "sentBy": event.sent_by,
                "parameters": [
                    {"key": p.key, "origin": p.origin, **_json_value_shape(p.type, p.values, p.edges, p)}
                    for p in event.parameters
                ],
            }
            for event in schema.events
        ],
        "userProperties": [
            {"name": prop.name, **_json_value_shape(prop.type, prop.values, prop.edges)}
            for prop in schema.properties
        ],
        "facts": [
            {"name": fact.name, "source": fact.source, "query": fact.query}
            for fact in schema.facts
        ],
    }
    return json.dumps(document, ensure_ascii=False, indent=2) + "\n"


# ---------------------------------------------------------------- 受け口のための TypeScript

# 生成する TypeScript の頭の名前。enum の型名と重なると書き出せない。
TS_RESERVED_NAMES = {"CATALOG_VERSION", "INCLUDES", "EVENTS", "EVENT_NAMES", "COMMON_EVENT_NAMES",
                     "EventName", "CommonEventName", "EventProps"}


def _ts_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _ts_type(parameter: Parameter) -> str:
    if parameter.type == "enum":
        return parameter.swift_type_name
    if parameter.type == "bucket":
        return " | ".join(_ts_string(label) for label in bucket_labels(parameter.edges))
    return {"count": "number", "number": "number", "flag": "boolean", "token": "string"}[parameter.type]


def _ts_shape(parameter: Parameter) -> str:
    fields = [f"type: {_ts_string(parameter.type)}", f"origin: {_ts_string(parameter.origin)}"]
    if parameter.type == "enum":
        fields.append(f"values: {parameter.swift_type_name}")
        fields.append(f"extensible: {'true' if parameter.extensible else 'false'}")
    elif parameter.type == "bucket":
        fields.append(f"edges: {json.dumps(sorted(parameter.edges))}")
        fields.append(f"values: {json.dumps(bucket_labels(parameter.edges))}")
    elif parameter.type == "token":
        fields.append(f"pattern: {_ts_string(parameter.pattern)}")
        fields.append(f"maxLength: {parameter.max_length}")
    return "{ " + ", ".join(fields) + " }"


def render_ts(schema: Schema) -> str:
    """受け口（Worker・studio）が import する名前・引数・enum の値。照らし合わせは --json と同じ中身。"""
    enums: dict[str, Parameter] = {}
    for event in schema.events:
        for parameter in event.parameters:
            if parameter.type == "enum":
                enums.setdefault(parameter.swift_type_name, parameter)
    clashing = sorted(TS_RESERVED_NAMES.intersection(enums))
    if clashing:
        raise SchemaError(f"enum の型名 {', '.join(clashing)} は TypeScript の出力の名前と重なる。type_name を替えてください")

    out = [
        HEADER,
        "// 元は analytics.yaml。**先にそちらを直してから生成する。**",
        "",
        f"export const CATALOG_VERSION = {schema.version} as const;",
        "export const INCLUDES = ["
        + ", ".join(f"{{ name: {_ts_string(n)}, version: {v} }}" for n, v in schema.includes)
        + "] as const;",
        "",
    ]
    for name, parameter in enums.items():
        out.append(f"export const {name} = [{', '.join(_ts_string(v) for v in parameter.values)}] as const;")
        out.append(f"export type {name} = (typeof {name})[number];")
    out += ["", "export const EVENTS = {"]
    for event in schema.events:
        out.append(f"  {event.name}: {{")
        out.append(
            f"    kind: {_ts_string(event.kind)}, dedup: {_ts_string(event.dedup)}, "
            f"origin: {_ts_string(event.origin)}, sentBy: {_ts_string(event.sent_by)},"
        )
        if event.parameters:
            out.append("    parameters: {")
            for parameter in event.parameters:
                out.append(f"      {parameter.key}: {_ts_shape(parameter)},")
            out.append("    },")
        else:
            out.append("    parameters: {},")
        out.append("  },")
    out += [
        "} as const;",
        "",
        "export type EventName = keyof typeof EVENTS;",
        "export const EVENT_NAMES = Object.keys(EVENTS) as EventName[];",
        "export const COMMON_EVENT_NAMES = ["
        + ", ".join(_ts_string(e.name) for e in schema.events if e.origin != "app")
        + "] as const satisfies readonly EventName[];",
        "export type CommonEventName = (typeof COMMON_EVENT_NAMES)[number];",
        "",
        "/** 出来事ごとの `props` の型。生成した Swift は引数を全部埋めて送る。 */",
        "export interface EventProps {",
    ]
    for event in schema.events:
        if not event.parameters:
            out.append(f"  {event.name}: Record<string, never>;")
            continue
        fields = "; ".join(f"{p.key}: {_ts_type(p)}" for p in event.parameters)
        out.append(f"  {event.name}: {{ {fields} }};")
    out.append("}")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- 配線の監査

ENTRY_POINTS = ("trackScreen", "trackImpression", "track", "setUserProperty")


def audit(schema: Schema, roots: list[Path]) -> list[str]:
    sites = _collect_sites(roots)
    corpus = "\n".join(expression for _, expression, _ in sites)
    problems: list[str] = []

    for event in schema.app_fired_events:
        fired = re.search(rf"\.{event.case}\b", corpus)
        if not fired:
            # 共通の出来事は、アプリにその場面が無ければ撃たなくてよい（unfired_common が知らせるだけ）
            if event.origin == "app":
                problems.append(f"{event.name}（.{event.case}）を撃っている場所が無い")
            continue
        # 値はその出来事を撃っている式の中だけで探す。ほかの出来事や属性に同じ名前の値があっても数えない。
        own = "\n".join(expression for _, expression, _ in sites if re.search(rf"\.{event.case}\b", expression))
        for parameter in (p for p in event.parameters if p.type == "enum"):
            literal = [v for v in parameter.values if re.search(rf"\.{lower_camel(v)}\b", own)]
            if not literal:
                # 値をすべて計算式で渡している。静的には確かめられないので落とさない。
                continue
            # 共通の値は、アプリにその入口が無いことがある。確かめるのはアプリが足した値とアプリの引数だけ
            expected = parameter.values if parameter.origin == "app" else parameter.app_values
            for value in expected:
                if value not in literal:
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


def unfired_common(schema: Schema, roots: list[Path]) -> list[str]:
    """共通カタログの出来事のうち、アプリがどこからも撃っていないもの。落とさず知らせるだけ。"""
    corpus = "\n".join(expression for _, expression, _ in _collect_sites(roots))
    return [
        event.name for event in schema.app_fired_events
        if event.origin != "app" and not re.search(rf"\.{event.case}\b", corpus)
    ]


def _audit_firing_mechanism(schema: Schema, sites: list[tuple[str, str, str]]) -> list[str]:
    problems: list[str] = []
    for event in schema.app_fired_events:
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

    common_help = "include: common で読むファイル（省くとパッケージの Schema/common/common.yaml）"
    for name in ("generate", "check"):
        p = sub.add_parser(name)
        p.add_argument("--schema", type=Path, required=True)
        p.add_argument("--common", type=Path, help=common_help)
        p.add_argument("--out", type=Path, help="書き出す Swift のファイル")
        p.add_argument("--json", type=Path, help="受け口のための JSON のカタログ")
        p.add_argument("--ts", type=Path, help="受け口のための TypeScript（名前・引数・enum の値）")

    p = sub.add_parser("audit")
    p.add_argument("--schema", type=Path, required=True)
    p.add_argument("--common", type=Path, help=common_help)
    p.add_argument("--sources", type=Path, nargs="+", required=True)

    args = parser.parse_args()

    try:
        schema = load(args.schema, common=args.common)
    except SchemaError as error:
        print(str(error), file=sys.stderr)
        return 1

    if args.command in ("generate", "check"):
        renderers = ((args.out, render), (args.json, render_json), (args.ts, render_ts))
        outputs = [(path, renderer) for path, renderer in renderers if path]
        if not outputs:
            print("--out・--json・--ts の少なくとも 1 つが要ります", file=sys.stderr)
            return 2
        try:
            rendered = {path: renderer(schema) for path, renderer in outputs}
        except SchemaError as error:
            print(str(error), file=sys.stderr)
            return 1
        if args.command == "generate":
            for path, text in rendered.items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
                print(f"生成: {path}（出来事 {len(schema.events)} / 属性 {len(schema.properties)}）")
            return 0
        stale = [
            path for path, text in rendered.items()
            if text != (path.read_text(encoding="utf-8") if path.exists() else "")
        ]
        if stale:
            pairs = (("--common", args.common), ("--out", args.out), ("--json", args.json), ("--ts", args.ts))
            flags = " ".join(f"{flag} {path}" for flag, path in pairs if path)
            for path in stale:
                print(f"生成物がスキーマとずれています: {path}", file=sys.stderr)
            print(
                f"  analytics-gen.py generate --schema {args.schema} {flags} を実行してコミットしてください",
                file=sys.stderr,
            )
            return 1
        for path, _ in outputs:
            print(f"生成物は最新です: {path}")
        return 0

    problems = audit(schema, args.sources)
    for name in unfired_common(schema, args.sources):
        print(f"（知らせ）共通の出来事 {name} を撃っている場所が無い。その場面がアプリに無いなら、そのままでよい")
    if problems:
        print("計測の配線がカタログと合っていません:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    print(f"配線 OK: 出来事 {len(schema.events)} / 属性 {len(schema.properties)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
