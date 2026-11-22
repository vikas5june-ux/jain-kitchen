# Jain Kitchen Operations Hub

A multi-outlet restaurant operations prototype for Banjara Hills, Jubilee Hills, Gachibowli, and a Central Kitchen / Head Office. The static demo is hosted on GitHub Pages and runs without a build step.

## Run it

Open `index.html` in a browser. The demo uses sample records and browser `localStorage`; use **Settings → Demo role access** to preview the Owner, Outlet Manager, Central Kitchen / Purchase Manager, and Cashier / Captain views. A browser reset clears locally saved demo changes.

## Modules in the prototype

- Consolidated dashboard with outlet comparison, daily sales, KDS queue, and operational alerts
- Outlet-filtered kitchen order board with New → Preparing → Ready → Completed actions, sample recipe stock deduction, KOT print, and table map
- POS flow, sample GST line, invoice sequence preview, and order hand-off to KDS
- Menu master with dietary tags, prep stations, packaging charges, and per-outlet stock switches
- Ingredients, PAR tracking, sample vendors, purchase orders / GRNs, stock indents, transfers, and wastage logs
- Customer profiles with masked contact data, loyalty metrics, dietary preferences, feedback and recovery tickets
- Staff directory, shift attendance, payroll estimate, transfers, and redacted CSV export
- Cash closing, sample outlet P&L, payout reconciliation CSV import, and sample GST/Tally exports
- Outlet/localization configuration, demo RBAC selector, and integration readiness notes

## Important limitations

This is a **front-end demo**, not a production restaurant ERP. Browser role switching is not authentication or secure authorization; all demo records are stored locally in the visitor's browser. The included [Supabase starter schema](supabase-schema.sql) and [signed aggregator webhook scaffold](supabase/functions/aggregators-webhook/index.ts) are design/code scaffolds only and have not been deployed or connected to a database. No Supabase project, API server, live POS, payment processor, Swiggy/Zomato middleware, GST filing, WhatsApp provider, or Tally connection is configured.

All outlet compliance identifiers, menu pricing, settlement figures, ingredients, employee, customer, attendance, and financial data are invented examples. No Aadhaar, PAN, bank account, real phone number, or real GSTIN/FSSAI number is included. Replace demo data only after confirming business, legal, tax, food-safety, and privacy requirements with the relevant professionals. Do not enter real customer or employee personal details into this demo.

Before production, configure Supabase Auth, apply and review database row-level security, store secrets only server-side, validate webhook signatures, implement transactional stock deduction and invoice sequencing, and connect approved partner APIs. Swiggy/Zomato aggregator flows need an approved POS middleware/partner connection. The Pages deployment serves static files only; it cannot host the webhook endpoint or safely store service credentials.
