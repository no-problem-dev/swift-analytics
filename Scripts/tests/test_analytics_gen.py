"""analytics-gen.py の検査と JSON の出力。

    python3 -m unittest discover -s Scripts/tests

`swift test` からも回る（Tests/AnalyticsBatchSinkTests/GeneratorTests.swift）。
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("analytics_gen", ROOT / "Scripts" / "analytics-gen.py")
gen = importlib.util.module_from_spec(_spec)
sys.modules["analytics_gen"] = gen
_spec.loader.exec_module(gen)


def load(yaml: str):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "analytics.yaml"
        path.write_text(textwrap.dedent(yaml), encoding="utf-8")
        return gen.load(path)


def first_party(parameters: str = "", name: str = "trip_created") -> str:
    block = textwrap.indent(textwrap.dedent(parameters), "      ") if parameters else ""
    return (
        "version: 3\n"
        "dialect: first_party\n"
        "events:\n"
        f"  - name: {name}\n"
        "    kind: outcome\n"
        "    dedup: always\n"
        + ("    parameters:\n" + block if block else "")
    )


class FirstPartyDialect(unittest.TestCase):

    def assertRejected(self, yaml: str, fragment: str):
        with self.assertRaises(gen.SchemaError) as caught:
            load(yaml)
        self.assertIn(fragment, str(caught.exception))

    def test_accepts_four_dimensions_one_number_two_tokens(self):
        schema = load(first_party("""\
            a:
              type: flag
            b:
              type: enum
              values: [x, y]
            c:
              type: bucket
              edges: [1, 5]
            d:
              type: flag
            n:
              type: count
            r:
              type: token
              pattern: "[a-z0-9]{4,20}"
            k:
              type: token
              pattern: "[a-z]+:[0-9]+"
        """))
        self.assertEqual(len(schema.events[0].parameters), 7)

    def test_rejects_fifth_dimension(self):
        self.assertRejected(first_party("""\
            a:
              type: flag
            b:
              type: flag
            c:
              type: flag
            d:
              type: flag
            e:
              type: flag
        """), "次元")

    def test_rejects_second_number(self):
        self.assertRejected(first_party("""\
            a:
              type: count
            b:
              type: number
        """), "数（count・number）")

    def test_rejects_third_token(self):
        self.assertRejected(first_party("""\
            a:
              type: token
              pattern: "[a-z]+"
            b:
              type: token
              pattern: "[a-z]+"
            c:
              type: token
              pattern: "[a-z]+"
        """), "token")

    def test_rejects_long_name(self):
        self.assertRejected(first_party(name="a" * 41), "40 字まで")

    def test_rejects_value_over_64(self):
        self.assertRejected(first_party(f"""\
            a:
              type: enum
              values: [{"v" * 65}]
        """), "64 字を超える")

    def test_ga4_keeps_its_100_character_values(self):
        load(f"""\
            version: 1
            dialect: ga4
            events:
              - name: shown
                kind: screen
                dedup: always
                parameters:
                  a:
                    type: enum
                    values: [{"v" * 80}]
        """)

    def test_rejects_unknown_dialect(self):
        self.assertRejected("version: 1\ndialect: amplitude\n", "dialect")


class ForbiddenParameterNames(unittest.TestCase):

    def test_rejects_words_that_point_at_people_or_text(self):
        for key in ("place_name", "email", "title", "home_address", "first_text"):
            with self.subTest(key=key), self.assertRaises(gen.SchemaError):
                load(first_party(f"""\
                    {key}:
                      type: flag
                """))

    def test_allows_words_that_only_contain_them(self):
        load(first_party("""\
            placement:
              type: flag
            renamed:
              type: flag
        """))


class Tokens(unittest.TestCase):

    def test_requires_pattern(self):
        with self.assertRaises(gen.SchemaError) as caught:
            load(first_party("""\
                r:
                  type: token
            """))
        self.assertIn("pattern", str(caught.exception))

    def test_rejects_pattern_matching_empty(self):
        with self.assertRaises(gen.SchemaError) as caught:
            load(first_party("""\
                r:
                  type: token
                  pattern: "[a-z]*"
            """))
        self.assertIn("空の文字列", str(caught.exception))

    def test_rejects_max_length_over_value_limit(self):
        with self.assertRaises(gen.SchemaError):
            load(first_party("""\
                r:
                  type: token
                  pattern: "[a-z]+"
                  max_length: 65
            """))

    def test_defaults_max_length_to_value_limit(self):
        schema = load(first_party("""\
            r:
              type: token
              pattern: "[a-z]+"
        """))
        self.assertEqual(schema.events[0].parameters[0].max_length, 64)

    def test_pattern_only_on_tokens(self):
        with self.assertRaises(gen.SchemaError):
            load(first_party("""\
                r:
                  type: enum
                  values: [a]
                  pattern: "[a-z]+"
            """))

    def test_not_allowed_on_user_properties(self):
        with self.assertRaises(gen.SchemaError):
            load("""\
                version: 1
                dialect: first_party
                user_properties:
                  - name: device
                    type: token
            """)

    def test_shared_type_name_must_share_shape(self):
        with self.assertRaises(gen.SchemaError) as caught:
            load("""\
                version: 1
                dialect: first_party
                events:
                  - name: a_seen
                    kind: screen
                    dedup: always
                    parameters:
                      render_id:
                        type: token
                        pattern: "[a-z]+"
                  - name: b_seen
                    kind: screen
                    dedup: always
                    parameters:
                      render_id:
                        type: token
                        pattern: "[0-9]+"
            """)
        self.assertIn("形が別の場所と食い違う", str(caught.exception))


class JsonCatalog(unittest.TestCase):

    def test_shape(self):
        schema = load(first_party("""\
            source:
              type: enum
              values: [paste, sample_copy]
            nth:
              type: bucket
              edges: [3, 1, 2]
            render_id:
              type: token
              pattern: "[a-z]+"
              max_length: 20
            items:
              type: count
        """))
        document = json.loads(gen.render_json(schema))
        self.assertEqual(document["format"], 1)
        self.assertEqual(document["catalogVersion"], 3)
        self.assertEqual(document["dialect"], "first_party")
        self.assertEqual(document["limits"], {"value": 64, "name": 40, "dimensions": 4, "numbers": 1, "tokens": 2})
        event = document["events"][0]
        self.assertEqual((event["name"], event["kind"], event["dedup"]), ("trip_created", "outcome", "always"))
        self.assertEqual([p["key"] for p in event["parameters"]], ["source", "nth", "render_id", "items"])
        self.assertEqual((event["origin"], event["sentBy"]), ("app", "app"))
        self.assertEqual(document["includes"], [])
        self.assertEqual(
            event["parameters"][0],
            {"key": "source", "origin": "app", "type": "enum", "values": ["paste", "sample_copy"], "extensible": False},
        )
        self.assertEqual(
            event["parameters"][1],
            {"key": "nth", "origin": "app", "type": "bucket", "edges": [1, 2, 3], "values": ["0", "1_1", "2_2", "3_plus"]},
        )
        self.assertEqual(
            event["parameters"][2],
            {"key": "render_id", "origin": "app", "type": "token", "pattern": "[a-z]+", "maxLength": 20},
        )
        self.assertEqual(event["parameters"][3], {"key": "items", "origin": "app", "type": "count"})

    def test_bucket_labels_follow_swift(self):
        # AnalyticsValue.bucket(_:edges:) の例と同じ: 0 → "0", 3 → "1_5", 99 → "16_plus"
        self.assertEqual(gen.bucket_labels([1, 6, 16]), ["0", "1_5", "6_15", "16_plus"])
        self.assertEqual(gen.bucket_labels([]), ["0"])

    def test_checked_in_example_is_current(self):
        schema = gen.load(ROOT / "Schema" / "example-first-party.yaml")
        expected = (ROOT / "Schema" / "example-first-party.catalog.json").read_text(encoding="utf-8")
        self.assertEqual(gen.render_json(schema), expected)
        swift = (ROOT / "Tests" / "AnalyticsBatchSinkTests" / "Generated" / "TripAnalytics.swift").read_text(encoding="utf-8")
        self.assertEqual(gen.render(schema), swift)


class SwiftKeywordCaseTests(unittest.TestCase):
    def test_keyword_values_are_escaped(self):
        schema = load("""
            dialect: first_party
            events:
              - name: address_copied
                kind: interaction
                dedup: always
                parameters:
                  from:
                    type: enum
                    values: [import, settings, live_activity]
        """)
        swift = gen.render(schema)
        self.assertIn("case `import`", swift)
        self.assertIn("case settings", swift)
        self.assertIn('case liveActivity = "live_activity"', swift)


class AuditScopeTests(unittest.TestCase):
    def test_values_are_matched_within_the_event_sites(self):
        schema = load("""
            dialect: first_party
            events:
              - name: sign_in_finished
                kind: outcome
                dedup: always
                parameters:
                  result:
                    type: enum
                    type_name: SignInResult
                    values: [signed_in, failed]
              - name: paste_finished
                kind: outcome
                dedup: always
                parameters:
                  result:
                    type: enum
                    type_name: PasteResult
                    values: [imported, failed]
        """)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Sites.swift"
            source.write_text(textwrap.dedent("""
                analytics.track(.signInFinished(result: .signedIn))
                analytics.track(.signInFinished(result: .failed))
                analytics.track(.pasteFinished(result: computed))
            """), encoding="utf-8")
            self.assertEqual(gen.audit(schema, [Path(directory)]), [])



# ---------------------------------------------------------------- YAML の読み方

class YamlFlowStyle(unittest.TestCase):

    def test_reads_flow_mapping_with_nested_sequence(self):
        document = gen.parse_yaml(
            'a: { type: enum, type_name: X, extensible: true, values: [p, q] }\n'
            'b: { type: count, description: 開いてから押すまでの秒（1から） }\n'
        )
        self.assertEqual(document["a"], {"type": "enum", "type_name": "X", "extensible": True, "values": ["p", "q"]})
        self.assertEqual(document["b"], {"type": "count", "description": "開いてから押すまでの秒（1から）"})

    def test_reads_quoted_strings_with_commas_and_escapes(self):
        document = gen.parse_yaml(
            'p: { type: token, pattern: "[0-9]{1,3}(\\\\.[0-9]{1,3}){1,2}" }\n'
            "q: 'it''s'\n"
            'r: "say \\"hi\\""\n'
        )
        self.assertEqual(document["p"]["pattern"], r"[0-9]{1,3}(\.[0-9]{1,3}){1,2}")
        self.assertEqual(document["q"], "it's")
        self.assertEqual(document["r"], 'say "hi"')

    def test_rejects_unknown_escape(self):
        with self.assertRaises(gen.SchemaError):
            gen.parse_yaml('p: "\\d+"\n')

    def test_rejects_unclosed_flow(self):
        for text in ("a: { type: enum\n", "a: [x, y\n", 'a: "open\n', "a: { type }\n"):
            with self.subTest(text=text), self.assertRaises(gen.SchemaError):
                gen.parse_yaml(text)

    def test_rejects_trailing_text_and_duplicate_keys(self):
        with self.assertRaises(gen.SchemaError):
            gen.parse_yaml("a: [x] y\n")
        with self.assertRaises(gen.SchemaError):
            gen.parse_yaml("a: 1\na: 2\n")
        with self.assertRaises(gen.SchemaError):
            gen.parse_yaml("a: { k: 1, k: 2 }\n")

    def test_still_rejects_anchors_and_block_strings(self):
        for text in ("a: &x 1\n", "a: |\n  text\n", "a: *x\n"):
            with self.subTest(text=text), self.assertRaises(gen.SchemaError):
                gen.parse_yaml(text)


# ---------------------------------------------------------------- include と extend

COMMON = ROOT / "Schema" / "common" / "common.yaml"


def app(body: str = "", head: str = "version: 2\ndialect: envelope\ninclude: common\n"):
    return load(head + textwrap.dedent(body))


class IncludeCommon(unittest.TestCase):

    def assertRejected(self, body: str, fragment: str, head: str | None = None):
        with self.assertRaises(gen.SchemaError) as caught:
            app(body) if head is None else app(body, head=head)
        self.assertIn(fragment, str(caught.exception))

    def test_common_catalog_loads_on_its_own(self):
        schema = gen.load(COMMON)
        self.assertEqual(schema.dialect, "envelope")
        self.assertTrue(all(event.origin == "common" for event in schema.events))
        names = {event.name for event in schema.events}
        for name in ("first_open", "internal_device", "screen_viewed", "paywall_shown", "purchase_completed",
                     "review_requested", "whats_new_shown", "whats_new_closed"):
            self.assertIn(name, names)

    def test_include_brings_common_events_first(self):
        schema = app("""\
            events:
              - name: entry_saved
                kind: outcome
                dedup: always
        """)
        self.assertEqual(schema.includes, [("common", 2)])
        self.assertEqual(schema.events[0].name, "first_open")
        self.assertEqual(schema.events[-1].name, "entry_saved")
        self.assertEqual(schema.events[-1].origin, "app")

    def test_common_path_can_be_overridden(self):
        with tempfile.TemporaryDirectory() as directory:
            custom = Path(directory) / "mine.yaml"
            custom.write_text(
                "version: 7\nname: common\nevents:\n  - name: only_one\n    kind: outcome\n    dedup: always\n",
                encoding="utf-8",
            )
            path = Path(directory) / "analytics.yaml"
            path.write_text("dialect: envelope\ninclude: common\n", encoding="utf-8")
            schema = gen.load(path, common=custom)
        self.assertEqual([event.name for event in schema.events], ["only_one"])
        self.assertEqual(schema.includes, [("common", 7)])

    def test_include_needs_envelope_dialect(self):
        self.assertRejected("", "dialect: envelope", head="dialect: first_party\ninclude: common\n")
        self.assertRejected("", "dialect: envelope", head="include: common\n")

    def test_unknown_include_is_rejected(self):
        self.assertRejected("", "include できるのは", head="dialect: envelope\ninclude: shared\n")

    def test_common_event_cannot_be_redefined(self):
        self.assertRejected("""\
            events:
              - name: paywall_shown
                kind: impression
                dedup: always
        """, "extend に書く")

    def test_extend_adds_values_to_the_type_everywhere(self):
        schema = app("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    values: [home]
        """)
        tapped = next(e for e in schema.events if e.name == "tapped")
        screen = next(p for p in tapped.parameters if p.key == "screen")
        self.assertEqual(screen.values[-1], "home")
        self.assertEqual(screen.app_values, ["home"])
        self.assertIn("case home", gen.render(schema))

    def test_extend_adds_parameter_at_the_end(self):
        schema = app("""\
            extend:
              - name: paywall_shown
                parameters:
                  variant: { type: enum, values: [a, b] }
        """)
        shown = next(e for e in schema.events if e.name == "paywall_shown")
        self.assertEqual([p.key for p in shown.parameters][-1], "variant")
        self.assertEqual(shown.parameters[-1].origin, "app")

    def test_cannot_add_values_to_closed_enum(self):
        self.assertRejected("""\
            extend:
              - name: paywall_plan_selected
                parameters:
                  to:
                    values: [daily]
        """, "extensible: true の enum でない")

    def test_cannot_change_type_of_common_parameter(self):
        self.assertRejected("""\
            extend:
              - name: paywall_shown
                parameters:
                  nth: { type: count }
        """, "変えられない")

    def test_cannot_readd_existing_value(self):
        self.assertRejected("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    values: [paywall]
        """, "既にある")

    def test_cannot_add_the_same_value_twice_through_two_events(self):
        self.assertRejected("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    values: [home]
              - name: tapped
                parameters:
                  screen:
                    values: [home]
        """, "2 回足している")

    def test_cannot_extend_unknown_event(self):
        self.assertRejected("""\
            extend:
              - name: entry_saved
                parameters:
                  words: { type: count }
        """, "共通カタログに無い")

    def test_app_event_can_reuse_common_enum_by_type_name(self):
        schema = app("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    values: [home]
            events:
              - name: entry_saved
                kind: outcome
                dedup: always
                parameters:
                  screen: { type: enum, type_name: ScreenName }
        """)
        saved = schema.events[-1]
        self.assertEqual(saved.parameters[0].values[-1], "home")

    def test_package_sent_events_stay_out_of_swift(self):
        schema = app()
        swift = gen.render(schema)
        self.assertNotIn("case firstOpen", swift)
        self.assertNotIn("case internalDevice", swift)
        self.assertNotIn("FirstOpenKind", swift)
        self.assertIn("case paywallShown(", swift)
        self.assertIn('"first_open"', gen.render_ts(schema))
        names = [e["name"] for e in json.loads(gen.render_json(schema))["events"]]
        self.assertIn("first_open", names)

    def test_sent_by_package_only_in_common(self):
        with self.assertRaises(gen.SchemaError):
            load("""\
                dialect: envelope
                events:
                  - name: mine
                    kind: outcome
                    dedup: always
                    sent_by: package
            """)

    def test_json_marks_origin_and_app_values(self):
        schema = app("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    values: [home]
        """)
        document = json.loads(gen.render_json(schema))
        self.assertEqual(document["includes"], [{"name": "common", "version": 2}])
        viewed = next(e for e in document["events"] if e["name"] == "screen_viewed")
        self.assertEqual((viewed["origin"], viewed["sentBy"]), ("common", "app"))
        screen = viewed["parameters"][0]
        self.assertTrue(screen["extensible"])
        self.assertEqual(screen["appValues"], ["home"])
        first_open = next(e for e in document["events"] if e["name"] == "first_open")
        self.assertEqual(first_open["sentBy"], "package")


