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
        self.assertEqual(event["parameters"][0], {"key": "source", "type": "enum", "values": ["paste", "sample_copy"]})
        self.assertEqual(
            event["parameters"][1],
            {"key": "nth", "type": "bucket", "edges": [1, 2, 3], "values": ["0", "1_1", "2_2", "3_plus"]},
        )
        self.assertEqual(
            event["parameters"][2], {"key": "render_id", "type": "token", "pattern": "[a-z]+", "maxLength": 20}
        )
        self.assertEqual(event["parameters"][3], {"key": "items", "type": "count"})

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


if __name__ == "__main__":
    unittest.main()
