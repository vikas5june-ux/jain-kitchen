-- Jain Kitchen Operations Hub: starter schema for Supabase/Postgres.
-- Review and adapt before production. Demo identifiers and policies are not deployed.
create extension if not exists pgcrypto;

create table public.outlets (
  id text primary key check (id in ('BH','JH','GC','CK')),
  name text not null,
  outlet_type text not null check (outlet_type in ('restaurant','central_kitchen')),
  area text not null,
  timezone text not null default 'Asia/Kolkata',
  currency text not null default 'INR',
  gstin text,
  fssai_license text,
  invoice_prefix text not null,
  invoice_sequence bigint not null default 0 check (invoice_sequence >= 0),
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('owner','outlet_manager','purchase_manager','cashier')),
  outlet_id text references public.outlets(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (role in ('owner','purchase_manager') or outlet_id is not null)
);

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() and active = true $$;

create or replace function public.current_outlet_id()
returns text language sql stable security definer set search_path = public
as $$ select outlet_id from public.profiles where id = auth.uid() and active = true $$;

create or replace function public.can_access_outlet(target_outlet text)
returns boolean language sql stable security definer set search_path = public
as $$ select public.current_role() = 'owner'
      or public.current_outlet_id() = target_outlet
      or (public.current_role() = 'purchase_manager' and target_outlet = 'CK') $$;

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  sku text unique not null,
  name text not null,
  category text not null,
  base_price numeric(12,2) not null check (base_price >= 0),
  packaging_charge numeric(12,2) not null default 0 check (packaging_charge >= 0),
  prep_station text not null check (prep_station in ('Tandoor','Curry','Chaat','Beverages')),
  dietary_tags text[] not null default '{}',
  is_published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.outlet_menu_stock (
  outlet_id text not null references public.outlets(id),
  menu_item_id uuid not null references public.menu_items(id),
  is_available boolean not null default true,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (outlet_id, menu_item_id)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  -- Keep direct identifiers encrypted or tokenized by a trusted server; do not put plaintext in public clients.
  mobile_lookup_hash text unique,
  display_name text not null,
  dietary_profile text,
  fasting_preference text,
  spice_preference text,
  allergy_notes text,
  loyalty_points integer not null default 0 check (loyalty_points >= 0),
  consent_marketing_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null,
  outlet_id text not null references public.outlets(id),
  customer_id uuid references public.customers(id),
  channel text not null check (channel in ('dine_in','direct','swiggy','zomato')),
  status text not null default 'new' check (status in ('new','preparing','ready','completed','cancelled')),
  table_label text,
  gross_amount numeric(12,2) not null default 0 check (gross_amount >= 0),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(12,2) not null default 0 check (tax_amount >= 0),
  packaging_amount numeric(12,2) not null default 0 check (packaging_amount >= 0),
  platform_reference text,
  opened_at timestamptz not null default now(),
  preparing_at timestamptz,
  ready_at timestamptz,
  completed_at timestamptz,
  unique (outlet_id, order_number)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id),
  item_name_snapshot text not null,
  quantity numeric(10,3) not null check (quantity > 0),
  base_price numeric(12,2) not null check (base_price >= 0),
  packaging_charge numeric(12,2) not null default 0,
  dietary_notes text[] not null default '{}'
);

create table public.ingredients (
  id uuid primary key default gen_random_uuid(),
  sku text unique not null,
  name text not null,
  base_unit text not null check (base_unit in ('kg','g','l','ml','pc')),
  jain_verified boolean not null default false,
  verification_note text,
  created_at timestamptz not null default now()
);

create table public.recipe_bom (
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  ingredient_id uuid not null references public.ingredients(id),
  quantity_per_serving numeric(12,4) not null check (quantity_per_serving > 0),
  unit text not null,
  primary key (menu_item_id, ingredient_id)
);

create table public.inventory_balances (
  outlet_id text not null references public.outlets(id),
  ingredient_id uuid not null references public.ingredients(id),
  on_hand numeric(14,4) not null default 0 check (on_hand >= 0),
  minimum_par numeric(14,4) not null default 0 check (minimum_par >= 0),
  last_unit_rate numeric(12,2) not null default 0 check (last_unit_rate >= 0),
  updated_at timestamptz not null default now(),
  primary key (outlet_id, ingredient_id)
);

