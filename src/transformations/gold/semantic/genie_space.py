"""Genie space definition for the Applebee's fraud challenge (semantic layer in catalog applebees_semantic).

python src/transformations/gold/semantic/genie_space.py validate   -> runs every example and benchmark SQL on the warehouse
python src/transformations/gold/semantic/genie_space.py json       -> writes serialized_space.json next to this file (payload for create-space)
"""
import os
import json
import sys
import uuid
from pathlib import Path

C = os.environ.get("DATABRICKS_CATALOG", "applebees_semantic")
TITLE = "Applebee's Discount & Fraud Analyst"
DESCRIPTION = ("Ask about discounts, tips and voids across Sun Holdings Applebee's restaurants: "
               "discount rates, codes, employees, managers and outliers.")

METRIC_VIEWS = [
    f"{C}.semantic.mv_sales_discounts",
    f"{C}.semantic.mv_discount_usage",
    f"{C}.semantic.mv_card_tips",
    f"{C}.semantic.mv_voids",
    f"{C}.semantic.mv_fraud_employee",
    f"{C}.semantic.mv_fraud_manager",
]
TABLES = [
    f"{C}.semantic.kpi_employee",
    f"{C}.semantic.kpi_manager",
    f"{C}.semantic.kpi_location",
    f"{C}.semantic.dim_discount",
    f"{C}.semantic.dim_location",
    f"{C}.reference.official_offers",
    f"{C}.reference.promotion_calendar",
    f"{C}.gold.fraud_employee_week",
    f"{C}.gold.fraud_manager_week",
]

INSTRUCTIONS = """\
Context: Sun Holdings runs Applebee's restaurants; the data covers one study period of POS checks. The goal of this space is to find suspicious discount, tip and void patterns. Amounts are in USD (assumed; the client has not confirmed the currency).

Which object to use:
- Discount rate, gross sales, discounted check frequency, average discount, checks, guests, by store, date, week, weekday, channel or daypart: mv_sales_discounts.
- Which discount codes, who applied or approved discounts, self-approvals, discounts without a manager: mv_discount_usage.
- Tips: mv_card_tips (card payments only; cash tips are not recorded).
- Voids: mv_voids.
- Ranking or watchlist of employees, managers or stores, outliers, money at stake: kpi_employee, kpi_manager, kpi_location.
- Meaning of a discount code, whether its meaning is confirmed, documented restrictions: dim_discount. Official offers and promotions: official_offers, promotion_calendar.

Rules:
- Query metric views with MEASURE(): SELECT dimension, MEASURE(measure) FROM view GROUP BY ALL. Never recompute a ratio by averaging other ratios; always use the ratio measures (discount_rate, discounted_check_frequency, tip_rate).
- The discount rate is discount amount / gross sales. Report rates as percentages with two decimals.
- A check is identified by location_id + business_date + check_id; check_id alone repeats.
- Employee and manager ID 0 means "not specified"; exclude it from rankings of people.
- Outliers follow the EDA rule: rate above Q3 + 1.5 x IQR among eligible people (employees with at least 50 checks and 2,000 in sales; managers with at least 50 approvals). Use the is_outlier column; do not invent another threshold unless asked.
- Being an outlier or having a quality flag is a risk signal, never proof of fraud. Say so when listing people.
- Show employee or manager names only when the question asks about specific people; otherwise aggregate.
- Some discount codes have no public definition (research_confidence = 'Not found online'). When explaining a code, state the confidence of its meaning.
- Business dates are restaurant days; use business_date for every date filter. Weekend means Friday to Sunday.
- Answer in the language of the question (Spanish or English).

Fraud indicators (team definitions, 2026-10-29):
- Employee indicators (8): discount_ratio, cash_ratio, tip_ratio, discount_frequency, full_comp_ratio, discount_void_ratio, card_no_tip_ratio, voids_per_100_checks / void_ratio. Each check belongs to the employee who took its first payment. Use mv_fraud_employee for any period or breakdown, and fraud_employee_week for exact weekly values per employee.
- Manager indicators (5): approval_ratio, self_approval_ratio, concentration_ratio, approved_voids_per_100_checks, approval_vs_peers. Use mv_fraud_manager grouped by manager, and fraud_manager_week for exact weekly values. Never sum store_sales across managers.
- Fraud weeks run Thursday to Wednesday (fraud_week_start / week_start in the fraud tables). The first and last fraud weeks are partial (is_partial_fraud_week).
- For ratios that compare discounted with non-discounted checks (cash_ratio, tip_ratio, card_no_tip_ratio), 1 means no difference. Above the normal value is suspicious.
- When ranking employee-weeks, require at least 5 discounted checks (discounted_checks >= 5) so one check does not decide the value.
- "Tip ratio" / "card tip ratio" / "tip_ratio" always means the fraud indicator tip_ratio from mv_fraud_employee (or fraud_employee_week): card tip % on discounted checks divided by card tip % on checks without discount. It is NOT the tip rate (tips / amount billed), which comes from mv_card_tips and is asked as "tip rate" or "tip percentage".
- Fraud indicator ratios (discount_ratio, full_comp_ratio, discount_frequency, discount_void_ratio, void_ratio, approval_ratio, self_approval_ratio, concentration_ratio) are returned as fractions from the MEASURE; do not multiply them by 100 in SQL, format them as percentages in the answer instead.
"""

