# Refine Skills Based on Training Batch

You just completed a training batch. Now refine the skills.

## Evaluation Data

Read all evaluation files in `results/evaluations/` from this batch:
{{EVAL_FILES}}

## Current Skills

Read all files in `skills/`.

## Your Task

1. **Aggregate results**: What's the overall accuracy? Which skills
   performed well? Which performed poorly?

2. **Update each skill** that was activated in this batch:
   - Add new patterns discovered from the evaluations
   - Remove or demote patterns that led to false alarms
   - Update accuracy numbers
   - Add evidence PR numbers

3. **Create new skills** if evaluations reveal patterns not covered
   by existing skills. Follow the skill format in skills/.

4. **Consider structural changes**:
   - Split skills that are too broad (low accuracy, diverse miss patterns)
   - Merge skills that always activate together
   - Archive skills consistently below 40% accuracy

5. **Update the changelog**: Append to `results/skill_changelog.md`
   what you changed and why.

## Rules
- Every change must cite specific PR evaluations as evidence
- Don't over-fit to a single PR — a pattern needs at least 2 PRs
- Keep skills concise — a reviewer should be able to read a skill in 2 minutes
- Preserve high-performing patterns even when refactoring
- Update accuracy numbers honestly