create table public.vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  gstin text,
  payment_terms_days integer not null default 0 check (payment_terms_days >= 0),
  jain_verified boolean not null default false,
  verification_note text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  vendor_id uuid not null references public.vendors(id),
  po_number text not null,
  status text not null default 'draft' check (status in ('draft','submitted','in_transit','part_received','received','cancelled')),
  ordered_at timestamptz not null default now(),
  expected_at timestamptz,
  unique (outlet_id, po_number)
);

create table public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  ingredient_id uuid not null references public.ingredients(id),
  quantity numeric(14,4) not null check (quantity > 0),
  unit_rate numeric(12,2) not null check (unit_rate >= 0),
  received_quantity numeric(14,4) not null default 0 check (received_quantity >= 0)
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  ingredient_id uuid not null references public.ingredients(id),
  order_id uuid references public.orders(id),
  movement_type text not null check (movement_type in ('purchase_receipt','recipe_consumption','wastage','adjustment','transfer_in','transfer_out')),
  quantity_delta numeric(14,4) not null,
  unit text not null,
  reason text,
  actor_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.stock_indents (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  ingredient_id uuid not null references public.ingredients(id),
  requested_quantity numeric(14,4) not null check (requested_quantity > 0),
  unit text not null,
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','fulfilled','rejected')),
  requested_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  source_outlet_id text not null references public.outlets(id),
  destination_outlet_id text not null references public.outlets(id),
  ingredient_id uuid not null references public.ingredients(id),
  quantity numeric(14,4) not null check (quantity > 0),
  unit text not null,
  status text not null default 'requested' check (status in ('requested','approved','in_transit','received','cancelled')),
  requested_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (source_outlet_id <> destination_outlet_id)
);

