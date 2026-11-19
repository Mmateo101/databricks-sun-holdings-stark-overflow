from datetime import date,timedelta
import json
from pathlib import Path
import sys
import unittest
import numpy as np
import pandas as pd
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src'/'models'))
import time_series as ts

CONFIG=json.loads((ROOT/'src/models/time_series.json').read_text())
RATES={'discount_frequency':.13,'full_comp':.03,'discount_void':.01,'voids':.05}


def synthetic(seed=1,employees=60,checks=70,change=None):
    """Invented stores and employees; change=(employee, first week, indicator, extra share)."""
    rng=np.random.default_rng(seed);rows=[]
    weeks=[date(2026,4,23)+timedelta(days=7*i) for i in range(18)]
    for e in range(employees):
        theta=rng.gamma(8,1/8)
        for w,week in enumerate(weeks):
            n=int(rng.poisson(checks));row=dict(employee_id=e+1,location_id=e%4,week_start=week,n=float(n))
            for i,r in RATES.items():
                rate=r*theta+(change[3] if change and change[0]==e+1 and w>=change[1] and change[2]==i else 0)
                row['k_'+i]=float(rng.poisson(n*rate) if i=='voids' else rng.binomial(n,min(rate,.9)))
                row['e_'+i]=n*r
            rows.append(row)
    return pd.DataFrame(rows)


class TimeSeriesTests(unittest.TestCase):
    def test_partial_weeks_and_adaptive_periods(self):
        f=synthetic()
        f.loc[f.employee_id==1,'n']=10.0
        groups,usable,partial,_=ts.prepare(f,CONFIG)
        self.assertEqual(len(usable),16)
        self.assertEqual(partial,[date(2026,4,23),date(2026,8,20)])
        self.assertIn(1,groups[4]['emps'])
        self.assertEqual(groups[1]['T'],16);self.assertEqual(groups[4]['T'],4)

    def test_alarm_rate_respects_target(self):
        long,short,facts=ts.run(synthetic(),CONFIG)
        self.assertLessEqual(facts['rising_rate'],CONFIG['target_rising_rate']+1e-9)
        self.assertEqual(set(long.indicator),set(CONFIG['indicators']))
        self.assertTrue(set(short.status)<={'rising','falling','spike','stable','insufficient_history','partial_week'})
        self.assertTrue((short[short.status=='partial_week'].week_start.isin([date(2026,4,23),date(2026,8,20)])).all())

    def test_sustained_increase_is_detected(self):
        long,short,_=ts.run(synthetic(change=(7,9,'discount_void',.06)),CONFIG)
        later=short[(short.employee_id==7)&(short.week_start>=date(2026,6,25))]
        self.assertIn('rising',set(later.status))
        self.assertIn('discount_void',set(later[later.status=='rising'].top_driver))

    def test_store_wide_change_is_not_the_employee(self):
        f=synthetic(seed=3)
        late=f.week_start>=date(2026,7,2)
        f.loc[late,'k_full_comp']+=np.ceil(.05*f.loc[late,'n']);f.loc[late,'e_full_comp']+=.05*f.loc[late,'n']
        _,short,_=ts.run(f,CONFIG)
        after=short[(short.week_start>=date(2026,7,2))&(short.status!='partial_week')]
        self.assertLess((after[after.status=='rising'].top_driver=='full_comp').mean() if (after.status=='rising').any() else 0,.5)


if __name__=='__main__':unittest.main()
