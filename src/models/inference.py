"""Small discrete Bayesian network and weekly filter; no fitted parameters."""

from datetime import date
import math


def probability(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("A probability must be numeric")
    if not math.isfinite(value) or not 0 <= value <= 1:
        raise ValueError("A probability must be finite and between zero and one")
    return value


def validate_parameters(parameters):
    if parameters.get("status") != "synthetic_only":
        raise ValueError("This development engine requires explicit synthetic parameters")
    for key in ("initial_probability", "persistence", "onset"):
        probability(parameters[key])
    states = parameters["activity_states"]
    tips = parameters["tip_states"]
    if not states or len(set(states)) != len(states) or not tips or len(set(tips)) != len(tips):
        raise ValueError("State names must be nonempty and unique")
    for hidden in ("0", "1"):
        distributions = [parameters["activity_given_event"][hidden]]
        distributions.extend(parameters["tip_given_activity_event"][hidden][s] for s in states)
        for index, distribution in enumerate(distributions):
            expected = states if index == 0 else tips
            if set(distribution) != set(expected):
                raise ValueError("Conditional probability table has inconsistent states")
            # Positive cells avoid impossible-evidence and infinite-ratio demo outputs.
            if any(probability(p) == 0 for p in distribution.values()):
                raise ValueError("Demonstration CPD cells must be strictly positive")
            if not math.isclose(math.fsum(distribution.values()), 1, abs_tol=1e-12, rel_tol=0):
                raise ValueError("Each conditional probability distribution must sum to one")


def log_likelihood_ratio(activity, tip, parameters):
    """P(D,T|F)=P(D|F)P(T|D,F); marginalize any unobserved node."""
    if activity is not None and activity not in parameters["activity_states"]:
        raise ValueError("Unknown joint activity state")
    if tip is not None and tip not in parameters["tip_states"]:
        raise ValueError("Unknown tip state")
    likelihoods = []
    for hidden in ("0", "1"):
        likelihoods.append(math.fsum(
            parameters["activity_given_event"][hidden][d]
            * (1 if tip is None else parameters["tip_given_activity_event"][hidden][d][tip])
            for d in parameters["activity_states"] if activity is None or activity == d
        ))
    return math.log(likelihoods[1]) - math.log(likelihoods[0])


def predict(previous, persistence, onset, elapsed_weeks=1):
    """Advance a fixed two-state transition model over unobserved calendar weeks."""
    for value in (previous, persistence, onset):
        probability(value)
    if isinstance(elapsed_weeks, bool) or not isinstance(elapsed_weeks, int) or elapsed_weeks < 1:
        raise ValueError("Elapsed weeks must be a positive integer")
    denominator = 1 - persistence + onset
    if denominator == 0:
        return previous
    stationary = onset / denominator
    value = stationary + (previous - stationary) * (persistence - onset) ** elapsed_weeks
    return min(1.0, max(0.0, value))


def update(prior, log_lr):
    probability(prior)
    if not math.isfinite(log_lr):
        raise ValueError("Evidence log likelihood ratio must be finite")
    if prior in (0, 1):
        return prior
    odds = math.log(prior) - math.log1p(-prior) + log_lr
    if odds >= 0:
        return 1 / (1 + math.exp(-odds))
    value = math.exp(odds)
    return value / (1 + value)


def filter_sequence(observations, parameters):
    """Filter one synthetic employee/location sequence; never scores real employees."""
    validate_parameters(parameters)
    records = sorted(observations, key=lambda row: row["week_start"])
    result, previous_week, posterior = [], None, None
    identity = None
    for row in records:
        if row.get("data_kind") != "synthetic":
            raise ValueError("Synthetic parameters must not score real employee records")
        current_identity = (row["employee_id"], row["location_id"])
        if identity is not None and identity != current_identity:
            raise ValueError("Filter one employee/location sequence at a time")
        identity = current_identity
        week = date.fromisoformat(row["week_start"])
        if week.weekday() != 3:
            raise ValueError("Fraud weeks must begin on Thursday")
        elapsed = None if previous_week is None else (week - previous_week).days // 7
        if elapsed is not None and elapsed < 1:
            raise ValueError("Duplicate employee/location/week")
        prior = parameters["initial_probability"] if posterior is None else predict(
            posterior, parameters["persistence"], parameters["onset"], elapsed
        )
        lr = log_likelihood_ratio(row.get("activity_state"), row.get("tip_state"), parameters)
        posterior = update(prior, lr)
        result.append({
            **row, "model_version": parameters["model_version"],
            "parameter_status": "synthetic_only", "scoring_status": "scenario_only",
            "elapsed_weeks": elapsed, "predicted_prior": prior,
            "log_likelihood_ratio": lr, "posterior_probability": posterior,
        })
        previous_week = week
    return result
