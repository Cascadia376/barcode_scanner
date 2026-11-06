-- Ursus Count pilot: isolated, bearer-token gated, shadow counts only.
-- Apply using an authorized database migration workflow. No Stellar writes.
create schema if not exists pilot_private;
revoke all on schema pilot_private from public, anon, authenticated;

create table if not exists pilot_private.store_links (
  store_id integer primary key references public.store(store_id),
  token_hash text not null unique,
  enabled boolean not null default true,
  expires_at timestamptz not null,
  issued_at timestamptz not null default now()
);
create table if not exists pilot_private.counts (
  id uuid primary key default gen_random_uuid(),
  store_id integer not null references public.store(store_id),
  name text not null check (length(name) between 1 and 100),
  status text not null default 'open' check (status in ('open','finished')),
  created_at timestamptz not null default now()
);
create index if not exists count_pilot_counts_store_idx on pilot_private.counts(store_id,created_at desc);
create table if not exists pilot_private.observations (
  id uuid primary key default gen_random_uuid(),
  count_id uuid not null references pilot_private.counts(id),
  store_id integer not null references public.store(store_id),
  sku text not null,
  quantity integer not null check (quantity between 0 and 99999),
  event_id uuid not null unique,
  created_at timestamptz not null default now()
);
create index if not exists count_pilot_obs_count_idx on pilot_private.observations(count_id,created_at desc);
create table if not exists pilot_private.corrections (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null references pilot_private.observations(id),
  new_quantity integer not null check (new_quantity between 0 and 99999),
  created_at timestamptz not null default now()
);
create index if not exists count_pilot_corrections_idx on pilot_private.corrections(observation_id,created_at desc);

alter table pilot_private.store_links enable row level security;
alter table pilot_private.counts enable row level security;
alter table pilot_private.observations enable row level security;
alter table pilot_private.corrections enable row level security;
revoke all on all tables in schema pilot_private from public, anon, authenticated;

create or replace function pilot_private.authorized_store(p_token text)
returns integer language sql stable security definer set search_path = '' as $$
  select store_id from pilot_private.store_links
  where token_hash = encode(extensions.digest(convert_to(p_token,'UTF8'),'sha256'),'hex')
    and enabled and expires_at > now()
    and length(p_token) = 64
  limit 1
$$;
revoke all on function pilot_private.authorized_store(text) from public, anon, authenticated;

create or replace function public.count_pilot_store(p_token text)
returns table(store_id integer,store_name text) language sql stable security definer set search_path = '' as $$
  select s.store_id,s.name from public.store s
  where s.store_id = pilot_private.authorized_store(p_token) and s.store_id between 1 and 13
$$;

create or replace function public.count_pilot_sessions(p_token text)
returns table(id uuid,name text,status text,created_at timestamptz) language sql stable security definer set search_path = '' as $$
  select c.id,c.name,c.status,c.created_at from pilot_private.counts c
  where c.store_id=pilot_private.authorized_store(p_token)
  order by c.created_at desc limit 40
$$;

