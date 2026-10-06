create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  role text not null default 'customer' check (role in ('admin', 'customer')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, role)
  values (
    new.id,
    new.email,
    case
      when pg_catalog.lower(new.email) = 'adryelteste@gmail.com' then 'admin'
      else 'customer'
    end
  )
  on conflict (id) do update
    set email = excluded.email,
        role = excluded.role;
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update of email on auth.users
  for each row execute function public.handle_new_user();

insert into public.profiles (id, email, role)
select
  id,
  email,
  case
    when pg_catalog.lower(email) = 'adryelteste@gmail.com' then 'admin'
    else 'customer'
  end
from auth.users
where email is not null
on conflict (id) do update
  set email = excluded.email,
      role = excluded.role;

create table if not exists public.products (
  id text primary key,
  name text not null,
  price_cents integer not null check (price_cents > 0),
  stock integer not null check (stock >= 0)
);

insert into public.products (id, name, price_cents, stock) values
  ('account', 'LV 1800 + GodHuman', 500, 8),
  ('boats', 'Barcos Rápidos', 1500, 13),
  ('money', '2x Money', 1730, 5),
  ('discord-nitro', 'Conta Nitro 3 meses + 14 boosts', 1400, 1)
on conflict (id) do nothing;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  total_cents integer not null default 0 check (total_cents >= 0),
  status text not null default 'pending' check (status in ('pending', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table if not exists public.order_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id text not null references public.products (id),
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price_cents integer not null check (unit_price_cents > 0)
);

alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
revoke all on public.products, public.orders, public.order_items from anon, authenticated;
grant select on public.products to anon, authenticated;
grant select on public.orders, public.order_items to authenticated;
grant update (status, paid_at) on public.orders to authenticated;

drop policy if exists products_read on public.products;
create policy products_read on public.products for select to anon, authenticated using (true);

drop policy if exists orders_read_own_or_admin on public.orders;
create policy orders_read_own_or_admin on public.orders
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin')
  );

drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders
  for update to authenticated
  using (exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin') and status = 'pending')
  with check (exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin'));

drop policy if exists order_items_read_own_or_admin on public.order_items;
create policy order_items_read_own_or_admin on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders
      where orders.id = order_items.order_id
        and (
          orders.user_id = (select auth.uid())
          or exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin')
        )
    )
  );

create or replace function public.create_gamevault_order(p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_order_id uuid;
  v_product record;
  v_entry jsonb;
  v_quantity integer;
  v_total integer := 0;
  v_input_count integer;
  v_product_count integer;
begin
  if v_user_id is null then
    raise exception 'Entre na sua conta para continuar.';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'O carrinho está vazio.';
  end if;

  for v_entry in select value from jsonb_array_elements(p_items)
  loop
     if jsonb_typeof(v_entry -> 'id') is distinct from 'string'
       or jsonb_typeof(v_entry -> 'quantity') is distinct from 'number'
       or coalesce(v_entry ->> 'quantity', '') !~ '^[1-9][0-9]*$' then
      raise exception 'Produto ou quantidade inválida.';
    end if;
  end loop;

  select count(distinct value ->> 'id') into v_input_count
  from jsonb_array_elements(p_items);
  select count(*) into v_product_count
  from public.products p
  where p.id in (select value ->> 'id' from jsonb_array_elements(p_items));
  if v_input_count <> v_product_count then
    raise exception 'O carrinho contém um produto indisponível.';
  end if;

  insert into public.orders (user_id) values (v_user_id) returning id into v_order_id;

  for v_product in
    select p.id, p.name, p.price_cents, p.stock
    from public.products p
    where p.id in (select value ->> 'id' from jsonb_array_elements(p_items))
    order by p.id
    for update
  loop
    select sum((value ->> 'quantity')::integer)::integer into v_quantity
    from jsonb_array_elements(p_items)
    where value ->> 'id' = v_product.id;

    if v_quantity > v_product.stock then
      raise exception 'Estoque insuficiente para %.', v_product.name;
    end if;

    update public.products set stock = stock - v_quantity where id = v_product.id;
    insert into public.order_items (order_id, product_id, product_name, quantity, unit_price_cents)
    values (v_order_id, v_product.id, v_product.name, v_quantity, v_product.price_cents);
    v_total := v_total + v_product.price_cents * v_quantity;
  end loop;

  update public.orders set total_cents = v_total where id = v_order_id;
  return jsonb_build_object('id', v_order_id, 'total_cents', v_total);
end;
$$;

revoke all on function public.create_gamevault_order(jsonb) from public, anon;
grant execute on function public.create_gamevault_order(jsonb) to authenticated;

create or replace function public.cancel_gamevault_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer;
begin
  if auth.uid() is null then
    raise exception 'Entre na sua conta para cancelar o pedido.';
  end if;
  update public.orders
  set status = 'cancelled'
  where id = p_order_id
    and user_id = auth.uid()
    and status = 'pending';
  get diagnostics v_changed = row_count;
  if v_changed = 0 then
    raise exception 'O pedido não está pendente ou não pertence a esta conta.';
  end if;
  return true;
end;
$$;

revoke all on function public.cancel_gamevault_order(uuid) from public, anon;
grant execute on function public.cancel_gamevault_order(uuid) to authenticated;

create or replace function public.expire_gamevault_orders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer;
begin
  update public.orders
  set status = 'cancelled'
  where status = 'pending'
    and created_at < now() - interval '20 minutes';
  get diagnostics v_changed = row_count;
  return v_changed;
end;
$$;

revoke all on function public.expire_gamevault_orders() from public, anon;
grant execute on function public.expire_gamevault_orders() to authenticated;

create or replace function public.expire_gamevault_order()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.expire_gamevault_orders();
end;
$$;

revoke all on function public.expire_gamevault_order() from public, anon;
grant execute on function public.expire_gamevault_order() to authenticated;

create or replace function public.restore_cancelled_order_stock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'pending' and new.status = 'cancelled' then
    update public.products p
    set stock = p.stock + item.quantity
    from public.order_items item
    where item.order_id = new.id and item.product_id = p.id;
  elsif old.status = 'pending' and new.status = 'paid' then
    if old.created_at < now() - interval '20 minutes' then
      raise exception 'O prazo da reserva expirou. Este pedido não pode ser aprovado.';
    end if;
    new.paid_at := now();
  end if;
  return new;
end;
$$;

revoke all on function public.restore_cancelled_order_stock() from public, anon, authenticated;
drop trigger if exists orders_restore_stock on public.orders;
create trigger orders_restore_stock
  before update of status on public.orders
  for each row execute function public.restore_cancelled_order_stock();