class TypeScriptOutput(unittest.TestCase):

    def test_shape(self):
        schema = app("""\
            events:
              - name: entry_saved
                kind: outcome
                dedup: always
                parameters:
                  words: { type: bucket, edges: [1, 50] }
                  pinned: { type: flag }
        """)
        ts = gen.render_ts(schema)
        self.assertIn("export const CATALOG_VERSION = 2 as const;", ts)
        self.assertIn('export const INCLUDES = [{ name: "common", version: 2 }] as const;', ts)
        self.assertIn('export const PaywallSource = ["onboarding", "settings", "limit"] as const;', ts)
        self.assertIn("export type PaywallSource = (typeof PaywallSource)[number];", ts)
        self.assertIn('entry_saved: { words: "0" | "1_49" | "50_plus"; pinned: boolean };', ts)
        self.assertIn("internal_device: Record<string, never>;", ts)
        self.assertIn('"first_open"', ts.split("COMMON_EVENT_NAMES = [")[1].split("]")[0])
        self.assertNotIn('"entry_saved"', ts.split("COMMON_EVENT_NAMES = [")[1].split("]")[0])

    def test_reserved_type_name_is_rejected(self):
        schema = load("""\
            dialect: envelope
            events:
              - name: a_done
                kind: outcome
                dedup: always
                parameters:
                  x: { type: enum, type_name: EventName, values: [p] }
        """)
        with self.assertRaises(gen.SchemaError):
            gen.render_ts(schema)


