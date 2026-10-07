-- =====================================================================
-- Quản lý Thiết bị IT — v2 (Supabase)
-- Chạy toàn bộ file này một lần trong Supabase → SQL Editor → New query.
-- =====================================================================

create extension if not exists pg_trgm;

-- ---------- Admin ----------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- Thiết bị --------------------------------------------------
create table if not exists public.devices (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  name          text not null,
  type          text not null default 'other'
                check (type in ('laptop','desktop','monitor','printer','network','phone','server','other')),
  serial        text,
  status        text not null default 'available'
                check (status in ('in_use','available','repair','retired')),
  prev_status   text,
  assignee      text,
  dept          text,
  location      text,
  price         bigint not null default 0 check (price >= 0),
  purchase_date date,
  warranty_end  date,
  notes         text,
  search        text generated always as (
                  lower(code || ' ' || name || ' ' || coalesce(serial,'') || ' ' ||
                        coalesce(assignee,'') || ' ' || coalesce(dept,'') || ' ' || coalesce(location,''))
                ) stored,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (warranty_end is null or purchase_date is null or warranty_end >= purchase_date)
);

create index if not exists devices_search_trgm on public.devices using gin (search gin_trgm_ops);
create index if not exists devices_status_idx   on public.devices (status);
create index if not exists devices_type_idx     on public.devices (type);
create index if not exists devices_dept_idx     on public.devices (dept);
create index if not exists devices_assignee_idx on public.devices (assignee);
create index if not exists devices_name_idx     on public.devices (name);
create index if not exists devices_warranty_idx on public.devices (warranty_end);
create index if not exists devices_price_idx    on public.devices (price);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists devices_touch on public.devices;
create trigger devices_touch before update on public.devices
  for each row execute function public.touch_updated_at();

-- ---------- Bảo trì ---------------------------------------------------
create table if not exists public.maintenance (
  id         uuid primary key default gen_random_uuid(),
  device_id  uuid not null references public.devices(id) on delete cascade,
  date       date not null default current_date,
  descr      text not null,
  cost       bigint not null default 0 check (cost >= 0),
  vendor     text,
  status     text not null default 'open' check (status in ('open','done')),
  created_at timestamptz not null default now()
);
create index if not exists maintenance_device_idx on public.maintenance (device_id);
create index if not exists maintenance_status_idx on public.maintenance (status, date desc);

-- Có phiếu đang mở → thiết bị chuyển "Đang sửa"; hết phiếu mở → trả lại trạng thái cũ.
create or replace function public.sync_device_repair()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare did uuid := coalesce(new.device_id, old.device_id);
begin
  if exists (select 1 from maintenance where device_id = did and status = 'open') then
    update devices set prev_status = status, status = 'repair'
     where id = did and status not in ('repair','retired');
  else
    update devices
       set status = coalesce(prev_status, case when coalesce(assignee,'') <> '' then 'in_use' else 'available' end),
           prev_status = null
     where id = did and status = 'repair';
  end if;
  return null;
end $$;

drop trigger if exists maintenance_sync on public.maintenance;
create trigger maintenance_sync after insert or update or delete on public.maintenance
  for each row execute function public.sync_device_repair();

-- ---------- Phân quyền (Row Level Security) ---------------------------
alter table public.devices     enable row level security;
alter table public.maintenance enable row level security;
alter table public.admins      enable row level security;

drop policy if exists "Ai cũng xem được thiết bị" on public.devices;
create policy "Ai cũng xem được thiết bị" on public.devices for select using (true);
drop policy if exists "Admin sửa thiết bị" on public.devices;
create policy "Admin sửa thiết bị" on public.devices for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Ai cũng xem được bảo trì" on public.maintenance;
create policy "Ai cũng xem được bảo trì" on public.maintenance for select using (true);
drop policy if exists "Admin sửa bảo trì" on public.maintenance;
create policy "Admin sửa bảo trì" on public.maintenance for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Xem quyền của chính mình" on public.admins;
create policy "Xem quyền của chính mình" on public.admins for select to authenticated
  using (user_id = auth.uid());

