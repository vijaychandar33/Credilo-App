# Credilo: Supabase → Azure Migration Plan

**Document version:** 1.0  
**Last updated:** February 2025  
**Target:** India (Central India / South India / West India)

---

## 1. Executive Summary

This plan describes how to migrate the Credilo app from **Supabase** (database, auth, API) to **Azure** with minimal or zero downtime, and how to roll back to Supabase if needed.

| Current (Supabase) | Target (Azure) |
|--------------------|----------------|
| Supabase PostgreSQL + PostgREST | Azure Database for PostgreSQL Flexible Server + custom API |
| Supabase Auth | Microsoft Entra External ID |
| Supabase client (Flutter) | REST API client → App Service |
| (No storage/realtime in use) | Optional: ACS Email for OTP |

**Estimated base cost (India):** ~$29–140 USD/month (~₹2,450–11,770) depending on tier.  
**Rollback:** Yes — keep Supabase live until Azure is validated; revert config/code to use Supabase again if migration fails.

---

## 2. Current State (Supabase)

### 2.1 What Is in Use (from Supabase MCP)

| Component | Status | Details |
|-----------|--------|---------|
| **Database** | ✅ In use | 24 tables, RLS on all, 27 migrations, PostgreSQL |
| **Auth** | ✅ In use | 8 users, 47 sessions, Supabase Auth |
| **API** | ✅ In use | Via Supabase client (PostgREST) |
| **Storage** | ❌ Not used | 0 buckets |
| **Realtime** | ❌ Not used | No tables in realtime publication |
| **Edge Functions** | ❌ Not used | 0 functions |

### 2.2 Key Tables (public schema)

- `users`, `businesses`, `branches`, `branch_users`
- `cash_expenses`, `cash_counts`, `cash_closings`
- `card_sales`, `card_machines`
- `online_sales`, `online_sales_platforms`, `online_expenses`
- `qr_payments`, `upi_providers`, `daily_qr_totals`
- `dues`, `credit_expenses`, `suppliers`
- `safe_balances`, `safe_transactions`
- `fixed_expenses`, `pending_users`
- `branch_visibility`, `branch_closing_cycle`

### 2.3 Extensions in Use

- `pgcrypto`, `uuid-ossp`, `pg_stat_statements`, `supabase_vault`, `pg_graphql`

---

## 3. Target Azure Architecture

### 3.1 Services Required

| # | Component | Azure Service | Purpose |
|---|-----------|---------------|---------|
| 1 | Database | Azure Database for PostgreSQL (Flexible Server) | Replace Supabase Postgres; run migrations, RLS |
| 2 | Auth | Microsoft Entra External ID | Replace Supabase Auth; sign-up, sign-in, JWT |
| 3 | API | Azure App Service (Linux) | Replace PostgREST; your REST API for Flutter app |
| 4 | Email (OTP) | Azure Communication Services – Email | Optional: custom OTP emails; no fixed cost |
| 5 | Secrets | Azure Key Vault | Optional: store DB connection string, API keys |

### 3.2 Base Configuration (India)

- **Region:** Central India or South India (same for all resources).
- **Database:** B1ms (1 vCore, 2 GiB) + 32 GB storage — ~$16/month.
- **App Service:** B1 (1 core, 1.75 GB) or P1v3 (2 vCPU, 8 GB) — ~$13 or ~$124/month.
- **Auth:** Entra External ID — first 50,000 MAU free.
- **ACS Email:** Pay per send (~$0.00025/email); no fixed fee.

### 3.3 Network (High Level)

```
[Flutter App] → HTTPS → [App Service] → [Azure PostgreSQL]
                    ↑
              [Entra External ID] (auth)
              [ACS Email] (OTP, optional)
```

---

## 4. Prerequisites

### 4.1 Before Starting

- [ ] Azure subscription (pay-as-you-go or similar).
- [ ] Azure CLI installed and logged in (`az login`), subscription set.
- [ ] Supabase project **unchanged** and **not deleted** until migration is validated.
- [ ] Git branch for migration (e.g. `feature/azure-migration`) so you can revert.
- [ ] Backup or export of Supabase data (optional but recommended).

### 4.2 Access and Permissions

- [ ] Contributor (or equivalent) on the Azure subscription or resource group.
- [ ] Ability to create Entra External ID tenant (or use existing).
- [ ] Supabase project URL and keys available (read-only usage during migration).

---

## 5. Migration Phases

### Phase 0: Preparation (No Production Change)

| Step | Action | Owner |
|------|--------|--------|
| 0.1 | Create migration branch in Git | Dev |
| 0.2 | Document current Supabase env vars (URL, anon key, etc.) | Dev |
| 0.3 | Export Supabase schema (e.g. from MCP or `pg_dump --schema-only`) | Dev / MCP |
| 0.4 | List all RLS policies per table for re-creation in Azure | Dev / MCP |
| 0.5 | Decide cutover strategy: minimal downtime (short window) vs zero downtime (parallel + switch) | Team |

