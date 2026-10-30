# Independent review and effectiveness

The objective is more verified policy-violating employee-weeks per review. An old risk coefficient or model score is a comparator, not a label. Training against it would train agreement with that algorithm, not establish verified violation detection.

## Prepare and inspect

After one model run completes, configure `review_model_run_id` and run the `review_pilot` Job. It prepares the most recent informed week, or an explicitly chosen Thursday week. It takes both frozen top-20 lists (model score and positive-discount-check rate), then samples ten additional cases without replacement from each of three remaining score-rank bands. Overlapping top lists are reviewed once. Each cohort member has a known nonzero inclusion probability; certainty cases have probability 1.

Open `notebooks/review_cases.py` in the deployed bundle. Set `repo_root`, `catalog`, `model_schema`, `expected_owner`, `model_run_id` and `review_batch_id` to the deployment's values. Keep `action=inspect`; select a `case_id` to see its saved positive-discount applications. Scores/ranks are hidden in that display, although analysts with table access can still see them.

Managers or teammates who can confirm the policies effective for that location/date and inspect required approval/eligibility evidence perform the review. Use the interactive notebook to record the actual submitting workspace identity. An owner-run Job would record its executing identity. External reviewers can be documented in evidence references/notes; no external account is created automatically.

## Record outcomes

Use `submit_review` and supply an outcome, policy and evidence references, notes, and number of positive checks inspected:

- `violation`: at least one inspected positive-discount check violated a confirmed applicable policy. Enter its check ID and business date from the packet. Intent is not required.
- `no_violation`: all positive actor checks in the recorded week were reviewed and all applicable policy/approval/eligibility conditions were confirmed. One clean transaction is insufficient.
- `insufficient_evidence`: policy applicability, approvals or other necessary evidence remains unavailable. Do not relabel uncertainty as compliance.

Submissions append audit records and use idempotent identifiers. Conflicting decisive outcomes are marked disputed and excluded pending a separately documented adjudication; this release does not implement an adjudication override. A recorded manager ID is not proof of authorization. Candidate-policy numeric screens do not constitute confirmed outcomes.

The model/review owner needs its configured output-schema privileges. Reviewers need USE CATALOG, USE SCHEMA and SELECT for that model schema, plus MODIFY on only `review_pilot_outcomes` and `review_pilot_evaluations` when saving results. Obtain these from the workspace owner; this repository does not grant privileges automatically. MODIFY also permits direct SQL changes/deletes, so evidence governance still matters despite the notebook's append-only behavior.

## Calculate

Choose `action=evaluate`:

- Precision@20 is verified violating weeks among the corresponding frozen top 20 divided by 20. It remains unavailable until all 20 have decisive outcomes. Before that, report completion and lower/upper identification bounds, not a confidence interval.
- Estimate the eligible cohort's total violating weeks with `sum(y_i/pi_i)`, where `pi_i` is the saved inclusion probability. Recall estimates divide each method's exact verified top-20 positives by that estimated total. Recall is undefined if no positives are estimated.
- Compare mean predicted probability with sampling-weighted observed frequency in three frozen score-rank bands. Also calculate weighted Brier score and log loss. These scores combine aspects of calibration and discrimination; neither alone establishes calibration.

Population recall and probability-quality estimates wait until every planned sampled case is resolved and nonconflicting. This prevents silently treating nonresponse as negative or discarding it. Sampling variance includes the finite-population correction; recall uses a delta approximation. Small-pilot normal intervals are approximate and are withheld for one-class non-census strata, where zero plug-in variance would understate uncertainty.

Measures describe the frozen eligible cohort and review budget. Incomplete/prior-only observations are outside that cohort. Review effort varies with the number of transactions; interpret yield alongside checks inspected. A future calibrator must be evaluated on separate later reviewed weeks, not the same outcomes used to fit it.

References: [scikit-learn calibration](https://scikit-learn.org/stable/modules/calibration.html), [stratified sampling](https://online.stat.psu.edu/stat506/Lesson06).
