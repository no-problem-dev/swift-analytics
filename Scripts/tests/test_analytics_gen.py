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
        with tempfile.TemporaryDirectory() as directory:
            custom = Path(directory) / "mine.yaml"
            custom.write_text(textwrap.dedent("""\
                version: 1
                name: common
                dialect: envelope
                events:
                  - name: a_done
                    kind: outcome
                    dedup: always
                    parameters:
                      mode: { type: enum, type_name: Mode, values: [a, b] }
            """), encoding="utf-8")
            path = Path(directory) / "analytics.yaml"
            path.write_text(textwrap.dedent("""\
                dialect: envelope
                include: common
                extend:
                  - name: a_done
                    parameters:
                      mode:
                        values: [c]
            """), encoding="utf-8")
            with self.assertRaises(gen.SchemaError) as caught:
                gen.load(path, common=custom)
        self.assertIn("extensible: true の enum でない", str(caught.exception))

    def test_app_can_add_first_open_kinds(self):
        schema = app("""\
            extend:
              - name: first_open
                parameters:
                  kind:
                    values: [existing]
        """)
        first_open = next(e for e in json.loads(gen.render_json(schema))["events"] if e["name"] == "first_open")
        self.assertEqual(first_open["parameters"][0]["values"], ["fresh", "upgraded", "existing"])
        # パッケージが送る出来事なので、足しても Swift の型には出ない
        self.assertNotIn("FirstOpenKind", gen.render(schema))

    def test_extend_can_name_the_bands_of_a_common_bucket(self):
        schema = app("""\
            extend:
              - name: paywall_shown
                parameters:
                  nth:
                    labels: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "10+"]
        """)
        swift = gen.render(schema)
        self.assertIn('labels: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "10+"]', swift)
        shown = next(e for e in json.loads(gen.render_json(schema))["events"] if e["name"] == "paywall_shown")
        nth = next(p for p in shown["parameters"] if p["key"] == "nth")
        self.assertEqual(nth["values"][-1], "10+")
        self.assertEqual(nth["edges"], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

    def test_extend_labels_are_checked_and_only_for_buckets(self):
        self.assertRejected("""\
            extend:
              - name: paywall_shown
                parameters:
                  nth:
                    labels: ["0", "1"]
        """, "1 つ多く")
        self.assertRejected("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    labels: [a]
        """, "bucket の引数にだけ")
        self.assertRejected("""\
            extend:
              - name: paywall_shown
                parameters:
                  nth:
                    edges: [1, 5]
        """, "変えられない")

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


class BucketLabels(unittest.TestCase):

    def body(self, labels: str, edges: str = "[1, 2, 10]") -> str:
        return f"""\
            dialect: envelope
            events:
              - name: a_done
                kind: outcome
                dedup: always
                parameters:
                  days: {{ type: bucket, edges: {edges}, labels: {labels} }}
            user_properties:
              - name: streak_band
                type: bucket
                edges: {edges}
                labels: {labels}
        """

    def test_labels_reach_swift_json_and_ts(self):
        schema = load(self.body('[0, 1, "2_9", "10+"]'))
        swift = gen.render(schema)
        self.assertIn('.bucket(days, edges: [1, 2, 10], labels: ["0", "1", "2_9", "10+"])', swift)
        self.assertIn('AnalyticsValue.bucket(value, edges: [1, 2, 10], labels: ["0", "1", "2_9", "10+"]).description', swift)
        document = json.loads(gen.render_json(schema))
        self.assertEqual(document["events"][0]["parameters"][0]["values"], ["0", "1", "2_9", "10+"])
        self.assertEqual(document["userProperties"][0]["values"], ["0", "1", "2_9", "10+"])
        self.assertIn('days: "0" | "1" | "2_9" | "10+"', gen.render_ts(schema))

    def test_labels_are_checked(self):
        for labels, edges, fragment in (
            ('["0", "1"]', "[1, 2, 10]", "1 つ多く"),
            ('["0", "1", "1", "x"]', "[1, 2, 10]", "同じ名前"),
            ('["0", "1", "2", "Ten"]', "[1, 2, 10]", "英小文字"),
            ('["0", "1", "2", "3"]', "[10, 2, 1]", "小さい順"),
        ):
            with self.assertRaises(gen.SchemaError) as caught:
                load(self.body(labels, edges))
            self.assertIn(fragment, str(caught.exception))

    def test_labels_only_on_buckets(self):
        with self.assertRaises(gen.SchemaError) as caught:
            load("""\
                dialect: envelope
                events:
                  - name: a_done
                    kind: outcome
                    dedup: always
                    parameters:
                      n: { type: count, labels: [a] }
            """)
        self.assertIn("bucket にだけ", str(caught.exception))


class ExtensibleCommonEnums(unittest.TestCase):

    def test_every_common_enum_is_extensible(self):
        closed = {
            p.swift_type_name for e in gen.load(COMMON).events for p in e.parameters
            if p.type == "enum" and not p.extensible
        }
        self.assertEqual(closed, set())

    def test_app_can_add_close_results(self):
        schema = app("""\
            extend:
              - name: paywall_closed
                parameters:
                  result:
                    values: [continue_free]
                  product:
                    values: [quarterly]
        """)
        purchase = next(e for e in schema.events if e.name == "purchase_completed")
        self.assertIn("quarterly", next(p for p in purchase.parameters if p.key == "product").values)


class ExtendByCommonTypeName(unittest.TestCase):
    """`extend:` で足す引数が共通の enum を型の名前だけで使う。"""

    def plan(self, spec: str):
        schema = app("""\
            extend:
              - name: paywall_plan_selected
                parameters:
                  to:
                    values: [quarterly]
                  from:
                    type: enum
                    type_name: PlanPeriod
        """.rstrip(" ") + spec)
        event = next(e for e in schema.events if e.name == "paywall_plan_selected")
        return schema, next(p for p in event.parameters if p.key == "from")

    def test_type_name_alone_takes_the_values_and_extensible(self):
        schema, parameter = self.plan("")
        self.assertEqual(parameter.values, ["yearly", "monthly", "weekly", "lifetime", "quarterly"])
        self.assertTrue(parameter.extensible)
        self.assertEqual(gen.render(schema).count("public enum PlanPeriod"), 1)

    def test_copied_values_still_pass(self):
        _, parameter = self.plan("""\
                    extensible: true
                    values: [yearly, monthly, weekly, lifetime, quarterly]
        """)
        self.assertTrue(parameter.extensible)


class AuditMappingSwitch(unittest.TestCase):
    """アプリの値から計測の値へ写す switch が返す値を、撃っている値として数える。"""

    def schema(self):
        return app("""\
            extend:
              - name: screen_viewed
                parameters:
                  screen:
                    values: [room, diary, about]
        """)

    def test_values_returned_by_a_mapping_switch_count(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, """
                view.trackScreen(AppEvent.screenViewed(screen: .about))
                view.trackScreen(AppEvent.screenViewed(screen: tab.analyticsScreen))
                extension Tab {
                    var analyticsScreen: AppEvent.ScreenName {
                        switch self {
                        case .home: .room
                        case .log(let day): .diary
                        }
                    }
                }
            """)
            self.assertEqual(gen.audit(self.schema(), roots), [])

    def test_case_patterns_and_other_types_do_not_count(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, """
                view.trackScreen(.screenViewed(screen: .about))
                func screen(for tab: Tab) -> ScreenName {
                    switch tab {
                    case .diary: return .room
                    default: return .about
                    }
                }
                var other: OtherKind { switch self { case .x: .diary } }
            """)
            problems = gen.audit(self.schema(), roots)
        self.assertEqual(problems, ["ScreenName.diary を撃っている場所が無い（screen_viewed.screen・tapped.screen のどれからも）"])


class AuditTypedValues(unittest.TestCase):
    """出来事の式の外で、型の付いた所に書いた値を撃っている値として数える（ここいいねで読み違えた形）。"""

    def schema(self):
        return app("""\
            events:
              - name: error_shown
                kind: impression
                dedup: always
                parameters:
                  area: { type: enum, values: [sync, consult, import, invite] }
              - name: blocked
                kind: outcome
                dedup: always
                parameters:
                  by: { type: enum, type_name: BlockedBy, values: [none, offline, other] }
              - name: answer_finished
                kind: outcome
                dedup: always
                parameters:
                  result: { type: enum, type_name: AnswerResult, values: [completed, cancelled, failed] }
        """)

    BASE = """
        analytics.track(AppEvent.blocked(by: .offline))
        analytics.track(AppEvent.answerFinished(result: answer.result))
        analytics.trackImpression(AppEvent.errorShown(area: .consult))
    """

    def problems(self, text: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            return gen.audit(self.schema(), write_sources(directory, self.BASE + text))

    WIRED = """
        func blockedBy(_ decision: Decision) -> AppEvent.BlockedBy {
            guard case let .skip(reason) = decision else { return AppEvent.BlockedBy.none }
            return reason.isOffline ? .offline : .other
        }
        final class Answer {
            var result: AppEvent.AnswerResult = .cancelled
            func receive(_ event: Event) {
                switch event {
                case .done: result = .completed
                case .failed: result = .failed
                }
            }
        }
        enum ImportTelemetry { static let area = AppEvent.Area.import }
        func noteArea(_ area: AppEvent.Area) { pending = area }
        noteArea(.sync)
        let inviteArea: AppEvent.Area = .invite
    """

    def test_values_written_where_the_type_is_known_count(self):
        self.assertEqual(self.problems(self.WIRED), [])

    def test_a_value_after_guard_case_is_not_cut(self):
        problems = self.problems(self.WIRED.replace("return AppEvent.BlockedBy.none", "return .other"))
        self.assertEqual(problems, ["BlockedBy.none を撃っている場所が無い（blocked.by のどれからも）"])

    def test_a_missing_value_is_still_reported(self):
        problems = self.problems(self.WIRED.replace("noteArea(.sync)", ""))
        self.assertEqual(problems, ["Area.sync を撃っている場所が無い（error_shown.area のどれからも）"])

    def test_member_assignment_in_another_file_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            write_sources(directory, self.BASE + self.WIRED.replace("case .failed: result = .failed", ""))
            roots = write_sources(directory, "answer.result = .failed\n", name="Other.swift")
            self.assertEqual(gen.audit(self.schema(), roots), [])

    def test_an_app_type_with_the_same_name_does_not_count(self):
        problems = self.problems(self.WIRED + """
            enum Area { case transit, sync }
            func pick(_ area: Area) {}
            let fallback: Area = .transit
            let other = Area.sync
        """.replace("noteArea(.sync)", ""))
        self.assertEqual(problems, [])
        problems = self.problems(self.WIRED.replace("noteArea(.sync)", "") + """
            enum Area { case sync }
            let other = Area.sync
        """)
        self.assertEqual(problems, ["Area.sync を撃っている場所が無い（error_shown.area のどれからも）"])

    def test_labels_of_typed_properties_and_extension_bodies_count(self):
        problems = self.problems(self.WIRED.replace("noteArea(.sync)", "").replace("let inviteArea: AppEvent.Area = .invite", "") + """
            struct Banner: View { let area: AppEvent.Area }
            Banner(area: .sync)
            extension AppEvent.Area {
                init(_ place: Domain.Place) {
                    self = switch place {
                    case .home: .invite
                    }
                }
            }
        """)
        self.assertEqual(problems, [])

    def test_raw_value_types_are_not_checked(self):
        problems = self.problems("""
            func blockedBy(_ code: String) -> AppEvent.BlockedBy {
                AppEvent.BlockedBy(rawValue: code) ?? .other
            }
            func answer(_ code: String) -> AppEvent.AnswerResult { Self(rawValue: code) ?? .failed }
            noteArea(.sync)
            func noteArea(_ area: AppEvent.Area) {}
        """)
        self.assertEqual(problems, [
            "Area.import を撃っている場所が無い（error_shown.area のどれからも）",
            "Area.invite を撃っている場所が無い（error_shown.area のどれからも）",
        ])

    def test_a_switch_into_a_typed_tuple_counts(self):
        """読書メモリーの `OnboardingMilestone.event`。タプルの型に T がある変数へ switch の式で入れる。"""
        wired = self.WIRED.replace("noteArea(.sync)", "").replace("let inviteArea: AppEvent.Area = .invite", "")
        problems = self.problems(wired + """
            var event: AppEvent {
                let (area, index): (AppEvent.Area, Int) = switch self {
                case .first: (.sync, 1)
                case .second: (.invite, 2)
                }
                return .errorShown(area: area)
            }
        """)
        self.assertEqual(problems, [])
        problems = self.problems(wired + """
            let pair: (area: AppEvent.Area, count: Int)? = (.sync, 1)
        """)
        self.assertEqual(problems, ["Area.invite を撃っている場所が無い（error_shown.area のどれからも）"])

    def test_a_tuple_without_the_type_does_not_count(self):
        wired = self.WIRED.replace("noteArea(.sync)", "")
        problems = self.problems(wired + """
            let (place, index): (Domain.Place, Int) = switch self { case .first: (.sync, 1) }
        """)
        self.assertEqual(problems, ["Area.sync を撃っている場所が無い（error_shown.area のどれからも）"])

    def test_a_default_argument_counts(self):
        """読書メモリーの `BookSearchView.init(registrationSource: … = .search)`。省いて呼べば既定値が渡る。"""
        wired = self.WIRED.replace("noteArea(.sync)", "")
        problems = self.problems(wired + """
            struct Search: View {
                let area: AppEvent.Area
                init(area: AppEvent.Area = .sync, onDone: (() -> Void)? = nil) { self.area = area }
            }
        """)
        self.assertEqual(problems, [])
        problems = self.problems(wired + """
            init(count: Int = 0, area: AppEvent.Area) {}
        """)
        self.assertEqual(problems, ["Area.sync を撃っている場所が無い（error_shown.area のどれからも）"])


class AuditSameNamedModifier(unittest.TestCase):
    """出来事と同じ名前の View の modifier は、出来事を作る所ではない。渡した値は数える。"""

    def schema(self):
        return app("""\
            events:
              - name: error_shown
                kind: impression
                dedup: always
                parameters:
                  area: { type: enum, values: [sync, consult] }
        """)

    MODIFIER = """
        extension View {
            public func errorShown(_ area: AppEvent.Area) -> some View { modifier(ErrorShown(area: area)) }
        }
        Text(message).errorShown(.consult)
        Text(message).errorShown(.sync)
    """

    def test_modifier_calls_alone_do_not_fire_the_event(self):
        with tempfile.TemporaryDirectory() as directory:
            problems = gen.audit(self.schema(), write_sources(directory, self.MODIFIER))
        self.assertEqual(problems, ["error_shown（.errorShown）を撃っている場所が無い"])

    def test_values_passed_to_the_modifier_count(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, self.MODIFIER + """
                content.task { analytics.trackImpression(AppEvent.errorShown(area: area)) }
            """)
            self.assertEqual(gen.audit(self.schema(), roots), [])

    def test_a_value_missing_from_the_modifier_calls_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            roots = write_sources(directory, self.MODIFIER.replace("Text(message).errorShown(.sync)", "") + """
                content.task { analytics.trackImpression(.errorShown(area: area)) }
            """)
            problems = gen.audit(self.schema(), roots)
        self.assertEqual(problems, ["Area.sync を撃っている場所が無い（error_shown.area のどれからも）"])


if __name__ == "__main__":
    unittest.main()
