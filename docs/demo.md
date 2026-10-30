# Three-minute judge walkthrough

1. Open `dashboards/model-demo.html` from the downloaded repository. The visible notice identifies every employee and observation as invented. No Databricks credentials are needed; displaying charts requires access to the pinned D3 CDN.
2. On **Population**, inspect 30 invented employees and the 29 with post-training informed estimates. Change restaurant. The training-only employee has no assigned event probability.
3. On **Employee timeline**, choose employee 3. Its temporary count spike raises the reference estimate; later ordinary counts reduce it. The shaded area shows disagreement among declared assumptions, not a credible interval. Choose employee 2 to compare persistent higher activity.
4. On **Global model checks**, inspect coverage and synthetic later-week count prediction. Change memory to zero or reverse the activity-odds hypothesis. The mean trajectory and transition values respond to the selected precomputed scenario. Precision/recall and calibration remain unmeasured because no verified outcomes are invented.
5. Open the model card and review protocol. Explain how source evidence and independent policy review will establish review yield and probability quality. For authorized private execution, show the Databricks Job DAG and the read-only employee-history notebook using the deployment's configured paths.

Rebuild with `python examples/run_demo.py`; test with `python -m unittest discover -s tests -v`. The initial small discrete network in `src/models/demo.py` is a separate synthetic arithmetic example. The displayed dashboard uses the current beta-binomial temporal model.
