import copy
from itertools import product
import json
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "models"))
from inference import filter_sequence, log_likelihood_ratio, predict, update, validate_parameters
from demo import run_demo


class InferenceTests(unittest.TestCase):
    def setUp(self):
        self.p = json.loads((ROOT / "demo/synthetic.json").read_text())

    def test_joint_network_by_independent_enumeration(self):
        for d, t in product([None] + self.p["activity_states"], [None] + self.p["tip_states"]):
            weights = []
            for hidden, prior in (("0", 0.95), ("1", 0.05)):
                joint = 0
                for activity, tip in product(self.p["activity_states"], self.p["tip_states"]):
                    if (d is None or d == activity) and (t is None or t == tip):
                        joint += self.p["activity_given_event"][hidden][activity] * self.p["tip_given_activity_event"][hidden][activity][tip]
                weights.append(prior * joint)
            expected = weights[1] / sum(weights)
            actual = update(0.05, log_likelihood_ratio(d, t, self.p))
            self.assertAlmostEqual(actual, expected)

    def test_missing_evidence_keeps_prediction(self):
        self.assertAlmostEqual(log_likelihood_ratio(None, None, self.p), 0)
        self.assertAlmostEqual(update(0.2, 0), 0.2)

    def test_calendar_gap_matches_repeated_transitions(self):
        for a, b in ((0.8, 0.02), (0, 1), (1, 0), (0.2, 0.9)):
            expected = 0.4
            for n in range(1, 15):
                expected = a * expected + b * (1 - expected)
                self.assertAlmostEqual(predict(0.4, a, b, n), expected)

    def test_temporal_filter_matches_all_hidden_paths(self):
        rows = run_demo(self.p)[:3]
        weights = [0, 0]
        for states in product(("0", "1"), repeat=len(rows)):
            weight = self.p["initial_probability"] if states[0] == "1" else 1 - self.p["initial_probability"]
            for i, (state, row) in enumerate(zip(states, rows)):
                if i:
                    p1 = self.p["persistence"] if states[i-1] == "1" else self.p["onset"]
                    weight *= p1 if state == "1" else 1-p1
                d, t = row["activity_state"], row["tip_state"]
                weight *= self.p["activity_given_event"][state][d]
                if t is not None:
                    weight *= self.p["tip_given_activity_event"][state][d][t]
            weights[int(states[-1])] += weight
        self.assertAlmostEqual(rows[-1]["posterior_probability"], weights[1]/sum(weights))

    def test_demo_rises_falls_and_handles_gap(self):
        rows = run_demo(self.p)
        self.assertLess(rows[0]["posterior_probability"], rows[0]["predicted_prior"])
        self.assertGreater(rows[1]["posterior_probability"], rows[0]["posterior_probability"])
        self.assertLess(rows[3]["posterior_probability"], rows[2]["posterior_probability"])
        self.assertEqual(rows[3]["elapsed_weeks"], 2)
        self.assertAlmostEqual(rows[4]["posterior_probability"], rows[4]["predicted_prior"])

    def test_replay_is_deterministic_and_later_weeks_do_not_change_past(self):
        rows = run_demo(self.p)
        self.assertEqual(rows, filter_sequence(rows, self.p))
        self.assertEqual(rows[:2], filter_sequence(rows[:2], self.p))

    def test_real_data_is_refused(self):
        rows = run_demo(self.p)
        rows[0]["data_kind"] = "real"
        with self.assertRaisesRegex(ValueError, "must not score real"):
            filter_sequence(rows, self.p)

    def test_bad_parameters_and_duplicate_dates_are_refused(self):
        p = copy.deepcopy(self.p)
        p["activity_given_event"]["0"]["ordinary"] = 0.5
        with self.assertRaises(ValueError):
            validate_parameters(p)
        rows = run_demo(self.p)
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            filter_sequence([rows[0], rows[0]], self.p)
        rows[0]["location_id"] = "DIFFERENT"
        with self.assertRaisesRegex(ValueError, "one employee/location"):
            filter_sequence(rows, self.p)

    def test_extreme_log_odds_are_stable(self):
        self.assertEqual(update(0.1, 10000), 1)
        self.assertEqual(update(0.9, -10000), 0)
        self.assertEqual(update(0, 10), 0)
        self.assertEqual(update(1, -10), 1)
        with self.assertRaises(ValueError):
            update(0.5, math.nan)


if __name__ == "__main__":
    unittest.main()
