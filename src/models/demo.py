"""Synthetic observations have declared categories, with no fitted real-data bins."""

from inference import filter_sequence


def run_demo(parameters):
    evidence = [
        ("2026-05-07", "ordinary", "ordinary"),
        ("2026-05-14", "frequent_and_intense", "elevated_contrast"),
        ("2026-05-21", "frequent_and_intense", None),
        ("2026-06-04", "ordinary", "ordinary"),
        ("2026-06-11", None, None),
    ]
    return filter_sequence([
        {"data_kind": "synthetic", "employee_id": "SYNTHETIC-001", "location_id": "SYNTHETIC-STORE",
         "week_start": week, "activity_state": activity, "tip_state": tip}
        for week, activity, tip in evidence
    ], parameters)
