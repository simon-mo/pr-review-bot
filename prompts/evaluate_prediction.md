# Evaluate Prediction Accuracy

You made a prediction for PR #{{PR_NUMBER}}. Now compare it to reality.

## Your Prediction

Read: `results/predictions/{{PR_NUMBER}}.json`

## What Actually Happened

NOW read the review data you were not allowed to see before:
- `{{PR_DIR}}/reviews.json` — reviewer verdicts
- `{{PR_DIR}}/review_comments.json` — inline code comments
- `{{PR_DIR}}/comments.json` — conversation thread
- `{{PR_DIR}}/meta.json` — final state (merged or not)

## Evaluate

For each aspect of your prediction:

1. **Outcome match**: Did you predict merged/rejected/revision correctly?
2. **Comment match**: For each predicted comment, was there a real comment
   about the same thing? Score each as: hit / partial / miss
3. **Missed issues**: What did real reviewers flag that you didn't predict?
4. **False alarms**: What did you predict that reviewers didn't care about?
5. **Triage match**: Was your triage category appropriate?
6. **Skill assessment**: For each skill that activated:
   - Did it help make a correct prediction?
   - Did it lead to a false positive?
   - Did it miss something it should have caught?

## Output

Write evaluation to: `results/evaluations/{{PR_NUMBER}}.json`

```json
{
  "pr_number": 0,
  "outcome_match": "correct|partial|wrong",
  "triage_match": "correct|partial|wrong",
  "comment_hits": 0,
  "comment_misses": 0,
  "false_alarms": 0,
  "missed_issues": ["description of each missed issue"],
  "false_alarm_details": ["description of each false alarm"],
  "skill_performance": {
    "skill_name": {
      "helped": true,
      "false_positives": 0,
      "missed": 0,
      "notes": "..."
    }
  },
  "overall_accuracy": 0.0,
  "key_insight": "The most important thing learned from this evaluation"
}
```

## Hypothesis

After writing the evaluation, think about WHY you were wrong (if you were).
Write a brief hypothesis at the end — this will feed into skill refinement.
Append it to the JSON as "hypothesis": "..."
