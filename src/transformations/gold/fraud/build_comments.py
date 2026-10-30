"""Writes fraud/fraud_comments.sql: table and column comments (English) for the four fraud gold tables.
python3 fraud/build_comments.py"""
from pathlib import Path

G = "applebees_semantic.gold"
OWN = "The employee who took the first payment of the check owns it (min_by(employee_id, payment_ordinal), 'GC Sold' excluded)."

EMPLOYEE = {
    "employee_id": "Employee who owns the checks (took the first payment). Join to silver.employees.",
    "location_id": "Restaurant of the checks. Join to silver.locations.",
    "sales": "Gross sales of the employee's checks before discounts (sum of check_items.gross_price).",
    "discount_amount": "Money discounted on the employee's checks (sum of discount_events.amount, item and check level).",
    "discount_ratio": "Indicator 1. discount_amount / sales. High = discounts a lot compared with what is sold.",
    "discounted_checks": "Checks with at least one discount.",
    "nondiscounted_checks": "Checks without any discount.",
    "card_discounted_checks": "Discounted checks with a card part billed above 0. Card = credit card or OLO-* tender.",
    "card_discounted_tips": "Card tips on the discounted card checks.",
    "card_discounted_bill": "Card bill before discount on the discounted card checks: card billed + the card share of the discount.",
    "card_nondiscounted_checks": "Checks without discount with a card part billed above 0.",
    "card_nondiscounted_tips": "Card tips on the card checks without discount.",
    "card_nondiscounted_bill": "Card bill on the card checks without discount.",
    "tip_ratio": "Indicator 3. (card_discounted_tips / card_discounted_bill) / (card_nondiscounted_tips / card_nondiscounted_bill). About 0.8 is normal; above 1 = discount money may be moving into the tip.",
    "cash_or_no_tip_discounted_checks": "Discounted checks paid only in cash or with a total tip of 0.",
    "cash_or_no_tip_nondiscounted_checks": "Checks without discount paid only in cash or with a total tip of 0.",
    "cash_ratio": "Indicator 2. (cash_or_no_tip_discounted_checks / discounted_checks) / (cash_or_no_tip_nondiscounted_checks / nondiscounted_checks). Above 1 = discounts go together with cash or no tip, where money leaves no trace.",
    "checks": "All checks owned by the employee (discounted_checks + nondiscounted_checks).",
    "discount_frequency": "Indicator 4. discounted_checks / checks. High = gives discounts often, even if each one is small.",
    "full_comp_checks": "Checks where the discount is equal to or larger than the sales (the whole check given away).",
    "full_comp_ratio": "Indicator 5. full_comp_checks / checks. High = gives whole checks away; with cash payment the money can be kept.",
    "discount_void_checks": "Discounted checks that also have at least one voided item.",
    "discount_void_ratio": "Indicator 6. discount_void_checks / checks. High = takes money off the same check twice (discount and void).",
    "card_discounted_no_tip_checks": "Discounted card checks with a card tip of 0.",
    "card_nondiscounted_no_tip_checks": "Card checks without discount with a card tip of 0.",
    "card_no_tip_ratio": "Indicator 7. (card_discounted_no_tip_checks / card_discounted_checks) / (card_nondiscounted_no_tip_checks / card_nondiscounted_checks). Above 1 = discounted card checks end without tip more often.",
    "void_items": "Voided items on the employee's checks.",
    "void_amount": "Money removed by voids on the employee's checks.",
    "voids_per_100_checks": "Indicator 8a. void_items x 100 / checks. High = voids many items.",
    "void_ratio": "Indicator 8b. void_amount / sales. High = voids remove a large share of sales.",
}
MANAGER = {
    "manager_id": "Manager who approved discounts or voids (manager_id on discount_events and silver.voids). ID 0 (not specified, automatic loyalty and gift card discounts) is left out. Join to silver.employees.",
    "location_id": "Restaurant where the manager approved. Join to silver.locations.",
    "approved_uses": "Discount applications the manager approved.",
    "approved_amount": "Money of the discounts the manager approved.",
    "approved_employees": "Distinct employees whose discounts the manager approved.",
    "store_sales": "Gross sales of the restaurant on the manager's active days (gold.location_day).",
    "store_checks": "Checks of the restaurant on the manager's active days.",
    "approval_ratio": "Indicator 1. approved_amount / store_sales. High = lets more be discounted than the store sales justify.",
    "self_approved_uses": "Discounts the manager applied and also approved (same ID in both roles).",
    "self_approval_ratio": "Indicator 2. self_approved_uses / approved_uses. Above 0 = no second person checked the discount.",
    "top_employee_uses": "Approvals that went to the employee this manager approved the most in the period.",
    "concentration_ratio": "Indicator 3. top_employee_uses / approved_uses. High = most approvals go to one person (possible collusion).",
    "approved_voids": "Voided items the manager approved.",
    "approved_void_amount": "Money removed by the voids the manager approved.",
    "approved_voids_per_100_checks": "Indicator 4. approved_voids x 100 / store_checks. High = approves many voids.",
    "store_approved_amount": "Money approved by all managers of the restaurant in the period (the peer group).",
    "store_managers": "Managers who approved discounts at the restaurant in the period.",
    "approval_vs_peers": "Indicator 5. approved_amount / (store_approved_amount / store_managers). 1 = average of the managers of the same store and period; well above 1 = approves more than peers.",
}

