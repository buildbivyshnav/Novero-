-- ============================================================
-- Novero: schema + RLS + secure order function
-- Run once in Supabase > SQL Editor > New query > Run.
-- ============================================================
create extension if not exists pgcrypto;

-- ---------- Tables ----------
create table public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text, phone text, email text,
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table public.categories(
  id uuid primary key default gen_random_uuid(),
  name text not null unique, slug text not null unique, image_url text,
  is_active boolean not null default true, created_at timestamptz not null default now());

create table public.products(
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 200),
  description text,
  category_id uuid references public.categories(id) on delete set null,
  price numeric(10,2) not null check (price > 0),
  discount_percent int not null default 0 check (discount_percent between 0 and 90),
  images text[] not null default '{}',
  sizes text[] not null default '{}', colors text[] not null default '{}',
  stock int not null default 0 check (stock >= 0),
  rating numeric(2,1) not null default 0, review_count int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index on public.products(category_id);
create index on public.products(created_at desc);
create index on public.products(lower(name));

create table public.cart_items(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity int not null default 1 check (quantity between 1 and 20),
  size text, color text, created_at timestamptz not null default now());
create unique index cart_unique on public.cart_items(user_id, product_id, coalesce(size,''), coalesce(color,''));

create table public.wishlist_items(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(), unique(user_id, product_id));

create table public.addresses(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  full_name text not null, phone text not null check (phone ~ '^[6-9][0-9]{9}$'),
  address_line text not null, city text not null, state text not null,
  pincode text not null check (pincode ~ '^[1-9][0-9]{5}$'),
  is_default boolean not null default false, created_at timestamptz not null default now());
create index on public.addresses(user_id);

create table public.coupons(
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code = upper(code)),
  discount_type text not null check (discount_type in ('percent','flat')),
  discount_value numeric(10,2) not null check (discount_value > 0),
  max_discount numeric(10,2), min_order numeric(10,2) not null default 0,
  usage_limit int, used_count int not null default 0,
  valid_from timestamptz not null default now(), valid_until timestamptz,
  is_active boolean not null default true, created_at timestamptz not null default now());