**Deliverable:** Schema export, RLS list, strategy decision.

---

### Phase 1: Create Azure Resources (India)

All resources in **Central India** (or South India) unless otherwise required.

| Step | Action | Azure CLI / Portal |
|------|--------|--------------------|
| 1.1 | Create resource group, e.g. `rg-credilo-prod` | `az group create --name rg-credilo-prod --location centralindia` |
| 1.2 | Create Azure PostgreSQL Flexible Server (B1ms, 32 GB), allow Azure services + your IP | `az postgres flexible-server create` (see Appendix A) |
| 1.3 | Create App Service plan (B1 or P1v3 Linux) | `az appservice plan create` |
| 1.4 | Create Web App (API) on the plan | `az webapp create` |
| 1.5 | Create Microsoft Entra External ID tenant (or use existing) | Portal: Entra → External ID |
| 1.6 | (Optional) Create Communication Services resource for Email | `az communication create` |
| 1.7 | (Optional) Create Key Vault for secrets | `az keyvault create` |

**Deliverable:** All Azure resources created; PostgreSQL and App Service reachable.

---

### Phase 2: Database Migration

| Step | Action | Notes |
|------|--------|------|
| 2.1 | Run schema migration on Azure PostgreSQL (tables, indexes, FKs, extensions: uuid-ossp, pgcrypto) | Use exported DDL; add RLS policies |
| 2.2 | Recreate RLS policies on Azure PostgreSQL | Align with Supabase RLS (role/user mapping to Entra later) |
| 2.3 | Data migration: one-time or continuous sync | Option A: `pg_dump` (Supabase) → `pg_restore` (Azure) in a window. Option B: ETL/CDC for zero downtime |
| 2.4 | Verify row counts and critical queries on Azure | Run same queries as production |
| 2.5 | Create DB user/role for App Service (least privilege) | Store credentials in Key Vault or App Service config |

**Deliverable:** Azure PostgreSQL has same schema, RLS, and data as Supabase (or in sync).

---

### Phase 3: Auth Migration (Entra External ID)

| Step | Action | Notes |
|------|--------|------|
| 3.1 | Create External ID tenant (if new) | Portal: Microsoft Entra → External Identities |
| 3.2 | Configure Email one-time passcode (and/or Email + password) | Enable in tenant |
| 3.3 | (Optional) Configure custom email provider (ACS Email) for OTP | Custom extension: EmailOtpSend → your API → ACS |
| 3.4 | Create App registration for Credilo (client ID, redirect URIs) | For Flutter app |
| 3.5 | Create user flow: sign-up and sign-in | Include attributes you need (e.g. email, name, phone) |
| 3.6 | Export Supabase Auth users (auth.users) and map to Entra | Script: create users in Entra or use migration API; set passwords or force OTP on first login |
| 3.7 | Document Entra issuer URL, client ID, scopes for Flutter | For token validation in API |

**Deliverable:** Entra configured; existing users migrated or invited; Flutter can authenticate against Entra.

---

### Phase 4: API Development and Deployment

| Step | Action | Notes |
|------|--------|------|
| 4.1 | Implement REST API (e.g. Node/Express, .NET, or other) that mirrors current Supabase usage | Same operations: CRUD for branches, expenses, sales, etc. |
| 4.2 | API: connect to Azure PostgreSQL with pooled connection (e.g. PgBouncer or server-side pool) | Use connection string from Key Vault or config |
| 4.3 | API: validate JWT from Entra (issuer, audience, signing keys) and map to user/role for RLS | Use same claims you use in RLS (e.g. `auth.uid()`) |
| 4.4 | Add config switch: e.g. `USE_AZURE=true/false` or `API_BASE_URL` (Supabase vs Azure) | Enables rollback without code revert |
| 4.5 | Deploy API to App Service (zip deploy or CI/CD) | Set env: DB URL, Entra issuer, client ID |
| 4.6 | Smoke-test API (health, auth, one read/write per entity) | From Postman or Flutter |

**Deliverable:** API running on App Service; Flutter can point to it and get same behaviour as Supabase.

---

### Phase 5: Flutter App Changes

| Step | Action | Notes |
|------|--------|------|
| 5.1 | Add Entra auth (MSAL or OIDC) for login/sign-up and OTP flow | Replace Supabase Auth calls |
| 5.2 | Replace Supabase client with HTTP client to your API (or abstract behind a “data source” interface) | Keep same app logic; swap implementation |
| 5.3 | Use config (env/build) for API base URL and auth (Supabase vs Azure) | One build can target Supabase or Azure |
| 5.4 | Test on staging: full flow with Azure (DB + API + Entra) | Login, CRUD, OTP |

