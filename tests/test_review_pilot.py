import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'/'models'))
from review_pilot import prepare_population, validate_review, evaluate

def population(size=90,budget=5,per_band=4):
    return prepare_population([dict(employee_id=i+1,location_id=i%7+1,week_start='2026-08-13',
      model_observation_status='assumption_conditioned_activity',reference_probability=(i+1)/(size+1),
      activity_successes=(size-i)%11,activity_trials=20,actor_positive_checks=12)
      for i in range(size)],budget,per_band)

def review(case,y):
    return dict(case_id=case['case_id'],outcome='violation' if y else 'no_violation',
      label_basis='independent_policy_review',reviewed_by='independent_reviewer',evidence_reference='audit://evidence',
      policy_reference='approved policy version 1',review_notes='Inspected applicable policies and records',
      applicable_policy_confirmed=True,positive_checks_reviewed=12,full_week_scope_reviewed=True,violating_check_id='123',violating_business_date='2026-08-13')

class ReviewPilotTests(unittest.TestCase):
    def test_configured_run_identity_is_preserved(self):
        p=prepare_population(population(),5,4,batch_id='another-batch',model_run_id='another-model')
        result=evaluate(p,[])
        self.assertEqual(result['batch_id'],'another-batch')
        self.assertEqual(result['model_run_id'],'another-model')
        self.assertTrue(all(r['model_run_id']=='another-model' for r in p))

    def test_too_small_population_or_sample_refused(self):
        with self.assertRaises(ValueError):prepare_population(population()[:2],1,2)
        with self.assertRaises(ValueError):prepare_population(population(),5,1)

    def test_reproducible_order_independent_sample(self):
        p=population()
        raw=[{k:v for k,v in r.items() if k not in ('model_rank','baseline_rank')} for r in reversed(p)]
        self.assertEqual(p,prepare_population(raw,5,4))

    def test_all_top_cases_are_census_and_weights_represent_population(self):
        p=population()
        self.assertTrue(all(r['selected_for_review'] and r['inclusion_probability']==1 for r in p if r['model_rank']<=5 or r['baseline_rank']<=5))
        self.assertAlmostEqual(sum(1/r['inclusion_probability'] for r in p if r['selected_for_review']),len(p))

    def test_duplicate_or_uninformed_cohort_refused(self):
        p=population()
        with self.assertRaises(ValueError):prepare_population(p+[p[0]])
        p[0]['model_observation_status']='prior_only_partial_calendar'
        with self.assertRaises(ValueError):prepare_population(p)

    def test_heuristic_labels_refused(self):
        r=next(r for r in population() if r['selected_for_review'])
        label=review(r,1);label['label_basis']='risk_coefficient'
        with self.assertRaises(ValueError):validate_review(r,label)

    def test_partial_negative_or_unconfirmed_policy_refused(self):
        r=next(r for r in population() if r['selected_for_review'])
        label=review(r,0);label['positive_checks_reviewed']=1
        with self.assertRaises(ValueError):validate_review(r,label)
        label=review(r,1);label['applicable_policy_confirmed']=False
        with self.assertRaises(ValueError):validate_review(r,label)

    def test_no_fabricated_metrics_before_reviews(self):
        result=evaluate(population(),[])
        self.assertIsNone(result['weighted_brier'])
        self.assertIsNone(result['methods']['model']['precision_at_budget'])
        self.assertEqual(result['status'],'awaiting_independent_reviews')

    def test_unresolved_top_cases_show_identification_bounds(self):
        p=population();r=next(r for r in p if r['model_rank']==1)
        result=evaluate(p,[review(r,1)])
        self.assertEqual(result['methods']['model']['precision_identification_bounds'],[.2,1])
        self.assertIsNone(result['methods']['model']['precision_at_budget'])

    def test_disagreements_remain_unresolved_and_duplicates_not_double_counted(self):
        p=population();r=next(r for r in p if r['selected_for_review'])
        self.assertEqual(evaluate(p,[review(r,1)]*2)['decisive_reviews'],1)
        result=evaluate(p,[review(r,1),review(r,0)])
        self.assertEqual(result['decisive_reviews'],0)
        self.assertEqual(result['disputed_cases'],[r['case_id']])

    def test_weighted_estimates_match_independent_arithmetic(self):
        p=population();sample=[r for r in p if r['selected_for_review']]
        outcomes=[review(r,r['employee_id']%2) for r in sample]
        result=evaluate(p,outcomes)
        total=sum((r['employee_id']%2)/r['inclusion_probability'] for r in sample)
        brier=sum((r['reference_probability']-r['employee_id']%2)**2/r['inclusion_probability'] for r in sample)/len(p)
        top=sum(r['employee_id']%2 for r in p if r['model_rank']<=5)
        self.assertAlmostEqual(result['estimated_violating_weeks'],total)
        self.assertAlmostEqual(result['weighted_brier'],brier)
        self.assertAlmostEqual(result['methods']['model']['precision_at_budget'],top/5)
        self.assertAlmostEqual(result['methods']['model']['recall_estimate'],top/total)
        self.assertEqual(len(result['calibration']),3)

    def test_zero_violations_recall_is_undefined(self):
        p=population()
        result=evaluate(p,[review(r,0) for r in p if r['selected_for_review']])
        self.assertIsNone(result['methods']['model']['recall_estimate'])
        self.assertEqual(result['methods']['model']['precision_at_budget'],0)
        self.assertIsNone(result['calibration'][0]['observed_rate_95_interval_approx'])

if __name__=='__main__':unittest.main()
