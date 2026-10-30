from pathlib import Path
import sys
import unittest
import math
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
sys.path.insert(0,str(ROOT/'src/models'))
from examples.run_demo import build_payload,synthetic_rows
from count_model import beta_binomial_log_pmf

class SyntheticDemoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.data=build_payload()

    def test_only_declared_synthetic_population(self):
        self.assertEqual(self.data['data_kind'],'synthetic')
        self.assertEqual({r[0] for r in self.data['employees']},set(range(1,31)))
        self.assertEqual({r[1] for r in self.data['employees']},{1,2,3})
        self.assertEqual(len(self.data['grid']),108)
        self.assertEqual(synthetic_rows(),synthetic_rows())

    def test_spike_recovers_and_persistent_activity_stays_higher(self):
        people={r[0]:r[2] for r in self.data['employees']}
        spike=[r[3] for r in people[3] if r[3] is not None]
        self.assertGreater(max(spike),spike[-1])
        self.assertGreater(people[2][-1][3],people[1][-1][3])

    def test_training_missingness_and_complete_zero(self):
        people={r[0]:r[2] for r in self.data['employees']}
        self.assertTrue(all(r[3] is None for r in people[30]))
        missing=next(r for r in people[1] if r[7]==3)
        self.assertEqual(missing[3],missing[6])
        zero=next(r for r in people[4] if r[7]==2)
        self.assertEqual(zero[3],0)

    def test_probability_and_sensitivity_bounds(self):
        for _,_,history in self.data['employees']:
            for row in history:
                if row[3] is not None:self.assertTrue(0<=row[4]<=row[3]<=row[5]<=1)

    def test_standard_library_pmf_matches_scipy_oracle(self):
        from scipy.stats import betabinom
        for n in (1,10,100):
            for k in (0,1,n):
                self.assertAlmostEqual(beta_binomial_log_pmf(k,n,1.7,16.0),float(betabinom.logpmf(k,n,1.7,16.0)),places=10)

if __name__=='__main__':unittest.main()
