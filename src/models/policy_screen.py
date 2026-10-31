"""Numerical candidate screens, deliberately separate from confirmed violations."""
from datetime import date
from decimal import Decimal


def evaluate(rule, row):
    result = {"screen_result": "not_evaluable", "screen_exception": None,
              "screen_reason": "", "policy_status": "local_applicability_unconfirmed"}
    if not row.get("employee_id"):
        reason = "unknown_discount_actor"
    elif row["name_mismatches"]:
        reason = "code_name_mismatch"
    elif row["multi_actor_check"]:
        reason = "multiple_actors_on_check"
    elif not row["discount_complete"]:
        reason = "incomplete_discount_amounts"
    elif rule["kind"] == "amount" and row["positive_applications"] != 1:
        reason = "multiple_applications_redemption_grain_unresolved"
    else:
        day = row["business_date"]
        if isinstance(day, str):
            day = date.fromisoformat(day)
        if rule["kind"] == "amount":
            value = Decimal(str(row["positive_amount"]))
            if not value.is_finite() or value <= 0:
                raise ValueError("Positive finite decimal amount required")
            failed = value > Decimal(rule["maximum"])
        elif rule["kind"] == "date_window":
            failed = not date.fromisoformat(rule["start"]) <= day <= date.fromisoformat(rule["end"])
        elif rule["kind"] == "expiry":
            failed = day > date.fromisoformat(rule["end"])
        else:
            raise ValueError("Unknown policy screen kind")
        result.update(screen_result="candidate_exception" if failed else "screen_pass",
                      screen_exception=failed,
                      screen_reason="numerical_screen_only_not_confirmed_policy")
        return result
    result["screen_reason"] = reason
    return result
