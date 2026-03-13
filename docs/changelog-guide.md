# Changelog Guide — For Non-Technical Managers

This guide explains the changelog system in plain language. You don't need to
know anything about coding to understand what's going on.

## What Is a Changelog?

A changelog is a record of every change made to your application. Think of it
like a diary that writes itself every time Claude Code finishes building
something for you.

## Two Files, Two Purposes

Your project has two changelog files. They serve different audiences:

### CHANGELOG.md — "What shipped?"
This is the simple one. It lives in the project root and looks like release
notes. When you open it, you'll see changes grouped by version:

```
## [v1.2.0] — 2026-03-15
### Added
- User can now reset their password via email
### Fixed
- Login page no longer shows a blank screen on mobile
```

**Who reads this:** You, your stakeholders, anyone who wants a quick summary
of what changed in each release.

**You don't need to do anything** — entries are added automatically every time
Claude Code successfully completes a task.

### .claude/dev-log.md — "What happened in detail?"
This is the detailed one. Each entry includes exactly what files changed,
which tests ran, what the code reviewer said, and whether it's been deployed.

**Who reads this:** Engineers debugging an issue, auditors reviewing the
development process, or you when you need to trace back a specific change.

**You don't need to do anything** — entries are written automatically.

## What Happens Automatically

When you ask Claude Code to build something, here's what happens behind
the scenes:

1. Claude writes code and tests
2. The pipeline runs automatically (unit tests, UI tests, integration tests,
   performance tests)
3. If all tests pass, a senior AI reviewer (Opus) examines the code
4. If Opus approves, the pipeline passes
5. **A changelog entry and dev-log entry are written automatically**
6. The changes are committed to your project history

You just describe what you want. Everything else is automatic.

## When Do Changelog Entries Get Created?

Changelog entries are created only when you **deploy** — not during regular building.

When you're building and testing ideas (build mode), no changelog entries are written.
This keeps the changelog clean and meaningful — it only records changes that actually
shipped.

When you say "ship it" or "share with my team," Claude runs the deploy pipeline.
If the pipeline passes, a changelog entry is automatically created recording what
changed.

**In short:**
- Building and experimenting — no changelog entries
- Deploying/sharing — changelog entry created automatically

## How to Read a Dev-Log Entry

Each entry has these sections:

- **Session/Date/Author** — When it happened and who was working
- **Branch/Commit** — Technical reference (you can ignore these)
- **What Changed** — A table showing which files were added, modified, or deleted
- **Change Description** — A plain English summary of what was done
- **Test Results** — Did each test stage pass or fail?
  - PASSED means everything is working
  - FAILED means something broke (Claude will fix it)
  - SKIPPED means that test type isn't set up yet (not a problem)
- **Opus Review Summary**
  - **APPROVED** — The code reviewer found no issues. Everything is good.
  - **APPROVED WITH CONDITIONS** — The code is good enough for now, but some
    features still need to be added before going live in production. The
    "Pre-production items outstanding" number tells you how many.
  - **CHANGES REQUIRED** — The reviewer found problems that must be fixed.
    Claude will address these automatically.
- **Deployment** — Whether this change has been deployed (sent live)

## How to Mark a Deployment

After your app has been deployed to a server (your tech team will handle the
actual deployment), run this command to record it:

```
bash .claude/scripts/mark-deployed.sh production
```

Replace `production` with `staging` if it's going to a test environment first.

This updates the changelog to show that the changes are live.

## How to Cut a Release

When you're ready to call a set of changes a "version" (like going from
v1.0.0 to v1.1.0), run:

```
bash .claude/scripts/tag-release.sh v1.1.0
```

This does three things:
1. Moves all the "Unreleased" changes in CHANGELOG.md into a named version
2. Creates a version tag in the project history
3. Tells you how to publish it

**Version numbers work like this:**
- v1.0.0 → v1.0.1 = Small fix (bug fix, typo)
- v1.0.0 → v1.1.0 = New feature added
- v1.0.0 → v2.0.0 = Major change (things work differently than before)

## What to Do If the Pipeline Fails

If the changelog shows a failed pipeline, **you don't need to do anything**.
Claude Code will see the failure and work to fix it. The changelog only
records *successful* pipeline runs, so a failure just means "not done yet."

If you see the same failure repeatedly, ask Claude Code: "Why is the pipeline
failing?" and it will explain what's going wrong in plain language.

## What Is "APPROVED WITH CONDITIONS"?

This means the code works correctly and passes all required checks, but
some features that are needed before going live in production haven't been
built yet. These are tracked as "Pre-production items outstanding."

Think of it like a building inspection: the structure is sound (approved),
but you still need to install the fire alarm and emergency exits before
opening to the public (conditions).

Claude Code will continue building these features. You'll see the
"Pre-production items outstanding" number decrease over time until
everything is complete.