create table public.wastage_logs (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  ingredient_id uuid not null references public.ingredients(id),
  quantity numeric(14,4) not null check (quantity > 0),
  unit text not null,
  reason_code text not null check (reason_code in ('expired','spoiled','prep_loss','damaged','other')),
  notes text,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.operating_expenses (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  expense_date date not null,
  category text not null check (category in ('rent','utilities','packaging','payroll','aggregator_commission','ads','petty_cash','other')),
  amount numeric(12,2) not null check (amount >= 0),
  vendor_id uuid references public.vendors(id),
  reference text,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.cash_closings (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  business_date date not null,
  opening_cash numeric(12,2) not null default 0,
  cash_sales numeric(12,2) not null default 0,
  petty_cash_expenses numeric(12,2) not null default 0,
  physical_cash numeric(12,2) not null default 0,
  upi_total numeric(12,2) not null default 0,
  card_total numeric(12,2) not null default 0,
  swiggy_total numeric(12,2) not null default 0,
  zomato_total numeric(12,2) not null default 0,
  submitted_by uuid not null references auth.users(id),
  submitted_at timestamptz not null default now(),
  unique (outlet_id, business_date)
);

create table public.aggregator_settlements (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  platform text not null check (platform in ('swiggy','zomato')),
  external_order_id text not null,
  gross_order_value numeric(12,2) not null default 0,
  restaurant_discount numeric(12,2) not null default 0,
  commission_amount numeric(12,2) not null default 0,
  gst_on_commission numeric(12,2) not null default 0,
  tcs_amount numeric(12,2) not null default 0,
  tds_amount numeric(12,2) not null default 0,
  ad_spend numeric(12,2) not null default 0,
  expected_net numeric(12,2) not null default 0,
  actual_settled numeric(12,2) not null default 0,
  settlement_date date,
  unique (outlet_id, platform, external_order_id)
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  employee_code text not null,
  display_name text not null,
  job_role text not null,
  monthly_salary numeric(12,2) not null default 0,
  active boolean not null default true,
  unique (outlet_id, employee_code)
  -- Aadhaar, PAN, bank accounts, selfies and emergency contacts are deliberately excluded.
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  employee_id uuid not null references public.employees(id),
  shift_name text not null,
  shift_date date not null,
  punch_in timestamptz,
  punch_out timestamptz,
  attendance_status text not null default 'scheduled' check (attendance_status in ('scheduled','present','late','half_day','leave','absent')),
  unique (employee_id, shift_date, shift_name)
);

create table public.customer_feedback (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  order_id uuid references public.orders(id),
  customer_id uuid references public.customers(id),
  rating integer not null check (rating between 1 and 5),
  review_text text,
  created_at timestamptz not null default now()
);

create table public.recovery_tickets (
  id uuid primary key default gen_random_uuid(),
  outlet_id text not null references public.outlets(id),
  feedback_id uuid not null references public.customer_feedback(id),
  assigned_manager uuid references public.profiles(id),
  status text not null default 'open' check (status in ('open','in_progress','resolved')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index orders_outlet_status_idx on public.orders(outlet_id,status,opened_at desc);
create index balances_outlet_idx on public.inventory_balances(outlet_id,ingredient_id);
create index settlements_outlet_date_idx on public.aggregator_settlements(outlet_id,settlement_date desc);
create index feedback_outlet_date_idx on public.customer_feedback(outlet_id,created_at desc);

-- Enable row-level security on every tenant/business table.
do $$ declare t text; begin
  foreach t in array array['outlets','profiles','menu_items','outlet_menu_stock','customers','orders','order_items','ingredients','recipe_bom','inventory_balances','vendors','purchase_orders','purchase_order_lines','stock_movements','stock_indents','stock_transfers','wastage_logs','operating_expenses','cash_closings','aggregator_settlements','employees','attendance','customer_feedback','recovery_tickets'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

create policy outlets_read_scope on public.outlets for select to authenticated
  using (public.current_role() = 'owner' or id = public.current_outlet_id() or (public.current_role() = 'purchase_manager' and id = 'CK'));
create policy outlets_owner_write on public.outlets for all to authenticated
  using (public.current_role() = 'owner') with check (public.current_role() = 'owner');

create policy profiles_owner_read on public.profiles for select to authenticated
  using (public.current_role() = 'owner' or id = auth.uid());
create policy profiles_owner_write on public.profiles for all to authenticated
  using (public.current_role() = 'owner') with check (public.current_role() = 'owner');

create policy menu_read on public.menu_items for select to authenticated using (true);
create policy menu_owner_write on public.menu_items for all to authenticated
  using (public.current_role() = 'owner') with check (public.current_role() = 'owner');
create policy menu_stock_read on public.outlet_menu_stock for select to authenticated using (public.can_access_outlet(outlet_id));
create policy menu_stock_write on public.outlet_menu_stock for all to authenticated
  using (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));

create policy orders_read_scope on public.orders for select to authenticated using (public.can_access_outlet(outlet_id));
create policy orders_create_scope on public.orders for insert to authenticated
  with check (public.current_role() in ('owner','outlet_manager','cashier') and public.can_access_outlet(outlet_id));
create policy orders_update_scope on public.orders for update to authenticated
  using (public.current_role() in ('owner','outlet_manager','cashier') and public.can_access_outlet(outlet_id))
  with check (public.current_role() in ('owner','outlet_manager','cashier') and public.can_access_outlet(outlet_id));
create policy order_items_scope on public.order_items for all to authenticated
  using (public.can_access_outlet(outlet_id) and public.current_role() in ('owner','outlet_manager','cashier'))
  with check (public.can_access_outlet(outlet_id) and public.current_role() in ('owner','outlet_manager','cashier'));

create policy inventory_balance_read on public.inventory_balances for select to authenticated
  using (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy inventory_balance_write on public.inventory_balances for all to authenticated
  using (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy stock_movements_read on public.stock_movements for select to authenticated using (public.can_access_outlet(outlet_id));
create policy stock_movements_insert on public.stock_movements for insert to authenticated
  with check (public.current_role() in ('owner','purchase_manager','outlet_manager') and public.can_access_outlet(outlet_id));
create policy stock_indents_scope on public.stock_indents for all to authenticated
  using (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy stock_transfers_scope on public.stock_transfers for all to authenticated
  using (public.current_role() = 'owner' or (public.current_role() = 'purchase_manager' and (source_outlet_id = 'CK' or destination_outlet_id = 'CK')) or (public.current_role() = 'outlet_manager' and (source_outlet_id = public.current_outlet_id() or destination_outlet_id = public.current_outlet_id())))
  with check (public.current_role() = 'owner' or (public.current_role() = 'purchase_manager' and (source_outlet_id = 'CK' or destination_outlet_id = 'CK')) or (public.current_role() = 'outlet_manager' and (source_outlet_id = public.current_outlet_id() or destination_outlet_id = public.current_outlet_id()));
create policy wastage_scope on public.wastage_logs for all to authenticated
  using (public.current_role() = 'owner' or (public.current_role() in ('outlet_manager','purchase_manager') and public.can_access_outlet(outlet_id)))
  with check (public.current_role() = 'owner' or (public.current_role() in ('outlet_manager','purchase_manager') and public.can_access_outlet(outlet_id)));
create policy expenses_scope on public.operating_expenses for all to authenticated
  using (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy inventory_catalog_read on public.ingredients for select to authenticated using (auth.uid() is not null);
create policy inventory_catalog_write on public.ingredients for all to authenticated
  using (public.current_role() in ('owner','purchase_manager')) with check (public.current_role() in ('owner','purchase_manager'));
create policy recipe_read on public.recipe_bom for select to authenticated using (auth.uid() is not null);
create policy recipe_owner_write on public.recipe_bom for all to authenticated
  using (public.current_role() = 'owner') with check (public.current_role() = 'owner');

create policy vendor_purchase_read on public.vendors for select to authenticated using (public.current_role() in ('owner','purchase_manager'));
create policy vendor_purchase_write on public.vendors for all to authenticated
  using (public.current_role() in ('owner','purchase_manager')) with check (public.current_role() in ('owner','purchase_manager'));
create policy purchase_orders_read on public.purchase_orders for select to authenticated
  using (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy purchase_orders_write on public.purchase_orders for all to authenticated
  using (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy po_lines_scope on public.purchase_order_lines for all to authenticated
  using (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() in ('owner','purchase_manager') or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));

create policy customers_read on public.customers for select to authenticated
  using (public.current_role() in ('owner','outlet_manager','cashier'));
create policy customers_write on public.customers for all to authenticated
  using (public.current_role() in ('owner','outlet_manager','cashier')) with check (public.current_role() in ('owner','outlet_manager','cashier'));
create policy cash_close_scope on public.cash_closings for all to authenticated
  using (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy settlement_owner_read on public.aggregator_settlements for select to authenticated using (public.current_role() = 'owner');
create policy settlement_owner_write on public.aggregator_settlements for all to authenticated
  using (public.current_role() = 'owner') with check (public.current_role() = 'owner');

create policy employee_read_scope on public.employees for select to authenticated
  using (public.current_role() = 'owner' or (public.current_role() in ('outlet_manager','purchase_manager') and public.can_access_outlet(outlet_id)));
create policy employee_write_scope on public.employees for all to authenticated
  using (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy attendance_scope on public.attendance for all to authenticated
  using (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy feedback_read_scope on public.customer_feedback for select to authenticated using (public.can_access_outlet(outlet_id));
create policy feedback_create_scope on public.customer_feedback for insert to authenticated
  with check (public.current_role() in ('owner','outlet_manager','cashier') and public.can_access_outlet(outlet_id));
create policy recovery_read_scope on public.recovery_tickets for select to authenticated
  using (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));
create policy recovery_update_scope on public.recovery_tickets for update to authenticated
  using (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()))
  with check (public.current_role() = 'owner' or (public.current_role() = 'outlet_manager' and outlet_id = public.current_outlet_id()));

-- Production TODOs: add a separate transfer workflow with paired stock movements,
-- an audited single-use invoice-sequence RPC, server-only webhook ingestion,
-- notification delivery, consent history, and policy tests before launch.