create table public.orders(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  request_id uuid not null unique,               -- blocks duplicate submissions
  subtotal numeric(10,2) not null, discount numeric(10,2) not null default 0,
  delivery_fee numeric(10,2) not null default 0, total numeric(10,2) not null,
  coupon_code text,
  payment_method text not null default 'cod' check (payment_method in ('cod')),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','failed','refunded')),
  status text not null default 'placed' check (status in ('placed','confirmed','packed','shipped','out_for_delivery','delivered','cancelled')),
  ship_name text not null, ship_phone text not null, ship_address text not null,
  ship_city text not null, ship_state text not null, ship_pincode text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index on public.orders(user_id, created_at desc);

create table public.order_items(
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null, image_url text, size text, color text,
  quantity int not null check (quantity > 0),
  unit_price numeric(10,2) not null);
create index on public.order_items(order_id);

create table public.reviews(
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text check (char_length(comment) <= 1000),
  created_at timestamptz not null default now(), unique(product_id, user_id));

-- ---------- Helper functions & triggers ----------
create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as
$$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin') $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data->>'full_name');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
create trigger t_prof before update on public.profiles for each row execute function public.touch_updated_at();
create trigger t_prod before update on public.products for each row execute function public.touch_updated_at();
create trigger t_ord  before update on public.orders   for each row execute function public.touch_updated_at();

create or replace function public.refresh_rating() returns trigger
language plpgsql security definer set search_path = public as $$
declare pid uuid := coalesce(new.product_id, old.product_id);
begin
  update public.products set
    rating = coalesce((select round(avg(rating)::numeric,1) from public.reviews where product_id = pid),0),
    review_count = (select count(*) from public.reviews where product_id = pid)
  where id = pid;
  return null;
end $$;
create trigger t_rating after insert or update or delete on public.reviews
  for each row execute function public.refresh_rating();

-- ---------- Row Level Security ----------
alter table public.profiles       enable row level security;
alter table public.categories     enable row level security;
alter table public.products       enable row level security;
alter table public.cart_items     enable row level security;
alter table public.wishlist_items enable row level security;
alter table public.addresses      enable row level security;
alter table public.coupons        enable row level security;
alter table public.orders         enable row level security;
alter table public.order_items    enable row level security;
alter table public.reviews        enable row level security;

-- profiles: own row; customers can edit only name/phone (role is locked by column grants)
create policy prof_sel on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy prof_upd on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- catalog: public reads active items, admins manage everything
create policy cat_sel on public.categories for select using (is_active or public.is_admin());
create policy cat_adm on public.categories for all using (public.is_admin()) with check (public.is_admin());
create policy prod_sel on public.products for select using (is_active or public.is_admin());
create policy prod_adm on public.products for all using (public.is_admin()) with check (public.is_admin());

-- personal data: owner only
create policy cart_own on public.cart_items     for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy wish_own on public.wishlist_items for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy addr_own on public.addresses      for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- orders: read own; NO direct insert/delete (only place_order()); admins update fulfilment
create policy ord_sel on public.orders for select using (user_id = auth.uid() or public.is_admin());
create policy ord_adm on public.orders for update using (public.is_admin()) with check (public.is_admin());
create policy oi_sel on public.order_items for select using (
  public.is_admin() or exists(select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

-- reviews: public read, write own
create policy rev_sel on public.reviews for select using (true);
create policy rev_ins on public.reviews for insert with check (user_id = auth.uid());
create policy rev_upd on public.reviews for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy rev_del on public.reviews for delete using (user_id = auth.uid() or public.is_admin());

-- coupons: admin only (customers are validated inside place_order)
create policy cpn_adm on public.coupons for all using (public.is_admin()) with check (public.is_admin());

-- ---------- Secure order creation ----------
-- Browser sends only: address, optional coupon code, and a unique request id.
-- Prices, stock, discount, totals and payment status are all decided here.
create or replace function public.place_order(
  p_name text, p_phone text, p_address text, p_city text, p_state text, p_pincode text,
  p_coupon text, p_request_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); oid uuid; r record; c record;
  sub numeric := 0; disc numeric := 0; fee numeric := 0; unit numeric;
begin
  if uid is null then raise exception 'Please log in to place an order'; end if;
  if p_request_id is null then raise exception 'Missing request id'; end if;
  select id into oid from orders where request_id = p_request_id and user_id = uid;
  if oid is not null then return oid; end if;                      -- duplicate click: same order
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_address),'') = ''
     or coalesce(trim(p_city),'') = '' or coalesce(trim(p_state),'') = '' then
    raise exception 'Please fill in all address fields'; end if;
  if p_phone !~ '^[6-9][0-9]{9}$' then raise exception 'Enter a valid 10-digit mobile number'; end if;
  if p_pincode !~ '^[1-9][0-9]{5}$' then raise exception 'Enter a valid 6-digit PIN code'; end if;

  -- lock products, validate stock, compute subtotal from DB prices
  for r in select ci.quantity, p.id, p.price, p.discount_percent, p.stock, p.is_active, p.name
           from cart_items ci join products p on p.id = ci.product_id
           where ci.user_id = uid order by p.id for update of p loop
    if not r.is_active then raise exception '% is no longer available', r.name; end if;
    if r.stock < r.quantity then raise exception 'Only % left of %', r.stock, r.name; end if;
    sub := sub + round(r.price * (100 - r.discount_percent) / 100) * r.quantity;
  end loop;
  if sub = 0 then raise exception 'Your cart is empty'; end if;

  if p_coupon is not null and trim(p_coupon) <> '' then
    select * into c from coupons where code = upper(trim(p_coupon)) and is_active
      and valid_from <= now() and (valid_until is null or valid_until > now())
      and (usage_limit is null or used_count < usage_limit) for update;
    if not found then raise exception 'This coupon is invalid or has expired'; end if;
    if sub < c.min_order then raise exception 'Add items worth Rs. % to use this coupon', c.min_order; end if;
    disc := case when c.discount_type = 'percent' then round(sub * c.discount_value / 100) else c.discount_value end;
    if c.max_discount is not null then disc := least(disc, c.max_discount); end if;
    disc := least(disc, sub);
    update coupons set used_count = used_count + 1 where id = c.id;
  end if;

  fee := case when sub - disc >= 499 then 0 else 49 end;           -- free delivery from Rs. 499

  insert into orders(user_id, request_id, subtotal, discount, delivery_fee, total, coupon_code,
    ship_name, ship_phone, ship_address, ship_city, ship_state, ship_pincode)
  values (uid, p_request_id, sub, disc, fee, sub - disc + fee, upper(nullif(trim(p_coupon),'')),
    trim(p_name), p_phone, trim(p_address), trim(p_city), trim(p_state), p_pincode)
  returning id into oid;

  for r in select ci.quantity, ci.size, ci.color, p.id, p.name, p.price, p.discount_percent, p.images[1] as img
           from cart_items ci join products p on p.id = ci.product_id where ci.user_id = uid loop
    unit := round(r.price * (100 - r.discount_percent) / 100);
    insert into order_items(order_id, product_id, product_name, image_url, size, color, quantity, unit_price)
    values (oid, r.id, r.name, r.img, r.size, r.color, r.quantity, unit);
    update products set stock = stock - r.quantity where id = r.id;
  end loop;

  delete from cart_items where user_id = uid;
  return oid;
end $$;
revoke all on function public.place_order(text,text,text,text,text,text,text,uuid) from public, anon;
grant execute on function public.place_order(text,text,text,text,text,text,text,uuid) to authenticated;

-- ---------- Storage: product images ----------
insert into storage.buckets(id, name, public) values ('product-images','product-images', true)
  on conflict (id) do nothing;
create policy img_read  on storage.objects for select using (bucket_id = 'product-images');
create policy img_ins   on storage.objects for insert with check (bucket_id = 'product-images' and public.is_admin());
create policy img_upd   on storage.objects for update using (bucket_id = 'product-images' and public.is_admin());
create policy img_del   on storage.objects for delete using (bucket_id = 'product-images' and public.is_admin());

-- ---------- Starter data ----------
insert into public.categories(name, slug) values
 ('Women','women'),('Men','men'),('Kids','kids'),('Home','home'),
 ('Beauty','beauty'),('Electronics','electronics'),('Footwear','footwear'),('Accessories','accessories');

-- ---------- Make yourself admin (run AFTER you register on the site) ----------
-- update public.profiles set role = 'admin' where email = 'you@example.com';