class CheckedInOutputs(unittest.TestCase):

    def test_common_outputs_are_current(self):
        schema = gen.load(COMMON)
        folder = ROOT / "Schema" / "common"
        self.assertEqual(gen.render_json(schema), (folder / "common.catalog.json").read_text(encoding="utf-8"))
        self.assertEqual(gen.render_ts(schema), (folder / "common.catalog.ts").read_text(encoding="utf-8"))

    def test_example_including_common_is_current(self):
        schema = gen.load(ROOT / "Schema" / "example-common.yaml")
        self.assertEqual(gen.render_json(schema), (ROOT / "Schema" / "example-common.catalog.json").read_text(encoding="utf-8"))
        self.assertEqual(gen.render_ts(schema), (ROOT / "Schema" / "example-common.catalog.ts").read_text(encoding="utf-8"))
        swift = ROOT / "Tests" / "AnalyticsBatchSinkTests" / "Generated" / "JournalAnalytics.swift"
        self.assertEqual(gen.render(schema), swift.read_text(encoding="utf-8"))

    def test_package_sent_events_match_core(self):
        """AnalyticsCore が自分で送る出来事（CommonEvent）は、common.yaml と同じ名前・引数・値で書く。"""
        source = (ROOT / "Sources" / "AnalyticsCore" / "CommonEvent.swift").read_text(encoding="utf-8")
        schema = gen.load(COMMON)
        for event in (e for e in schema.events if e.sent_by == "package"):
            self.assertIn(f'"{event.name}"', source)
            for parameter in event.parameters:
                self.assertIn(f'"{parameter.key}"', source)
                for value in parameter.values:
                    self.assertIn(f'"{value}"' if gen.lower_camel(value) != value else f"case {value}", source)


