import copy
from datetime import date,timedelta
from itertools import product
import json
import math
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src'/'models'))
from weekly_scenarios import (transitions,scenario_grid,activity_log_ratio,filter_history,
                              observation_status,training_boundary,binomial_log_pmf)
from count_model import beta_binomial_log_pmf


class WeeklyScenarioTests(unittest.TestCase):
    def setUp(self):
        self.config=json.loads((ROOT/'src/models/weekly_scenarios.json').read_text())
        self.scenarios=scenario_grid(self.config)
        self.base={None:dict(mean=.2,kappa=12.),20:dict(mean=.2,kappa=12.)}
    def row(self,week=date(2026,5,28),k=2,n=20,**kwargs):
        return dict(employee_id=1,location_id=20,week_start=week,activity_successes=k,activity_trials=n,
                    actor_positive_checks=k,is_partial_week=False,location_source_days=7,action_only_checks=0,
                    multi_actor_checks=0,unknown_actor_checks=0,incomplete_discount_checks=0,**kwargs)

    def test_grid_stationarity_half_life_and_no_memory(self):
        self.assertEqual(len(self.scenarios),108)
        for s in self.scenarios:
            p=s['weekly_base_rate'];a=s['persistence'];b=s['onset']
            self.assertAlmostEqual(a*p+b*(1-p),p)
            self.assertAlmostEqual(b/(1-a+b),p)
            if s['memory_half_life_weeks']==0: self.assertEqual(a,b)
            else: self.assertAlmostEqual((a-b)**s['memory_half_life_weeks'],.5)

    def test_truncated_class_normalizes_and_likelihood_is_independent(self):
        n,m,c,odds=8,.2,12.,2.
        elevated=odds*m/(1-m+odds*m)
        weights=[math.exp(beta_binomial_log_pmf(k,n,elevated*c,(1-elevated)*c)) for k in range(n+1)]
        normalized=[x/sum(weights[1:]) for x in weights[1:]]
        self.assertAlmostEqual(sum(normalized),1)
        for k in range(1,n+1):
            ordinary=math.exp(beta_binomial_log_pmf(k,n,m*c,(1-m)*c))
            expected=math.log(normalized[k-1]/ordinary)
            self.assertAlmostEqual(activity_log_ratio(k,n,m,c,odds,1),expected,places=12)

    def test_forward_result_matches_hidden_path_enumeration(self):
        s=[x for x in self.scenarios if x['is_reference']][0]
        rows=[self.row(k=k) for k in (1,8,2)]
        for i,r in enumerate(rows):r['week_start']+=timedelta(weeks=i)
        actual=filter_history(rows,[s],self.base,date(2026,5,28))
        totals=[0.,0.]
        for states in product((0,1),repeat=3):
            weight=s['initial_probability'] if states[0] else 1-s['initial_probability']
            for i,state in enumerate(states):
                if i:
                    transition=s['persistence'] if states[i-1] else s['onset']
                    weight*=transition if state else 1-transition
                if state:
                    weight*=math.exp(activity_log_ratio(rows[i]['activity_successes'],20,.2,12.,2.,1.))
            totals[states[-1]]+=weight
        self.assertAlmostEqual(actual[-1]['reference_probability'],totals[1]/sum(totals),places=12)

    def test_zeros_missing_training_and_gaps(self):
        s=[x for x in self.scenarios if x['is_reference']]
        a=self.row(k=0)
        b=self.row(date(2026,6,11),k=0);b['is_partial_week']=True
        result=filter_history([a,b],s,self.base,date(2026,5,28))
        self.assertEqual(result[0]['reference_probability'],0.)
        self.assertEqual(result[1]['elapsed_model_weeks'],2)
        self.assertEqual(result[1]['reference_probability'],result[1]['reference_prior'])
        self.assertGreater(result[1]['reference_probability'],0.)
        a['week_start']=date(2026,5,21)
        result=filter_history([a,b],s,self.base,date(2026,5,28))
        self.assertIsNone(result[0]['reference_probability'])
        self.assertEqual(result[1]['reference_probability'],s[0]['initial_probability'])
        for name in ('action_only_checks','multi_actor_checks','unknown_actor_checks','incomplete_discount_checks'):
            r=self.row();r[name]=1
            self.assertTrue(observation_status(r).startswith('prior_only_'))

    def test_prefix_stability_and_boundaries(self):
        a=self.row();b=self.row(date(2026,6,4),k=7)
        prefix=filter_history([a],self.scenarios,self.base,a['week_start'])
        extended=filter_history([a,b],self.scenarios,self.base,a['week_start'])
        self.assertEqual(prefix[0],extended[0])
        self.assertTrue(all(0<=p<=1 for p in extended[1]['scenario_probabilities']))
        with self.assertRaises(ValueError):filter_history([a,a],self.scenarios,self.base,a['week_start'])
        for args in ((0,1),(.2,-1),(1,1)):
            with self.assertRaises(ValueError):transitions(*args)
        with self.assertRaises(ValueError):activity_log_ratio(0,10,.2,10.,2.,1.)

    def test_training_split_and_binomial_oracle(self):
        rows=[self.row(date(2026,4,30)+timedelta(weeks=i)) for i in range(6)]
        weeks,cutoff=training_boundary(rows,4)
        self.assertEqual(cutoff,date(2026,5,28))
        self.assertTrue(all(w<cutoff for w in weeks))
        for k in range(11):
            expected=math.comb(10,k)*.2**k*.8**(10-k)
            self.assertAlmostEqual(math.exp(binomial_log_pmf(k,10,.2)),expected,places=13)


if __name__=='__main__':unittest.main()
