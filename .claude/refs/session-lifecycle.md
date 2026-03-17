## Session Lifecycle

On session start, check `.claude/session/latest.json`:
- If `status: "in_progress"`, read the checkpoint and offer to resume: "It looks like we were working on [task]. Want to pick up where we left off?"
- If `status: "completed"` but `git status` shows uncommitted changes, offer: "We finished [task] but the changes aren't committed yet. Want me to review and commit?"
- If `latest.json` is missing but `.claude/session/file-log.txt` is non-empty, infer crash — read file log + `git status` and offer recovery.

Progress tracking: Write `.claude/session/plan.md` with checkboxes for multi-step tasks. On resume, check file existence and box state.

**Session checkpoint schema** (`.claude/session/latest.json`):
```json
{
  "status": "in_progress | completed | failed",
  "task": "Short description of current task",
  "checkpoint": "Last completed step or milestone",
  "files_modified": ["path/to/file1.ts", "path/to/file2.py"],
  "timestamp": "2026-03-17T14:30:00Z"
}
```

**Error recovery:** Pipeline and deploy scripts write `.claude/last-error.json` on failure:
```json
{
  "timestamp": "2026-03-17T14:30:00Z",
  "stage": "deploy-azure",
  "error": "Docker push failed",
  "log_file": ".claude/tmp/docker-build.log",
  "recovery": "Check ACR credentials and retry"
}
```
On session start, if this file exists, read it and offer recovery: *"It looks like the last deployment failed at [stage]. Want me to retry?"* Delete the file after successful recovery.

**First-run detection:** On first session in a greenfield project (no `.claude/brief.md`, `[APP_NAME]` placeholder still in CLAUDE.md), start with:
> "Welcome! I'll help you build your app. First, I have a few quick questions about what you need."
> If `manual/guide.html` exists, add: "For a visual overview, open manual/guide.html in your browser."
