-- Run once after schema.sql has passed a security review.
-- Returns raw bearer tokens. Never paste them into GitHub, logs, or chat.
with fresh as (
 select s.store_id,s.name,encode(gen_random_bytes(32),'hex') as token
 from public.store s where s.store_id between 1 and 13
   and not exists(select 1 from pilot_private.store_links l where l.store_id=s.store_id)
), issued as (
 insert into pilot_private.store_links(store_id,token_hash,expires_at)
 select store_id,encode(extensions.digest(convert_to(token,'UTF8'),'sha256'),'hex'), now()+interval '30 days' from fresh
 returning store_id
)
select f.store_id,f.name,f.token from fresh f join issued i on i.store_id=f.store_id order by f.store_id;