**Deliverable:** App works end-to-end with Azure; config switch for Supabase vs Azure.

---

### Phase 6: Cutover and Go-Live

| Step | Action | Notes |
|------|--------|------|
| 6.1 | Final data sync Supabase → Azure (if not already continuous) | Stop writes to Supabase or run last delta sync |
| 6.2 | Put app in maintenance or use feature flag to switch to Azure | Prefer flag so rollback is instant |
| 6.3 | Switch config to Azure: API URL = App Service, Auth = Entra | Deploy or release flag |
| 6.4 | Monitor errors, latency, and auth for 24–48 hours | App Insights, logs |
| 6.5 | If stable: keep Azure as production; optionally reduce Supabase to read-only backup for a while | Do not delete Supabase until confident |

**Deliverable:** Production on Azure; Supabase still available for rollback.

---

### Phase 7: Rollback (If Needed)

| Step | Action |
|------|--------|
| 7.1 | Revert config: point app back to Supabase (API URL + Supabase Auth). |
| 7.2 | Redeploy or flip feature flag. |
| 7.3 | If data was written only to Azure after cutover, decide: re-export from Azure and import to Supabase, or accept loss of that slice. |
| 7.4 | Fix issues on Azure in parallel; retry cutover when ready. |

**No Supabase deletion** until Azure has been stable for a defined period (e.g. 2–4 weeks).

---

## 6. Cost Summary (India, Monthly)

| Scenario | Database | App Service | Auth | ACS Email | Total (USD) | Total (INR ~) |
|----------|----------|-------------|------|-----------|-------------|----------------|
| **Minimal** | B1ms + 32 GB (~$16) | B1 (~$13) | $0 | ~$0 | **~$29** | ~₹2,450 |
| **Production** | B1ms + 32 GB (~$16) | P1v3 (~$124) | $0 | ~$0 | **~$140** | ~₹11,770 |
| **With 1-yr reserve** | Reserved (~$11) | P1v3 reserved (~$74) | $0 | ~$0 | **~$85** | ~₹7,140 |

*ACS Email: pay per send (~$0.00025/email); no fixed cost.*

---

## 7. Traffic and Limits (Reference)

| | Supabase Free | Azure base (B1 + B1ms) |
|--|----------------|------------------------|
| **Concurrent users** | Tens | Hundreds |
| **Requests/sec (simple API)** | Best-effort, low | Hundreds |
| **Auth MAU** | 50,000 | 50,000 (free) |
| **DB size** | 500 MB | 32 GB+ |
| **Egress** | 5 GB/month | Pay per GB |

---

## 8. Checklist (One-Page)

- [ ] Phase 0: Branch, schema export, RLS list, strategy.
- [ ] Phase 1: Resource group, PostgreSQL, App Service, Entra, (optional) ACS, Key Vault.
- [ ] Phase 2: Schema + RLS on Azure, data sync, verification, DB user for API.
- [ ] Phase 3: Entra tenant, user flow, (optional) custom OTP, app registration, user migration.
- [ ] Phase 4: API implementation, DB + auth integration, config switch, deploy, smoke-test.
- [ ] Phase 5: Flutter Entra + API client, config for Supabase vs Azure, E2E test.
- [ ] Phase 6: Final sync, switch to Azure, monitor, keep Supabase for rollback.
- [ ] Rollback plan documented and tested (config revert).

---

## 9. Appendix A: Example Azure CLI Commands (Skeleton)

```bash
# Resource group
az group create --name rg-credilo-prod --location centralindia

# PostgreSQL Flexible Server (adjust names, admin password, SKU)
az postgres flexible-server create \
  --resource-group rg-credilo-prod \
  --name credilo-pg-prod \
  --location centralindia \
  --admin-user pgadmin \
  --admin-password '<secure>' \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 15

# Allow Azure services + your IP (example)
az postgres flexible-server firewall-rule create \
  --resource-group rg-credilo-prod \
  --name credilo-pg-prod \
  --rule-name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# App Service plan + Web App (Linux)
az appservice plan create \
  --resource-group rg-credilo-prod \
  --name plan-credilo-api \
  --is-linux --sku B1

az webapp create \
  --resource-group rg-credilo-prod \
  --plan plan-credilo-api \
  --name credilo-api-prod \
  --runtime "NODE:18-lts"
```

*Use Azure Pricing Calculator and official docs for exact parameters and regions.*

---

## 10. Appendix B: References

- [Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/azure/postgresql/flexible-server/)
- [Azure App Service](https://learn.microsoft.com/azure/app-service/)
- [Microsoft Entra External ID](https://learn.microsoft.com/entra/external-id/)
- [Azure Communication Services – Email](https://learn.microsoft.com/azure/communication-services/concepts/email/email-overview)
- [Azure Pricing Calculator (India)](https://azure.microsoft.com/en-in/pricing/calculator/)

---

*End of migration plan.*
