# Deploy Ursus Count from Cascadia376/barcode_scanner

This repository's `main` branch is now the **Ursus Count store-count pilot**. The previous Python barcode-lookup application is preserved under `archive/pre-ursus-count-pilot-2026-11-06` and in Git history.

**Repository is public.** Never commit store access tokens, confidential store reports, or service-role credentials. The browser's Supabase publishable key is public by design; actual store authorization is enforced by token-checked RPCs.

## Vercel
- Import `Cascadia376/barcode_scanner` as **a new independent Vercel project** named `ursus-count-pilot`, under the `Ursus Major's projects` team.
- Framework preset: **Other**. Root directory: `/`. No build command. Output is the static `index.html`.
- Do not associate the new project with Ursus Major's manager routes or authentication.
- Before issuing access links, verify the base URL without a token displays the private-access screen and has no access to products or observations.
- Do not use Vercel preview deployment protection as a substitute for the app's own store isolation.
- If Vercel requires verified commits authored with `jjordan@cascadialiquor.com`, have Jay create a **genuinely signed** commit on the authorized workstation and verify GitHub shows **Verified**. A commit's author email alone does not sign it.

## Database
- The required private schema and token-checked RPC functions were created in the Ursus Major Supabase project during development. `schema.sql` documents the pilot's intended database schema and should be reviewed and reconciled rather than blindly reapplied.
- No direct Stellar or manager app write access exists.
- The browser reads a store-scoped product catalog from the latest inventory cost snapshot. UPC coverage is incomplete; manual SKU search is available.
- The screen currently labels counts as selling units. Validate SKU count units with Stellar before operational use.

## Store access
- After the new project is deployed and security-tested, issue 64-character random, revocable store tokens in an authorized SQL session. `test_links.sql` is a sample issuance query. Do not post its returned raw token values into GitHub, chat, logs, screenshots, or Vercel environment variables.
- A store link is `https://<new-project-host>/#t=<token>`; the fragment is removed from the address bar and stored in tab session storage on first access.
- Verify a token for Store A cannot list, open, amend, or finish Store B counts.

## Field test
Test a store tablet with a Bluetooth HID scanner, repeated SKUs, zero counts, unsaved-quantity protection, corrections, refresh/resume, and CSV export. CSV is a **shadow-count artifact**, not a verified Stellar import. No stock posting.