class AuditWithCommon(unittest.TestCase):

    def test_unfired_common_events_are_noted_not_failed(self):
        schema = app("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    values: [home]
            events:
              - name: entry_saved
                kind: outcome
                dedup: always
        """)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Sites.swift"
            source.write_text(textwrap.dedent("""
                analytics.track(.entrySaved)
                view.trackScreen(.screenViewed(screen: .settings))
            """), encoding="utf-8")
            problems = gen.audit(schema, [Path(directory)])
            notes = gen.unfired_common(schema, [Path(directory)])
        # 共通の値（settings）を直書きしても、アプリが足した値（home）を直書きする理由にはならない
        self.assertEqual(problems, [])
        self.assertIn("paywall_shown", notes)
        self.assertNotIn("screen_viewed", notes)
        self.assertNotIn("first_open", notes)

    def test_app_events_must_still_be_fired(self):
        schema = app("""\
            events:
              - name: entry_saved
                kind: outcome
                dedup: always
        """)
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "Empty.swift").write_text("", encoding="utf-8")
            problems = gen.audit(schema, [Path(directory)])
        self.assertEqual(problems, ["entry_saved（.entrySaved）を撃っている場所が無い"])


class OptionalParameters(unittest.TestCase):

    def test_swift_json_and_ts(self):
        schema = load("""\
            dialect: envelope
            events:
              - name: sheet_closed
                kind: outcome
                dedup: always
                parameters:
                  via: { type: enum, values: [button, swipe] }
                  plan: { type: enum, values: [yearly, monthly], optional: true }
                  open_s: { type: count, optional: true }
        """)
        swift = gen.render(schema)
        self.assertIn("case sheetClosed(via: Via, plan: Plan? = nil, openS: Int? = nil)", swift)
        self.assertIn('var parameters: [String: AnalyticsValue] = ["via": .text(via.rawValue)]', swift)
        self.assertIn('if let plan { parameters["plan"] = .text(plan.rawValue) }', swift)
        self.assertIn('if let openS { parameters["open_s"] = .count(openS) }', swift)
        parameters = json.loads(gen.render_json(schema))["events"][0]["parameters"]
        self.assertNotIn("optional", parameters[0])
        self.assertTrue(parameters[1]["optional"])
        ts = gen.render_ts(schema)
        self.assertIn("sheet_closed: { via: Via; plan?: Plan; open_s?: number };", ts)
        self.assertIn('plan: { type: "enum", origin: "app", optional: true,', ts)

    def test_all_optional_starts_empty(self):
        schema = load("""\
            dialect: envelope
            events:
              - name: a_done
                kind: outcome
                dedup: always
                parameters:
                  n: { type: count, optional: true }
        """)
        self.assertIn("var parameters: [String: AnalyticsValue] = [:]", gen.render(schema))

    def test_must_be_bool(self):
        with self.assertRaises(gen.SchemaError):
            load("""\
                dialect: envelope
                events:
                  - name: a_done
                    kind: outcome
                    dedup: always
                    parameters:
                      n: { type: count, optional: yes }
            """)

    def test_common_product_is_optional(self):
        closed = next(e for e in gen.load(COMMON).events if e.name == "paywall_closed")
        self.assertTrue(next(p for p in closed.parameters if p.key == "product").optional)

    def test_extend_can_make_common_parameter_optional_but_not_required(self):
        schema = app("""\
            extend:
              - name: paywall_closed
                parameters:
                  via: { optional: true }
        """)
        closed = next(e for e in schema.events if e.name == "paywall_closed")
        self.assertTrue(next(p for p in closed.parameters if p.key == "via").optional)
        with self.assertRaises(gen.SchemaError) as caught:
            app("""\
                extend:
                  - name: paywall_closed
                    parameters:
                      product: { optional: false }
            """)
        self.assertIn("optional に書けるのは true だけ", str(caught.exception))


class SwiftDescriptions(unittest.TestCase):

    def test_descriptions_can_be_left_out(self):
        body = """\
            dialect: envelope
            swift:
              descriptions: {flag}
            events:
              - name: a_done
                kind: outcome
                dedup: always
                description: 説明の文
                trigger: 押したとき
                parameters:
                  via: {{ type: enum, values: [x], description: 値の説明 }}
        """
        self.assertIn("説明の文", gen.render(load(body.format(flag="true"))))
        swift = gen.render(load(body.format(flag="false")))
        for text in ("説明の文", "押したとき", "値の説明"):
            self.assertNotIn(text, swift)
        self.assertIn("/// `a_done.via` の値。\n", swift)


def write_sources(directory: str, text: str, name: str = "Sites.swift") -> list[Path]:
    (Path(directory) / name).write_text(textwrap.dedent(text), encoding="utf-8")
    return [Path(directory)]


class AuditAdopterCases(unittest.TestCase):

    def schema(self, extra: str = ""):
        return app("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    values: [home, shop]
              - name: paywall_shown
                parameters:
                  source:
                    values: [teaser, gate_402]
        """ + extra)

    def test_values_added_to_a_type_are_counted_per_type(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, """
                view.trackScreen(.screenViewed(screen: .home))
                analytics.track(.tapped(target: .close, screen: .shop))
            """)
            self.assertEqual(gen.audit(self.schema(), roots), [])

    def test_missing_value_names_the_type_and_its_events(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, "view.trackScreen(.screenViewed(screen: .home))\n")
            problems = gen.audit(self.schema(), roots)
        self.assertEqual(len(problems), 1)
        self.assertIn("ScreenName.shop を撃っている場所が無い", problems[0])
        self.assertIn("screen_viewed.screen", problems[0])
        self.assertIn("tapped.screen", problems[0])

    def test_a_common_literal_does_not_demand_app_literals(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, """
                analytics.track(.paywallClosed(source: .onboarding, pwId: id, result: .dismissed, via: .later, openS: 1))
                analytics.track(.paywallClosed(source: source, pwId: id, result: .dismissed, via: .later, openS: 1))
            """)
            self.assertEqual(gen.audit(self.schema(), roots), [])

    def test_events_built_away_from_track_are_found(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, """
                struct PaywallVisit {
                    var shown: AppEvent { .paywallShown(source: .teaser, pwId: id, nth: nth) }
                }
                send { .paywallShown(source: .gate402, pwId: $0, nth: 1) }
                view.trackImpression(visit.shown)
            """)
            schema = self.schema()
            self.assertEqual(gen.audit(schema, roots), [])
            self.assertNotIn("paywall_shown", gen.unfired_common(schema, roots))

    def test_generated_files_and_comments_do_not_count(self):
        schema = app("""\
            events:
              - name: entry_saved
                kind: outcome
                dedup: always
        """)
        with tempfile.TemporaryDirectory() as directory:
            write_sources(directory, gen.render(schema), name="AppAnalytics.swift")
            roots = write_sources(directory, "// analytics.track(.entrySaved)\n")
            self.assertEqual(gen.audit(schema, roots), ["entry_saved（.entrySaved）を撃っている場所が無い"])


