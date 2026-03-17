## Deploy Mode

Trigger: "ship it", "deploy", "go live". Write `deploy` to `.claude/mode`.

1. **If `DEPLOY_TARGET` is not set in `.env`:** Ask (AskUserQuestion) "Where do you want to put the app?" with options: "On the company server" / "In the cloud". Set `DEPLOY_TARGET=azure` or `DEPLOY_TARGET=vercel` in `.env` — this setting sticks until changed.
2. Ask up to 2 more questions via AskUserQuestion with clickable options to determine gate level (mvp/team/production).
3. Run `bash .claude/scripts/run-pipeline.sh <gate>` (reads `DEPLOY_TARGET` from env).
4. Write `build` back to `.claude/mode` when done.

**Language rule:** Say "company server" when referring to Azure. Say "cloud" when referring to Vercel. Never say the technical names in conversation. Say "switch to the company server" / "switch to the cloud" for target changes.

**Switch anytime:** If the manager says "switch to the company server" or "switch to the cloud", update `DEPLOY_TARGET` in `.env` and confirm in plain English.

## Cloud Deploy Mode

Trigger: "deploy to cloud", "make this live", "put it online", "go live" (when context implies cloud deployment, not local).

**Skip condition:** If `DEPLOY_TARGET` is already set → skip target discovery, go straight to the appropriate path.

### Path A — Cloud (Vercel)

**Skip condition:** If `vercel.json` exists AND `deploy-state.json` shows previous cloud deploy → skip discovery, go straight to deploy.

**Discovery (AskUserQuestion):**
- Round 1: "Do you have a Vercel account?" (Yes / No / IT handles this) + "Do you have a Supabase Cloud project?" (Yes / No / Not sure)
- Round 2: "Where should this go?" (Staging / Production)

**Three paths:**
1. **Self-service** (has accounts): `scaffold-cloud-configs.sh` → `run-pipeline.sh` → `deploy-cloud.sh`
2. **IT handoff** (IT handles infra): `scaffold-cloud-configs.sh` → `generate-handoff-doc.sh` → narrate "I created a setup guide for your IT team"
3. **Guided setup** (unsure): `generate-handoff-doc.sh` → `scaffold-cloud-configs.sh` → narrate what they need

**Architecture:** Frontend (Nuxt 3 SSR) + Backend (FastAPI serverless) both deploy to Vercel. Database on Supabase Cloud.

### Path B — Company Server (Azure)

**Skip condition:** If `azure-container-app.yml` exists AND `deploy-state.json` shows previous azure deploy → skip discovery, go straight to deploy.

**Discovery (AskUserQuestion):**
- Round 1: "Does your IT team have Azure set up?" (Yes / No / Not sure) + "Do you have a Google Workspace account for company login?" (Yes / No)
- Round 2: "Where should this go?" (Staging / Production)

**Three paths:**
1. **Self-service** (IT has Azure): `scaffold-azure-configs.sh` → `run-pipeline.sh` (DEPLOY_TARGET=azure) → `deploy-azure.sh`
2. **IT handoff** (IT handles infra): `scaffold-azure-configs.sh` → `generate-azure-handoff-doc.sh` → narrate "I created a setup guide for your IT team"
3. **Guided setup** (unsure): `generate-azure-handoff-doc.sh` → `scaffold-azure-configs.sh` → narrate what they need

**Architecture:** App runs as a Docker container on Azure Container Apps. Google SSO is handled automatically — employees log in with their company email. Database isolated per app via `APP_SCHEMA`.