# (question, sql) pairs: examples Genie learns from. Every SQL is validated against the data.
EXAMPLES = [
    ("What is the overall discount rate?",
     f"SELECT MEASURE(discount_rate) AS discount_rate, MEASURE(gross_sales) AS gross_sales, MEASURE(discount_amount) AS discount_amount\nFROM {C}.semantic.mv_sales_discounts"),
    ("Which 10 restaurants have the highest discount rate?",
     f"SELECT location_name, MEASURE(discount_rate) AS discount_rate, MEASURE(gross_sales) AS gross_sales\nFROM {C}.semantic.mv_sales_discounts\nGROUP BY ALL\nORDER BY discount_rate DESC\nLIMIT 10"),
    ("How does the discount rate change by week?",
     f"SELECT week_start, MEASURE(discount_rate) AS discount_rate, MEASURE(check_count) AS checks\nFROM {C}.semantic.mv_sales_discounts\nGROUP BY ALL\nORDER BY week_start"),
    ("Discount rate by channel group and daypart",
     f"SELECT channel_group, daypart, MEASURE(discount_rate) AS discount_rate, MEASURE(discounted_check_frequency) AS discounted_check_frequency\nFROM {C}.semantic.mv_sales_discounts\nGROUP BY ALL\nORDER BY channel_group, daypart"),
    ("Top 10 discount codes by amount, with their meaning",
     f"SELECT u.discount_name, u.research_confidence, u.uses, u.discount_amount, d.web_meaning\nFROM (SELECT discount_id, discount_name, research_confidence, MEASURE(discount_uses) AS uses, MEASURE(discount_amount) AS discount_amount\n      FROM {C}.semantic.mv_discount_usage GROUP BY ALL) u\nJOIN {C}.semantic.dim_discount d USING (discount_id)\nORDER BY u.discount_amount DESC\nLIMIT 10"),
    ("Which employees are discount outliers and how much money is at stake?",
     f"SELECT employee_name, location_name, checks, gross_sales, discount_rate, peer_median_rate, discount_uses_per_100_checks, excess_discount_vs_median\nFROM {C}.semantic.kpi_employee\nWHERE is_outlier\nORDER BY excess_discount_vs_median DESC"),
    ("Compare outlier employees with the rest",
     f"SELECT is_outlier, count(*) AS employees, avg(discount_rate) AS avg_discount_rate, avg(discount_uses_per_100_checks) AS discount_uses_per_100_checks,\n  avg(active_weeks) AS avg_active_weeks, sum(card_tips) / sum(card_billed) AS card_tip_rate\nFROM {C}.semantic.kpi_employee\nWHERE is_kpi_eligible\nGROUP BY is_outlier"),
    ("Which managers approve the most discounts relative to their store sales?",
     f"SELECT manager_name, location_name, approvals, employees_approved, approved_amount, approved_discount_rate, self_approved_uses, is_outlier\nFROM {C}.semantic.kpi_manager\nWHERE is_kpi_eligible\nORDER BY approved_discount_rate DESC\nLIMIT 20"),
    ("Which stores have the most discounts without an approving manager?",
     f"SELECT location_name, MEASURE(unapproved_uses) AS uses_without_manager, MEASURE(discount_uses) AS discount_uses,\n  MEASURE(unapproved_uses) / MEASURE(discount_uses) AS share_without_manager\nFROM {C}.semantic.mv_discount_usage\nGROUP BY ALL\nORDER BY uses_without_manager DESC\nLIMIT 10"),
    ("What is the card tip rate by restaurant?",
     f"SELECT location_name, MEASURE(tip_rate) AS tip_rate, MEASURE(tip_amount) AS tips, MEASURE(card_payments) AS card_payments\nFROM {C}.semantic.mv_card_tips\nGROUP BY ALL\nORDER BY tip_rate DESC"),
    ("Top void reasons and amount",
     f"SELECT void_category, MEASURE(void_count) AS voids, MEASURE(void_amount) AS void_amount\nFROM {C}.semantic.mv_voids\nGROUP BY ALL\nORDER BY voids DESC"),
    ("Which discount codes have no confirmed meaning?",
     f"SELECT discount_name, discount_level, research_status, program_scope\nFROM {C}.semantic.dim_discount\nWHERE research_confidence = 'Not found online'\nORDER BY discount_name"),
]

