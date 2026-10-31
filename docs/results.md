# Results and scope of verification

## Executed development workflow

The earlier authorized development run processed 3,174 observed employee histories and 34,342 actor-location-weeks. It saved every scenario/prior and explicit training, prior-only and informed statuses across 108 settings. Source reconciliation, numerical oracles, repeatability and controlled failure/recovery checks were performed in that workspace.

Later-week discount-count prediction used 22,914 eligible observations:

| Frozen background count model | Mean log predictive score; higher is better |
| --- | ---: |
| Beta-binomial | −2.5959600194 |
| Binomial | −2.8676496076 |

This comparison supports the beta-binomial count distribution on that eligible later-week population. It is not a test of actual policy violations. No statistical significance, causal benefit or financial-savings result is inferred from it.

The review setup covered one eligible week: 1,840 informed employee-location-weeks, 66 selected cases across 48 restaurants and 927 positive-discount-check evidence records. It had **zero independently reviewed outcomes** at setup. Actual violation precision, recall and calibration are therefore unavailable. The old risk coefficient was not located and was not used as ground truth.

## Public submission

The public package preserves the numerical model and adapts its workspace wrappers to configurable identities, namespaces and run identifiers. Its local synthetic generation and numerical/review/ownership tests can be rerun without private data. The bundle schema is validated separately. The demo uses 30 invented employees, three invented restaurants and 108 scenario settings; its displayed count scores describe that invented dataset only.

`python tests/verify_submission.py` checks the public file inventory, configuration portability, Python syntax, documentation links, templates and synthetic data boundary. GitHub Actions runs the tests, rebuilds the demo and runs that verifier. The verification summary is generated under ignored `evidence/`, not committed with personal execution metadata.

The portable Gold/actor/scoring/review wrappers have not been redeployed against private production data as part of preparing this submission. A schema-valid bundle does not establish execution privileges, retention, source correctness or successful live execution. No source data, private run logs, access links or reviewed outcomes accompany this repository.

See [model card](model-card.md) for assumptions and [review protocol](review-protocol.md) for the empirical evaluation plan.
