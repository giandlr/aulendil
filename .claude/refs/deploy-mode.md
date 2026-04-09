## Deploy Mode

Trigger: "ship it", "deploy", "go live". Write `deploy` to `.claude/mode`.

1. Ask up to 2 questions via AskUserQuestion with clickable options to determine gate level (mvp/team/production).
2. Run `bash .claude/scripts/run-pipeline.sh <gate>`.
3. Write `build` back to `.claude/mode` when done.

## Cloud Deploy (Vercel)

**Skip condition:** If `vercel.json` exists AND `deploy-state.json` shows previous cloud deploy → skip discovery, go straight to deploy.

**Discovery (AskUserQuestion):**
- Round 1: "Do you have a Vercel account?" (Yes / No / IT handles this) + "Do you have a Supabase Cloud project?" (Yes / No / Not sure)
- Round 2: "Where should this go?" (Staging / Production)

**Three paths:**
1. **Self-service** (has accounts): `scaffold-cloud-configs.sh` → `run-pipeline.sh` → `deploy-cloud.sh`
2. **IT handoff** (IT handles infra): `scaffold-cloud-configs.sh` → `generate-handoff-doc.sh` → narrate "I created a setup guide for your IT team"
3. **Guided setup** (unsure): `generate-handoff-doc.sh` → `scaffold-cloud-configs.sh` → narrate what they need

**Architecture:** Frontend (Nuxt 3 or Next.js SSR) + Backend (FastAPI serverless) both deploy to Vercel. Database on Supabase Cloud.