-- ---------- Hàm cho giao diện -----------------------------------------
create or replace function public.dashboard_stats()
returns json language sql stable
set search_path = public
as $$
  select json_build_object(
    'total',     (select count(*) from devices),
    'by_status', (select coalesce(json_object_agg(status, n), '{}'::json)
                    from (select status, count(*) n from devices group by status) s),
    'by_type',   (select coalesce(json_object_agg(type, n), '{}'::json)
                    from (select type, count(*) n from devices where status <> 'retired' group by type) s),
    'by_dept',   (select coalesce(json_agg(json_build_object('dept', dept, 'n', n) order by n desc), '[]'::json)
                    from (select coalesce(nullif(dept,''),'—') dept, count(*) n from devices
                           where status <> 'retired' group by 1 order by 2 desc limit 8) s),
    'value',     (select coalesce(sum(price),0) from devices where status <> 'retired'),
    'expiring',  (select count(*) from devices where status <> 'retired'
                     and warranty_end between current_date and current_date + 90),
    'expired',   (select count(*) from devices where status <> 'retired' and warranty_end < current_date),
    'open_mt',   (select count(*) from maintenance where status = 'open'),
    'done_mt',   (select count(*) from maintenance where status = 'done'),
    'mt_cost_year', (select coalesce(sum(cost),0) from maintenance
                      where date >= date_trunc('year', current_date))
  );
$$;

create or replace function public.list_depts()
returns setof text language sql stable
set search_path = public
as $$
  select distinct dept from devices where coalesce(dept,'') <> '' order by 1 limit 300;
$$;

create or replace function public.people_summary(p_search text default '', p_limit int default 24, p_offset int default 0)
returns table (assignee text, dept text, n bigint, total bigint)
language sql stable
set search_path = public
as $$
  with g as (
    select d.assignee, min(d.dept) dept, count(*) n
      from devices d
     where d.status <> 'retired' and coalesce(d.assignee,'') <> ''
       and (coalesce(p_search,'') = '' or lower(d.assignee) like '%' || lower(p_search) || '%')
     group by d.assignee
  )
  select g.assignee, g.dept, g.n, count(*) over () as total
    from g order by g.assignee
   limit least(greatest(p_limit,1),100) offset greatest(p_offset,0);
$$;

-- Tạo dữ liệu thử (chỉ admin). Gọi nhiều lần, mỗi lần tối đa 10.000 dòng.
create or replace function public.seed_demo(n int default 1000)
returns int language plpgsql security definer
set search_path = public
as $$
declare start_no int;
begin
  if not public.is_admin() then raise exception 'Chỉ admin được tạo dữ liệu thử'; end if;
  n := least(greatest(n,1), 10000);
  select coalesce(max(substring(code from '^DEMO-(\d+)$')::int), 0) into start_no
    from devices where code like 'DEMO-%';
  insert into devices (code, name, type, serial, status, assignee, dept, location, price, purchase_date, warranty_end)
  select 'DEMO-' || lpad((start_no + i)::text, 7, '0'),
         m.name, m.type,
         upper(substr(md5(random()::text), 1, 12)),
         st,
         case when st in ('in_use','repair') then
           (array['Nguyễn','Trần','Lê','Phạm','Hoàng','Vũ','Võ','Đặng','Bùi','Đỗ'])[1 + (i*7) % 10] || ' ' ||
           (array['Văn','Thị','Minh','Quốc','Thu','Đức','Hoàng','Lan'])[1 + (i*3) % 8] || ' ' ||
           (array['An','Bình','Cường','Dũng','Hà','Huy','Long','Mai','Nam','Phương','Quân','Trang'])[1 + (i/7) % 12] ||
           ' ' || (i % 5000)
         end,
         (array['Kỹ thuật','Kế toán','Kinh doanh','Nhân sự','Marketing','Hành chính','Pháp chế','Chăm sóc KH'])[1 + i % 8],
         (array['Văn phòng HN','Văn phòng HCM','Văn phòng ĐN','Kho IT'])[1 + i % 4],
         m.price,
         current_date - (i % 1500),
         current_date - (i % 1500) + 365 * (1 + i % 3)
    from generate_series(1, n) i
    cross join lateral (
      select (array['in_use','in_use','in_use','in_use','available','repair','retired'])[1 + (i*13) % 7] as st
    ) s
    cross join lateral (
      select * from (values
        (0,'Dell Latitude 7440','laptop',28500000),(1,'MacBook Pro 14 M3','laptop',45900000),
        (2,'Lenovo ThinkPad T14','laptop',24900000),(3,'HP EliteBook 840 G10','laptop',27200000),
        (4,'Dell UltraSharp U2723QE','monitor',13900000),(5,'LG 27UP850','monitor',9800000),
        (6,'Dell OptiPlex 7010','desktop',16500000),(7,'iPhone 15','phone',22900000),
        (8,'HP LaserJet Pro M404dn','printer',8900000),(9,'Cisco Catalyst 9200-24P','network',62000000),
        (10,'Ubiquiti UniFi U6 Pro','network',4200000),(11,'Dell PowerEdge R650','server',185000000)
      ) v(k, name, type, price) where v.k = i % 12
    ) m;
  return n;