EXAMPLES += [
    ("Which employees have the highest card tip ratio in a week, with enough discounted card checks?",
     f"SELECT w.week_start, e.employee_name, l.location_name, w.tip_ratio, w.card_discounted_checks, w.discount_ratio\nFROM {C}.gold.fraud_employee_week w\nJOIN {C}.semantic.dim_employee e USING (employee_id)\nJOIN {C}.semantic.dim_location l ON l.location_id = w.location_id\nWHERE w.card_discounted_checks >= 5\nORDER BY w.tip_ratio DESC\nLIMIT 20"),
    ("Employee fraud indicators by fraud week",
     f"SELECT fraud_week_start, MEASURE(discount_ratio) AS discount_ratio, MEASURE(cash_ratio) AS cash_ratio, MEASURE(tip_ratio) AS tip_ratio,\n  MEASURE(full_comp_ratio) AS full_comp_ratio, MEASURE(voids_per_100_checks) AS voids_per_100_checks\nFROM {C}.semantic.mv_fraud_employee\nGROUP BY ALL\nORDER BY fraud_week_start"),
    ("Which employees give away the most whole checks?",
     f"SELECT employee_name, location_name, MEASURE(full_comp_checks) AS full_comp_checks, MEASURE(full_comp_ratio) AS full_comp_ratio, MEASURE(checks) AS checks\nFROM {C}.semantic.mv_fraud_employee\nGROUP BY ALL\nHAVING MEASURE(checks) >= 50\nORDER BY full_comp_ratio DESC\nLIMIT 20"),
    ("Which managers approve their own discounts?",
     f"SELECT manager_name, location_name, MEASURE(self_approved_uses) AS self_approvals, MEASURE(approved_uses) AS approvals, MEASURE(self_approval_ratio) AS self_approval_ratio\nFROM {C}.semantic.mv_fraud_manager\nGROUP BY ALL\nHAVING MEASURE(self_approved_uses) > 0\nORDER BY self_approvals DESC"),
    ("Which managers approve much more than the other managers of their store?",
     f"SELECT manager_name, location_name, MEASURE(approval_vs_peers) AS approval_vs_peers, MEASURE(approval_ratio) AS approval_ratio, MEASURE(approved_uses) AS approvals\nFROM {C}.semantic.mv_fraud_manager\nGROUP BY ALL\nHAVING MEASURE(approved_uses) >= 50\nORDER BY approval_vs_peers DESC\nLIMIT 20"),
    ("Managers whose approvals concentrate on one employee in a week",
     f"SELECT w.week_start, e.employee_name AS manager_name, l.location_name, w.concentration_ratio, w.top_employee_uses, w.approved_uses\nFROM {C}.gold.fraud_manager_week w\nJOIN {C}.semantic.dim_employee e ON e.employee_id = w.manager_id\nJOIN {C}.semantic.dim_location l ON l.location_id = w.location_id\nWHERE w.approved_uses >= 20\nORDER BY w.concentration_ratio DESC\nLIMIT 20"),
]

SAMPLE_QUESTIONS = [
    "¿Cuál es la tasa de descuento general y por sucursal?",
    "¿Qué empleados son atípicos en descuentos y cuánto dinero está en juego?",
    "¿Qué códigos de descuento se usan más y qué significan?",
    "¿Qué gerentes aprueban más descuentos respecto a las ventas de su tienda?",
    "¿Los empleados atípicos reciben más propina?",
    "Which stores have the most discounts without an approving manager?",
    "¿Qué empleados tienen el tip ratio más alto en una semana?",
    "¿Qué gerentes se autoaprueban descuentos?",
]

