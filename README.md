# Ursus Count — isolated shadow-count pilot

This is a static Vercel site. It is **not** connected to Ursus Major authentication or manager routes. It connects to the existing Supabase Ursus Major database through restricted, store-token-checked RPC functions defined in `schema.sql`. **No Stellar writes** are possible through the pilot RPC interface.

## Activation
1. Have an authorized database maintainer review and apply `schema.sql` to Supabase project `wobndqnfqtumbyxxtojl`.
2. Generate one random 32-byte (64-character hexadecimal) token per store. Store only `encode(extensions.digest(convert_to(token,'UTF8'),'sha256'),'hex')` in `pilot_private.store_links`, scoped to store IDs 1–13, with an expiry. Never reuse existing Ursus login/access codes. Tokens must be shared securely and should be rotated when compromised or after the pilot.
3. Create a distinct Vercel project `ursus-count-pilot` under the Cascadia team, then deploy `index.html` and `vercel.json` from this directory.
4. Provide a store-specific link `https://<new-vercel-host>/#t=<64-character-random-token>` privately to each store. Fragment bearer token is moved to tab session storage on first visit and removed from browser URL. Close the tab to end access; note that session restore behaviour differs by browser.
5. Test one authorized store and a different unauthorized/expired token. Confirm one store cannot access another store's count by substituting count IDs or observation IDs.

## Data reality
- Source for product names and SKUs: `public.inventory_cost_daily`, latest snapshot per store.
- Barcode lookup is limited to whatever is present in `public.productbarcode` and exact SKU entry. Verify UPC coverage with actual scanners; the table currently contains few entries.
- The label `selling units` is a placeholder: verify Stellar's SKU counting unit before using counts for adjustments.
- Do not treat the CSV as a verified Stellar import. Do not post inventory adjustments in this pilot.
- The current app fetches recent observations with a 5,000-row cap; use smaller open counts during testing.

## Security notes
- Access is possession of an individual store link; it is **not** individual employee authentication or an audit of employee identity.
- Store scope is verified inside each SQL function. Tables are in private schema, with RLS enabled and no anon table grants; only specifically granted token-gated RPCs are exposed.
- Because the frontend sends a bearer token to the RPCs, ensure links are shared through a trusted internal channel. Keep referrer policy `no-referrer`, use TLS and rotate links if leaked.
- Supabase publishable key is intentionally public. Never embed a service-role key in frontend code.
- Review security, accessibility and browser/scanner behaviour on real hardware before adding other stores.

## Token issuance
A reviewed one-time issuing script is included as `test_links.sql`. It returns raw bearer tokens in the SQL result, so execute it only in a restricted administrative session and do not log or share the result broadly. Once issued, only hashes remain in the database.