class TrackReason(unittest.TestCase):

    SITE = "analytics.track(.paywallShown(source: .settings, pwId: id, nth: 1))\n"

    def test_impression_through_track_fails_without_a_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            problems = gen.audit(app(), write_sources(directory, self.SITE))
        self.assertEqual(len(problems), 1)
        self.assertIn("track_reason", problems[0])

    def test_reason_in_extend_allows_track_and_keeps_track_impression(self):
        schema = app("""\
            extend:
              - name: paywall_shown
                track_reason: シートを出したコールバックから送る
        """)
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, self.SITE + "view.trackImpression(.paywallShown(source: .limit, pwId: id, nth: 2))\n")
            self.assertEqual(gen.audit(schema, roots), [])

    def test_reason_only_on_screen_or_impression(self):
        with self.assertRaises(gen.SchemaError) as caught:
            app("""\
                events:
                  - name: entry_saved
                    kind: outcome
                    dedup: always
                    track_reason: なぜか
            """)
        self.assertIn("screen か impression", str(caught.exception))
        with self.assertRaises(gen.SchemaError):
            app("""\
                extend:
                  - name: paywall_closed
                    track_reason: なぜか
            """)

    def test_app_event_can_carry_a_reason(self):
        schema = app("""\
            events:
              - name: nudge_offer_shown
                kind: impression
                dedup: always
                track_reason: お知らせのタスクから送る
        """)
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, "analytics.track(.nudgeOfferShown)\n")
            self.assertEqual(gen.audit(schema, roots), [])


class CommonAdditions(unittest.TestCase):

    def test_sign_in_provider_has_other_and_is_extensible(self):
        signed_in = next(e for e in gen.load(COMMON).events if e.name == "signed_in")
        provider = next(p for p in signed_in.parameters if p.key == "provider")
        self.assertIn("other", provider.values)
        self.assertTrue(provider.extensible)


if __name__ == "__main__":
    unittest.main()
