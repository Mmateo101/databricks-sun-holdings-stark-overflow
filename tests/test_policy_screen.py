from datetime import date
from decimal import Decimal
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src' / 'models'))
from policy_screen import evaluate
RULES = {r['rule_id']: r for r in json.loads((ROOT/'config/policy-pilot.json').read_text())['rules']}


class PolicyScreenTests(unittest.TestCase):
    def row(self, **changes):
        return dict(employee_id=1, name_mismatches=0, multi_actor_check=False,
                    discount_complete=True, positive_applications=1,
                    positive_amount=Decimal('50.00'), business_date=date(2026, 8, 2), **changes)

    def test_exact_money(self):
        row=self.row()
        self.assertFalse(evaluate(RULES['dnp_amount'], row)['screen_exception'])
        row['positive_amount']=Decimal('50.000001')
        self.assertTrue(evaluate(RULES['dnp_amount'], row)['screen_exception'])

    def test_inclusive_dates(self):
        for day, failed in (('2026-03-01',True),('2026-03-02',False),('2027-02-28',False),('2027-03-01',True)):
            row=self.row(); row['business_date']=day
            self.assertEqual(evaluate(RULES['dnp_date'],row)['screen_exception'],failed)
        for day, failed in (('2026-08-02',False),('2026-08-03',True)):
            row=self.row(); row['business_date']=day
            self.assertEqual(evaluate(RULES['mdg_expiry'],row)['screen_exception'],failed)

    def test_missing_coverage_never_passes(self):
        for key, value in (('employee_id',None),('name_mismatches',1),('multi_actor_check',True),('discount_complete',False),('positive_applications',2)):
            row=self.row(); row[key]=value
            r=evaluate(RULES['dnp_amount'],row)
            self.assertEqual(r['screen_result'],'not_evaluable')
            self.assertIsNone(r['screen_exception'])
        self.assertEqual(evaluate(RULES['dnp_amount'],self.row())['policy_status'],'local_applicability_unconfirmed')


if __name__ == '__main__': unittest.main()