end $$;

-- Xoá dữ liệu thử (chỉ admin). Gọi lặp lại đến khi trả về 0.
create or replace function public.delete_demo(batch int default 20000)
returns int language plpgsql security definer
set search_path = public
as $$
declare c int;
begin
  if not public.is_admin() then raise exception 'Chỉ admin được xoá dữ liệu thử'; end if;
  delete from devices where id in (select id from devices where code like 'DEMO-%' limit least(greatest(batch,1),20000));
  get diagnostics c = row_count;
  return c;
end $$;

revoke execute on function public.seed_demo(int)   from anon;
revoke execute on function public.delete_demo(int) from anon;

-- ---------- Dữ liệu mẫu (chỉ chèn khi bảng còn trống) ------------------
do $$
begin
  if exists (select 1 from public.devices) then return; end if;

  insert into public.devices (code, type, name, status, assignee, dept, location, price, purchase_date, warranty_end) values
  ('LT-001','laptop','Dell Latitude 7440','in_use','Nguyễn Văn An','Kỹ thuật','Văn phòng HN',28500000,current_date-620,current_date+475),
  ('LT-002','laptop','MacBook Pro 14 M3','in_use','Lê Hoàng Cường','Kỹ thuật','Văn phòng HN',45900000,current_date-300,current_date+60),
  ('LT-003','laptop','Lenovo ThinkPad T14','in_use','Trần Thị Bình','Kế toán','Văn phòng HN',24900000,current_date-900,current_date-170),
  ('LT-004','laptop','HP EliteBook 840 G10','in_use','Phạm Minh Dũng','Kinh doanh','Văn phòng HN',27200000,current_date-200,current_date+530),
  ('LT-005','laptop','Dell Latitude 5440','available',null,'Kho IT','Kho IT',19800000,current_date-150,current_date+580),
  ('LT-006','laptop','ASUS ExpertBook B9','in_use','Đặng Quốc Huy','Kinh doanh','Văn phòng HN',32000000,current_date-500,current_date+40),
  ('LT-007','laptop','MacBook Air 13 M2','in_use','Bùi Lan Anh','Marketing','Văn phòng HN',26900000,current_date-420,current_date+310),
  ('LT-008','laptop','Lenovo ThinkPad X1 Carbon','in_use','Hoàng Đức Long','Kỹ thuật','Văn phòng HN',39500000,current_date-80,current_date+1010),
  ('PC-001','desktop','Dell OptiPlex 7010','in_use','Trần Thị Bình','Kế toán','Văn phòng HN',16500000,current_date-700,current_date+30),
  ('PC-002','desktop','HP ProDesk 400 G9','in_use','Võ Thu Hà','Nhân sự','Văn phòng HN',14200000,current_date-640,current_date+90),
  ('PC-003','desktop','Dell OptiPlex 3000','retired',null,'Kho IT','Kho IT',12000000,current_date-1900,current_date-1170),
  ('MN-001','monitor','Dell UltraSharp U2723QE','in_use','Nguyễn Văn An','Kỹ thuật','Văn phòng HN',13900000,current_date-610,current_date+485),
  ('MN-002','monitor','LG 27UP850','in_use','Lê Hoàng Cường','Kỹ thuật','Văn phòng HN',9800000,current_date-300,current_date+795),
  ('MN-003','monitor','Samsung S24C450','available',null,'Kho IT','Kho IT',3900000,current_date-90,current_date+640),
  ('MN-004','monitor','Dell P2422H','in_use','Phạm Minh Dũng','Kinh doanh','Văn phòng HN',4500000,current_date-1000,current_date+95),
  ('PR-001','printer','HP LaserJet Pro M404dn','in_use',null,'Kế toán','Tầng 2 - P.Kế toán',8900000,current_date-800,current_date-70),
  ('PR-002','printer','Canon imageRUNNER 2630i','available',null,'Hành chính','Tầng 1 - Sảnh',58000000,current_date-400,current_date+330),
  ('NW-001','network','Cisco Catalyst 9200-24P','in_use',null,'Kỹ thuật','Phòng server',62000000,current_date-720,current_date+10),
  ('NW-002','network','Ubiquiti UniFi U6 Pro','in_use',null,'Hành chính','Tầng 3',4200000,current_date-250,current_date+480),
  ('NW-003','network','FortiGate 60F','in_use',null,'Kỹ thuật','Phòng server',21500000,current_date-540,current_date+190),
  ('SV-001','server','Dell PowerEdge R650','in_use',null,'Kỹ thuật','Phòng server',185000000,current_date-680,current_date+1145),
  ('PH-001','phone','iPhone 15','in_use','Phạm Minh Dũng','Kinh doanh','Văn phòng HN',22900000,current_date-330,current_date+35),
  ('PH-002','phone','Samsung Galaxy S24','available',null,'Kho IT','Kho IT',19900000,current_date-60,current_date+670),
  ('PH-003','phone','Yealink T54W (IP Phone)','in_use','Đặng Quốc Huy','Kinh doanh','Văn phòng HN',3500000,current_date-700,current_date+30);

  insert into public.maintenance (device_id, date, descr, cost, vendor, status)
  select d.id, current_date + m.off, m.descr, m.cost, m.vendor, m.status
    from (values
      ('LT-006',-4,'Thay bàn phím, lỗi phím Enter',1200000,'ASUS Service','open'),
      ('PR-002',-2,'Kẹt giấy, thay trục kéo giấy',2500000,'Canon VN','open'),
      ('LT-003',-45,'Vệ sinh, thay keo tản nhiệt',350000,'Nội bộ','done'),
      ('PC-001',-80,'Nâng cấp RAM 16GB → 32GB',1400000,'Nội bộ','done'),
      ('NW-001',-120,'Cập nhật firmware IOS-XE',0,'Nội bộ','done'),
      ('LT-001',-160,'Thay pin chai',1850000,'Dell Service','done')
    ) m(code, off, descr, cost, vendor, status)
    join public.devices d on d.code = m.code;
end $$;

-- =====================================================================
-- SAU KHI CHẠY XONG: cấp quyền admin cho tài khoản bạn đã tạo trong
-- Authentication → Users (thay email bên dưới rồi chạy riêng câu này):
--
--   insert into public.admins (user_id)
--   select id from auth.users where email = 'email-cua-ban@example.com';
-- =====================================================================