create or replace function public.count_pilot_start(p_token text,p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare sid integer; cid uuid;
begin
  sid:=pilot_private.authorized_store(p_token);
  if sid is null or sid not between 1 and 13 then raise exception 'Unauthorized' using errcode='28000'; end if;
  if length(btrim(p_name)) not between 1 and 100 then raise exception 'Invalid count name'; end if;
  insert into pilot_private.counts(store_id,name) values(sid,btrim(p_name)) returning id into cid;
  return cid;
end $$;

create or replace function public.count_pilot_lookup(p_token text,p_query text)
returns table(sku text,product_name text,category text,stock_unit text) language plpgsql stable security definer set search_path = '' as $$
declare sid integer; cleaned text;
begin
  sid:=pilot_private.authorized_store(p_token);
  if sid is null or sid not between 1 and 13 then raise exception 'Unauthorized' using errcode='28000'; end if;
  cleaned:=left(btrim(p_query),120);
  if length(cleaned)<2 then return; end if;
  return query
  select c.sku,c.product_name,c.category,'selling units'::text
  from public.inventory_cost_daily c
  where c.store_id=sid
    and c.snapshot_date=(select max(d.snapshot_date) from public.inventory_cost_daily d where d.store_id=sid)
    and (c.sku=cleaned or c.sku in (select pb.sku from public.productbarcode pb where pb.barcode=cleaned and pb.is_active))
  order by c.sku limit 3;
  if found then return; end if;
  return query
  select c.sku,c.product_name,c.category,'selling units'::text
  from public.inventory_cost_daily c
  where c.store_id=sid
    and c.snapshot_date=(select max(d.snapshot_date) from public.inventory_cost_daily d where d.store_id=sid)
    and (c.product_name ilike '%' || cleaned || '%' or c.sku ilike '%' || cleaned || '%')
  order by c.product_name limit 15;
end $$;

create or replace function public.count_pilot_observe(p_token text,p_count_id uuid,p_sku text,p_quantity integer,p_event_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare sid integer; oid uuid;
begin
  sid:=pilot_private.authorized_store(p_token);
  if sid is null or sid not between 1 and 13 then raise exception 'Unauthorized' using errcode='28000'; end if;
  if p_quantity is null or p_quantity not between 0 and 99999 then raise exception 'Invalid quantity'; end if;
  if p_event_id is null then raise exception 'Missing event ID'; end if;
  if not exists (select 1 from pilot_private.counts c where c.id=p_count_id and c.store_id=sid and c.status='open') then raise exception 'Count unavailable'; end if;
  if not exists (select 1 from public.inventory_cost_daily c where c.store_id=sid and c.sku=p_sku and c.snapshot_date=(select max(d.snapshot_date) from public.inventory_cost_daily d where d.store_id=sid)) then raise exception 'SKU not in current store catalog'; end if;
  insert into pilot_private.observations(count_id,store_id,sku,quantity,event_id)
  values (p_count_id,sid,p_sku,p_quantity,p_event_id)
  on conflict(event_id) do nothing returning id into oid;
  if oid is null then
    select id into oid from pilot_private.observations where event_id=p_event_id and store_id=sid and count_id=p_count_id and sku=p_sku and quantity=p_quantity;
    if oid is null then raise exception 'Event ID conflict'; end if;
  end if;
  return oid;
end $$;

create or replace function public.count_pilot_history(p_token text,p_count_id uuid)
returns table(id uuid,sku text,product_name text,original_quantity integer,quantity integer,created_at timestamptz,correction_count bigint)
language plpgsql stable security definer set search_path = '' as $$
declare sid integer;
begin
  sid:=pilot_private.authorized_store(p_token);
  if sid is null or sid not between 1 and 13 then raise exception 'Unauthorized' using errcode='28000'; end if;
  return query
  select o.id,o.sku,coalesce((select c.product_name from public.inventory_cost_daily c where c.store_id=sid and c.sku=o.sku order by c.snapshot_date desc limit 1),o.sku),
         o.quantity,coalesce((select r.new_quantity from pilot_private.corrections r where r.observation_id=o.id order by r.created_at desc,r.id desc limit 1),o.quantity),o.created_at,
         (select count(*) from pilot_private.corrections x where x.observation_id=o.id)
  from pilot_private.observations o join pilot_private.counts ct on ct.id=o.count_id
  where o.count_id=p_count_id and o.store_id=sid and ct.store_id=sid
  order by o.created_at desc limit 5000;
end $$;

create or replace function public.count_pilot_correct(p_token text,p_observation_id uuid,p_quantity integer)
returns uuid language plpgsql security definer set search_path = '' as $$
declare sid integer; rid uuid;
begin
  sid:=pilot_private.authorized_store(p_token);
  if sid is null or sid not between 1 and 13 then raise exception 'Unauthorized' using errcode='28000'; end if;
  if p_quantity is null or p_quantity not between 0 and 99999 then raise exception 'Invalid quantity'; end if;
  if not exists(select 1 from pilot_private.observations o join pilot_private.counts c on c.id=o.count_id where o.id=p_observation_id and o.store_id=sid and c.store_id=sid and c.status='open') then raise exception 'Observation unavailable'; end if;
  insert into pilot_private.corrections(observation_id,new_quantity) values (p_observation_id,p_quantity) returning id into rid;
  return rid;
end $$;

create or replace function public.count_pilot_finish(p_token text,p_count_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare sid integer;
begin
  sid:=pilot_private.authorized_store(p_token);
  if sid is null or sid not between 1 and 13 then raise exception 'Unauthorized' using errcode='28000'; end if;
  update pilot_private.counts set status='finished' where id=p_count_id and store_id=sid and status='open';
  return found;
end $$;

-- Only explicit, token-checked RPCs are accessible to the browser.
revoke all on function public.count_pilot_store(text) from public;
revoke all on function public.count_pilot_sessions(text) from public;
revoke all on function public.count_pilot_start(text,text) from public;
revoke all on function public.count_pilot_lookup(text,text) from public;
revoke all on function public.count_pilot_observe(text,uuid,text,integer,uuid) from public;
revoke all on function public.count_pilot_history(text,uuid) from public;
revoke all on function public.count_pilot_correct(text,uuid,integer) from public;
revoke all on function public.count_pilot_finish(text,uuid) from public;
grant execute on function public.count_pilot_store(text),public.count_pilot_sessions(text),public.count_pilot_start(text,text),public.count_pilot_lookup(text,text),public.count_pilot_observe(text,uuid,text,integer,uuid),public.count_pilot_history(text,uuid),public.count_pilot_correct(text,uuid,integer),public.count_pilot_finish(text,uuid) to anon;