# Benchmarks: question + reference SQL; expected values come from validate (EDA cross-check in comments).
BENCHMARKS = [
    ("What is the overall discount rate?", EXAMPLES[0][1]),
    ("How many employees are discount outliers?",
     f"SELECT count(*) AS outlier_employees FROM {C}.semantic.kpi_employee WHERE is_outlier"),
    ("How many managers are discount outliers?",
     f"SELECT count(*) AS outlier_managers FROM {C}.semantic.kpi_manager WHERE is_outlier"),
    ("Which stores are discount outliers?",
     f"SELECT location_name, discount_rate FROM {C}.semantic.kpi_location WHERE is_outlier ORDER BY discount_rate DESC"),
    ("Which discount code has the largest discount amount?",
     f"SELECT discount_name, MEASURE(discount_amount) AS discount_amount FROM {C}.semantic.mv_discount_usage GROUP BY ALL ORDER BY discount_amount DESC LIMIT 1"),
    ("What share of checks has a discount?",
     f"SELECT MEASURE(discounted_check_frequency) AS discounted_check_frequency FROM {C}.semantic.mv_sales_discounts"),
    ("What is the overall card tip rate?",
     f"SELECT MEASURE(tip_rate) AS tip_rate FROM {C}.semantic.mv_card_tips"),
    ("How much money do outlier employees discount above the median rate?",
     f"SELECT sum(excess_discount_vs_median) AS money_at_stake FROM {C}.semantic.kpi_employee WHERE is_outlier"),
    ("What is the discount rate of dine-in checks?",
     f"SELECT MEASURE(discount_rate) AS discount_rate FROM {C}.semantic.mv_sales_discounts WHERE channel_group = 'Dine-in'"),
    ("How many discounts were approved by the same person who applied them?",
     f"SELECT MEASURE(self_approved_uses) AS self_approved_uses FROM {C}.semantic.mv_discount_usage"),
    ("What is the overall employee card tip ratio?",
     f"SELECT MEASURE(tip_ratio) AS tip_ratio FROM {C}.semantic.mv_fraud_employee"),
    ("What share of checks is given away completely?",
     f"SELECT MEASURE(full_comp_ratio) AS full_comp_ratio FROM {C}.semantic.mv_fraud_employee"),
    ("How many managers approved discounts or voids?",
     f"SELECT MEASURE(managers) AS managers FROM {C}.semantic.mv_fraud_manager"),
    ("How many fraud weeks are there?",
     f"SELECT count(DISTINCT week_start) AS fraud_weeks FROM {C}.gold.fraud_employee_week"),
]


def _id():
    return uuid.uuid4().hex


def serialized_space():
    space = {
        "version": 1,
        "config": {"sample_questions": [{"id": _id(), "question": [q]} for q in SAMPLE_QUESTIONS]},
        "data_sources": {
            "tables": [{"identifier": t} for t in sorted(TABLES)],
            "metric_views": [{"identifier": m} for m in sorted(METRIC_VIEWS)],
        },
        "instructions": {
            "text_instructions": [{"id": _id(), "content": [INSTRUCTIONS]}],
            "example_question_sqls": [{"id": _id(), "question": [q], "sql": [s]} for q, s in EXAMPLES],
        },
        "benchmarks": {"questions": [
            {"id": _id(), "question": [q], "answer": [{"format": "SQL", "content": [s]}]} for q, s in BENCHMARKS]},
    }
    for section in (space["config"]["sample_questions"], space["instructions"]["text_instructions"],
                    space["instructions"]["example_question_sqls"], space["benchmarks"]["questions"]):
        section.sort(key=lambda x: x["id"])
    return space


if __name__ == "__main__":
    if sys.argv[1:] == ["validate"]:
        sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
        from run_sql import execute
        for kind, items in (("example", EXAMPLES), ("benchmark", BENCHMARKS)):
            for q, s in items:
                rows = execute(s)
                print(f"OK {kind}: {q} -> {len(rows)} rows; first: {rows[0] if rows else None}")
    elif sys.argv[1:] == ["json"]:
        out = Path(__file__).with_name("serialized_space.json")
        out.write_text(json.dumps(serialized_space(), indent=1, ensure_ascii=False))
        print(f"wrote {out}")
