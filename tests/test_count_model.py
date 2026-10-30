import math
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "models"))
from count_model import beta_binomial_log_pmf, beta_cdf, beta_quantile, summarize_rate


class CountModelTests(unittest.TestCase):
    def test_uniform_count_prediction_and_independent_moments(self):
        for n in (0, 1, 10, 60):
            p = [math.exp(beta_binomial_log_pmf(k, n, 1., 1.)) for k in range(n+1)]
            self.assertAlmostEqual(sum(p), 1., places=11)
            self.assertTrue(all(abs(x-1/(n+1)) < 1e-12 for x in p))
        a, b, n = 3., 8., 30
        p = [math.exp(beta_binomial_log_pmf(k, n, a, b)) for k in range(n+1)]
        mean = sum(k*x for k, x in enumerate(p))
        variance = sum((k-mean)**2*x for k, x in enumerate(p))
        self.assertAlmostEqual(mean, n*a/(a+b), places=10)
        self.assertAlmostEqual(variance, n*a*b*(a+b+n)/((a+b)**2*(a+b+1)), places=9)

    def test_cdf_against_polynomials(self):
        for x in (.001, .1, .45, .8, .999):
            self.assertAlmostEqual(beta_cdf(x, 1, 1), x, places=12)
            self.assertAlmostEqual(beta_cdf(x, 2, 2), 3*x*x-2*x**3, places=12)
            self.assertAlmostEqual(beta_cdf(x, 1, 101), 1-(1-x)**101, places=11)

    def test_interval_and_sample_size(self):
        small, large = summarize_rate(1, 2), summarize_rate(100, 200)
        self.assertAlmostEqual(small['rate_mean'], .5)
        self.assertAlmostEqual(small['rate_variance'], .05)
        self.assertAlmostEqual(small['rate_lower_95'], .094299324050246, places=11)
        self.assertAlmostEqual(large['rate_lower_95'], .43129118363, places=9)
        self.assertLess(large['rate_variance'], small['rate_variance'])
        self.assertGreater(large['rate_lower_95'], small['rate_lower_95'])

    def test_zero_is_not_missing(self):
        no_trials, zero = summarize_rate(0, 0), summarize_rate(0, 20)
        self.assertIsNone(no_trials['rate_mean'])
        self.assertGreater(zero['rate_mean'], 0)
        self.assertLess(zero['rate_mean'], .05)
        self.assertEqual(zero, summarize_rate(0, 20))

    def test_boundaries_and_large_shapes(self):
        for a, b in ((1, 10001), (10001, 1), (5001, 5001), (.5, .5)):
            q = beta_quantile(.025, a, b)
            self.assertAlmostEqual(beta_cdf(q, a, b), .025, places=8)
        for k, n in ((-1, 10), (11, 10), (1.1, 5), (True, 1), (0, -1)):
            with self.assertRaises(ValueError): summarize_rate(k, n)
        for shape in (0, -1, float('inf'), float('nan')):
            with self.assertRaises(ValueError): summarize_rate(1, 2, shape, 1)


if __name__ == '__main__':
    unittest.main()
