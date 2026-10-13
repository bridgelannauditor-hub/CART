# Phase 0 disposable validation

This suite is intentionally local-only. It refuses no remote connection on its
own, so run it only through a fresh local Supabase project whose database URL is
confirmed to use `127.0.0.1` or `localhost`.

Prerequisites:

1. Docker Desktop with the WSL 2 backend.
2. Supabase CLI installed as a pinned project development dependency or through
   Scoop. Do not install or use a production access token.
3. A generated local `supabase/config.toml` from `supabase init` if one is not
   already present.

Validation sequence:

```text
supabase start
supabase db reset
supabase test db supabase/tests/phase0_prevalidation.sql
supabase stop --no-backup
```

`supabase db reset` is the clean-database migration test. For a representative
upgrade test, first restore a sanitized pre-Phase-0 schema/data dump into a
second disposable local project, then apply only migrations
`202610130001` through `202610130005`. Never use a production connection string
or a dump containing real identity, message, payment, or order data.

The SQL test uses actual PostgreSQL `authenticated` and `service_role` roles,
sets local JWT claims for `auth.uid()`, and rolls back all fixtures. Several
negative assertions are expected to fail against the current source because
broad seller enforcement, message/conversation remediation, profile-safe read
views, COD-only checkout, and LIVE shutdown have not been implemented in these
five migrations. Those failures are release blockers, not tests to waive.

The suite also checks both table-level and column-level ACLs. Do not interpret a
successful clean migration reset as authorization validation: the pgTAP command
must run to completion, and every unexpected failure must be reviewed. The
known deferred-boundary failures should remain visible until separately
approved containment migrations replace the legacy policies and RPC checks.