TABLES = {
    "fraud_employee_day": (f"One row per employee and business date. Fraud indicators per employee (8): discount_ratio, cash_ratio, tip_ratio (design by Mateo) and discount_frequency, full_comp_ratio, discount_void_ratio, card_no_tip_ratio, voids_per_100_checks / void_ratio, each with its numerator and denominator. {OWN} Built by fraud/fraud_employee_day.sql.",
                           {"business_date": "Business date.", **EMPLOYEE}),
    "fraud_employee_week": ("One row per employee and week (Thursday to Wednesday). Sums of fraud_employee_day; every ratio recomputed from the weekly numerators and denominators. location_id = restaurant with the most sales that week. Built by fraud/fraud_employee_week.sql.",
                            {"week_start": "Thursday that starts the week (weeks run Thursday to Wednesday).",
                             "days_worked": "Business days with checks owned by the employee in the week.", **EMPLOYEE}),
    "fraud_manager_day": ("One row per manager, restaurant and business date with at least one approved discount or void. Fraud indicators per manager (5): approval_ratio, self_approval_ratio, concentration_ratio, approved_voids_per_100_checks, approval_vs_peers, each with its numerator and denominator. Built by fraud/fraud_manager_day.sql.",
                          {"business_date": "Business date.", **MANAGER}),
    "fraud_manager_week": ("One row per manager, restaurant and week (Thursday to Wednesday, same weeks as fraud_employee_week). Additive columns are sums of fraud_manager_day; approved_employees, top_employee_uses and the peer group are recomputed from the week's events; ratios are recomputed from weekly sums. Built by fraud/fraud_manager_week.sql.",
                           {"week_start": "Thursday that starts the week (weeks run Thursday to Wednesday).",
                            "days_active": "Business days with at least one approval in the week.", **MANAGER}),
}


def q(s):
    return "'" + s.replace("'", "''") + "'"


lines = ["-- Generated by fraud/build_comments.py. Run after the four fraud_*.sql builds.", ""]
for t, (comment, cols) in TABLES.items():
    lines.append(f"COMMENT ON TABLE {G}.{t} IS {q(comment)};")
    lines += [f"ALTER TABLE {G}.{t} ALTER COLUMN {c} COMMENT {q(v)};" for c, v in cols.items()]
    lines.append("")
Path(__file__).with_name("fraud_comments.sql").write_text("\n".join(lines))
print(f"wrote {sum(len(c) for _, c in TABLES.values())} column comments")
