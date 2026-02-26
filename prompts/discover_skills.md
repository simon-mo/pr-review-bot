# Discover Skills from PR Review Data

You are analyzing closed PRs from the vLLM project to discover review
patterns and create skills.

## Your Task

Read the PR data in the directories listed below. For each PR, study:
1. The description and diff (what changed)
2. The review comments (what reviewers said)
3. The final outcome (merged or rejected, and why)

Look for PATTERNS — recurring things reviewers care about. Not generic
code review advice, but specific vLLM maintainer behaviors:
- What file paths trigger extra scrutiny?
- What kinds of changes get approved quickly vs slowly?
- What do reviewers consistently flag?
- What gets PRs rejected?
- Are there reviewer-specific patterns?

## Current Skills

Read all files in `skills/` to see what patterns are already captured.

## Instructions

1. Read each PR directory in the batch
2. For each PR, note what reviewers focused on and what the outcome was
3. After reading all PRs, identify patterns that are NOT yet captured
   by existing skills
4. For new patterns: create a new skill file in `skills/`
5. For patterns that extend existing skills: update the relevant skill
6. For each skill you create or modify, explain your reasoning

## Rules
- DO NOT create generic skills like "check for bugs" or "review code quality"
- Every pattern must cite specific PR numbers as evidence
- Skills must be actionable — a reviewer reading the skill should know
  exactly what to look for
- Maximum 20 active skills. If you need a new one and are at the limit,
  merge or deprecate first.
- Write skills as markdown files in `skills/` named with snake_case

## PR Directories to Analyze

{{PR_DIRS}}
