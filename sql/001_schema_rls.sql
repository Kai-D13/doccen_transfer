-- =====================================================================
-- LMS prototype: core schema + RBAC/ABAC helpers + Row Level Security
-- PostgreSQL 15+  |  Research prototype, KHÔNG phải migration production
--
-- Mô hình kết nối:
--   app_owner : sở hữu bảng, chỉ dùng chạy migration
--   app_user  : API kết nối bằng role này (RLS áp dụng)
--   app_worker: worker/service nội bộ (BYPASSRLS), chỉ dùng cho job hệ thống
--
-- Mỗi request API mở transaction và gọi:
--   select set_config('app.user_id', '<uuid từ JWT đã verify>', true);  -- = SET LOCAL
-- =====================================================================

create extension if not exists pgcrypto;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'app_owner')  then create role app_owner nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'app_user')   then create role app_user  nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'app_worker') then create role app_worker nologin bypassrls; end if;
end $$;

create schema if not exists app authorization app_owner;      -- helper functions
create schema if not exists lms authorization app_owner;      -- business tables
set role app_owner;

-- ---------------------------------------------------------------------
-- 1. Identity & tổ chức
-- ---------------------------------------------------------------------
create table lms.users (
  id          uuid primary key default gen_random_uuid(),
  phone       text unique,
  email       text unique,
  full_name   text not null,
  status      text not null default 'active' check (status in ('active','suspended','deleted')),
  created_at  timestamptz not null default now()
);

create table lms.hcp_profiles (
  user_id              uuid primary key references lms.users(id) on delete cascade,
  hcp_type             text not null check (hcp_type in ('doctor','pharmacist','nurse','technician','midwife','student','other')),
  specialty            text,
  province_code        text,
  license_no           text,                       -- số CCHN (PII, nên mã hóa cột ở production)
  verification_status  text not null default 'none'
                         check (verification_status in ('none','pending','approved','rejected','need_more_info','expired')),
  verified_until       date
);
create unique index hcp_license_unique on lms.hcp_profiles (license_no) where license_no is not null;

create table lms.organizations (
  id    uuid primary key default gen_random_uuid(),
  slug  text unique not null,
  name  text not null,
  type  text not null check (type in ('platform','pharma','distributor','association','hospital','university','cme_provider'))
);

-- Vai trò cấp platform (nhân sự vận hành)
create table lms.platform_roles (
  user_id uuid references lms.users(id) on delete cascade,
  role    text check (role in ('super_admin','platform_admin','kyc_officer','moderator','support','finance')),
  primary key (user_id, role)
);

-- Vai trò cấp tổ chức (tenant / kênh)
create table lms.org_memberships (
  org_id  uuid references lms.organizations(id) on delete cascade,
  user_id uuid references lms.users(id) on delete cascade,
  role    text check (role in ('org_owner','org_admin','content_editor','instructor','mlr_reviewer','cme_officer','analyst','member')),
  primary key (org_id, user_id, role)
);
create index org_memberships_user on lms.org_memberships (user_id);

-- ---------------------------------------------------------------------
-- 2. Nội dung
-- ---------------------------------------------------------------------
create table lms.courses (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null references lms.organizations(id),     -- kênh sở hữu
  sponsor_org_id       uuid references lms.organizations(id),              -- nhà tài trợ (nếu có)
  cme_provider_org_id  uuid references lms.organizations(id),              -- cơ sở đào tạo cấp CME
  title                text not null,
  status               text not null default 'draft'
                         check (status in ('draft','in_review','approved','published','unpublished','archived')),
  visibility           text not null default 'registered'
                         check (visibility in ('public','registered','verified_hcp','org_members','invite_only')),
  allowed_hcp_types    text[],                       -- null = mọi loại HCP
  enrollment_mode      text not null default 'open' check (enrollment_mode in ('open','code','paid','assigned')),
  cme_credits          numeric(5,2),
  version              int not null default 1,
  created_by           uuid references lms.users(id),
  created_at           timestamptz not null default now()
);
create index courses_org on lms.courses (org_id);
create index courses_sponsor on lms.courses (sponsor_org_id);

create table lms.lessons (
  id              uuid primary key default gen_random_uuid(),
  course_id       uuid not null references lms.courses(id) on delete cascade,
  title           text not null,
  position        int not null,
  video_asset_id  text,                     -- id bên video provider; playback token do API ký
  duration_sec    int,
  is_preview      boolean not null default false
);
create index lessons_course on lms.lessons (course_id);

-- ---------------------------------------------------------------------
-- 3. Học tập
-- ---------------------------------------------------------------------
create table lms.enrollments (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references lms.users(id),
  course_id     uuid not null references lms.courses(id),
  source        text not null default 'self' check (source in ('self','code','purchase','assigned','import')),
  status        text not null default 'enrolled' check (status in ('enrolled','in_progress','completed','expired','cancelled')),
  enrolled_at   timestamptz not null default now(),
  completed_at  timestamptz,
  unique (user_id, course_id)
);
create index enrollments_course on lms.enrollments (course_id);

create table lms.lesson_progress (
  user_id         uuid references lms.users(id),
  lesson_id       uuid references lms.lessons(id),
  watched_seconds int not null default 0,          -- do server tính từ heartbeat
  completed_at    timestamptz,
  primary key (user_id, lesson_id)
);

create table lms.quiz_attempts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references lms.users(id),
  course_id     uuid not null references lms.courses(id),
  score         numeric(5,2),
  passed        boolean,
  snapshot      jsonb,                              -- đề + câu trả lời (bằng chứng CME)
  submitted_at  timestamptz
);

create table lms.certificates (
  id             uuid primary key default gen_random_uuid(),
  serial_no      text unique not null,
  user_id        uuid not null references lms.users(id),
  course_id      uuid not null references lms.courses(id),
  course_version int not null,
  issuer_org_id  uuid not null references lms.organizations(id),
  credits        numeric(5,2),
  issued_at      timestamptz not null default now(),
  revoked_at     timestamptz,
  revoke_reason  text
);

create table lms.kyc_submissions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references lms.users(id),
  document_path  text not null,                     -- key trong bucket private
  status         text not null default 'pending' check (status in ('pending','approved','rejected','need_more_info')),
  reviewed_by    uuid references lms.users(id),
  reviewed_at    timestamptz,
  note           text
);

-- Consent chia sẻ dữ liệu dòng (PII) với một tổ chức (ví dụ nhà tài trợ)
create table lms.consents (
  user_id     uuid references lms.users(id),
  org_id      uuid references lms.organizations(id),
  purpose     text check (purpose in ('share_identity_with_org','marketing')),
  granted_at  timestamptz not null default now(),
  revoked_at  timestamptz,
  primary key (user_id, org_id, purpose)
);

-- ---------------------------------------------------------------------
-- 4. Helper functions (SECURITY DEFINER: chạy bằng quyền app_owner,
--    không bị RLS -> tránh đệ quy policy; luôn set search_path)
-- ---------------------------------------------------------------------
create or replace function app.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('app.user_id', true), '')::uuid
$$;

create or replace function app.has_platform_role(roles text[]) returns boolean
language sql stable security definer set search_path = pg_catalog, lms as $$
  select exists (select 1 from lms.platform_roles
                 where user_id = app.uid() and (role = any(roles) or role = 'super_admin'))
$$;

create or replace function app.has_org_role(p_org uuid, roles text[]) returns boolean
language sql stable security definer set search_path = pg_catalog, lms as $$
  select p_org is not null and exists (
    select 1 from lms.org_memberships
    where user_id = app.uid() and org_id = p_org and (role = any(roles) or role = 'org_owner'))
$$;

create or replace function app.current_hcp_type() returns text
language sql stable security definer set search_path = pg_catalog, lms as $$
  select hcp_type from lms.hcp_profiles
  where user_id = app.uid()
    and verification_status = 'approved'
    and (verified_until is null or verified_until >= current_date)
$$;

-- Quy tắc ABAC "ai được thấy khóa học" - dùng chung cho policy và các bảng con
create or replace function app.course_visible(p_course uuid, p_status text, p_visibility text,
                                              p_org uuid, p_hcp_types text[]) returns boolean
language sql stable security definer set search_path = pg_catalog, lms as $$
  select
    -- nhân sự của kênh / platform thấy mọi trạng thái
    app.has_org_role(p_org, array['org_admin','content_editor','instructor','mlr_reviewer','cme_officer','analyst'])
    or app.has_platform_role(array['platform_admin','moderator','support'])
    or (p_status = 'published' and (
          p_visibility = 'public'
       or (p_visibility = 'registered'   and app.uid() is not null)
       or (p_visibility = 'verified_hcp' and app.current_hcp_type() is not null
                                         and app.current_hcp_type() <> 'student'
                                         and (p_hcp_types is null or app.current_hcp_type() = any(p_hcp_types)))
       or (p_visibility = 'org_members'  and app.has_org_role(p_org, array['member','org_admin','content_editor','instructor']))
       or (p_visibility = 'invite_only'  and exists (select 1 from lms.enrollments e
                                                    where e.user_id = app.uid() and e.course_id = p_course))
    ))
$$;

create or replace function app.can_view_course(p_course uuid) returns boolean
language sql stable security definer set search_path = pg_catalog, lms as $$
  select exists (select 1 from lms.courses c where c.id = p_course
                 and app.course_visible(c.id, c.status, c.visibility, c.org_id, c.allowed_hcp_types))
$$;

-- Nhân sự có quyền xem dữ liệu học viên của khóa (org sở hữu hoặc cơ sở CME)
create or replace function app.can_staff_course(p_course uuid, roles text[]) returns boolean
language sql stable security definer set search_path = pg_catalog, lms as $$
  select exists (select 1 from lms.courses c where c.id = p_course
                 and (app.has_org_role(c.org_id, roles)
                      or app.has_org_role(c.cme_provider_org_id, array['cme_officer'])))
      or app.has_platform_role(array['platform_admin','support'])
$$;

create or replace function app.is_enrolled(p_course uuid) returns boolean
language sql stable security definer set search_path = pg_catalog, lms as $$
  select exists (select 1 from lms.enrollments
                 where user_id = app.uid() and course_id = p_course
                   and status in ('enrolled','in_progress','completed'))
$$;

-- ---------------------------------------------------------------------
-- 5. Row Level Security
--    Ghi chú hiệu năng: bọc hàm không phụ thuộc dòng trong (select ...) để
--    planner tính 1 lần / câu lệnh (InitPlan) thay vì mỗi dòng.
-- ---------------------------------------------------------------------
alter table lms.users            enable row level security;
alter table lms.hcp_profiles     enable row level security;
alter table lms.organizations    enable row level security;
alter table lms.platform_roles   enable row level security;
alter table lms.org_memberships  enable row level security;
alter table lms.courses          enable row level security;
alter table lms.lessons          enable row level security;
alter table lms.enrollments      enable row level security;
alter table lms.lesson_progress  enable row level security;
alter table lms.quiz_attempts    enable row level security;
alter table lms.certificates     enable row level security;
alter table lms.kyc_submissions  enable row level security;
alter table lms.consents         enable row level security;

-- users: thấy chính mình; nhân sự platform thấy tất cả
create policy users_self on lms.users for select
  using (id = (select app.uid()) or (select app.has_platform_role(array['platform_admin','support','kyc_officer'])));
create policy users_self_update on lms.users for update
  using (id = (select app.uid())) with check (id = (select app.uid()));

-- hcp_profiles: chủ sở hữu đọc; chỉ KYC officer đổi trạng thái xác thực (qua cột được grant, xem phần GRANT)
create policy hcp_read on lms.hcp_profiles for select
  using (user_id = (select app.uid()) or (select app.has_platform_role(array['platform_admin','kyc_officer','support'])));
create policy hcp_insert_self on lms.hcp_profiles for insert
  with check (user_id = (select app.uid()) and verification_status = 'none');
create policy hcp_update_kyc on lms.hcp_profiles for update
  using ((select app.has_platform_role(array['kyc_officer'])));

-- organizations: thông tin kênh là công khai
create policy orgs_read on lms.organizations for select using (true);
create policy orgs_admin on lms.organizations for all
  using ((select app.has_platform_role(array['platform_admin'])))
  with check ((select app.has_platform_role(array['platform_admin'])));

-- memberships: thấy membership của mình + admin của org thấy toàn bộ org
create policy om_read on lms.org_memberships for select
  using (user_id = (select app.uid()) or app.has_org_role(org_id, array['org_admin'])
         or (select app.has_platform_role(array['platform_admin'])));
create policy om_manage on lms.org_memberships for all
  using (app.has_org_role(org_id, array['org_admin']) or (select app.has_platform_role(array['platform_admin'])))
  with check (
    (app.has_org_role(org_id, array['org_admin']) and role <> 'org_owner')   -- org_admin không tự tạo owner
    or (select app.has_platform_role(array['platform_admin'])));

create policy pr_read on lms.platform_roles for select
  using (user_id = (select app.uid()) or (select app.has_platform_role(array['platform_admin'])));

-- courses
create policy courses_read on lms.courses for select
  using (app.course_visible(id, status, visibility, org_id, allowed_hcp_types));
create policy courses_insert on lms.courses for insert
  with check (app.has_org_role(org_id, array['org_admin','content_editor']) and status = 'draft');
create policy courses_update on lms.courses for update
  using (app.has_org_role(org_id, array['org_admin','content_editor','mlr_reviewer']))
  with check (
    -- chỉ org_admin được publish; editor chỉ thao tác draft/in_review
    (status in ('draft','in_review') and app.has_org_role(org_id, array['org_admin','content_editor']))
    or (status = 'approved'          and app.has_org_role(org_id, array['mlr_reviewer']))
    or app.has_org_role(org_id, array['org_admin'])
  );

-- lessons: metadata thấy khi thấy course; nội dung (playback) do API ký token sau khi check enrolled
create policy lessons_read on lms.lessons for select
  using (app.can_view_course(course_id));
create policy lessons_write on lms.lessons for all
  using (exists (select 1 from lms.courses c where c.id = course_id
                 and app.has_org_role(c.org_id, array['org_admin','content_editor'])))
  with check (exists (select 1 from lms.courses c where c.id = course_id
                 and app.has_org_role(c.org_id, array['org_admin','content_editor'])));

-- enrollments
create policy enr_read on lms.enrollments for select
  using (user_id = (select app.uid())
         or app.can_staff_course(course_id, array['org_admin','instructor','analyst']));
create policy enr_self_enroll on lms.enrollments for insert
  with check (
    user_id = (select app.uid()) and source = 'self' and status = 'enrolled'
    and exists (select 1 from lms.courses c where c.id = course_id
                and c.status = 'published' and c.enrollment_mode = 'open'
                and app.course_visible(c.id, c.status, c.visibility, c.org_id, c.allowed_hcp_types)));
create policy enr_assign on lms.enrollments for insert
  with check (
    source = 'assigned'
    and exists (select 1 from lms.courses c where c.id = course_id
                and app.has_org_role(c.org_id, array['org_admin']))
  );
-- Không có policy UPDATE cho learner: trạng thái hoàn thành do service (app_worker) cập nhật.

-- progress / attempts: chỉ đọc qua RLS; ghi qua service
create policy lp_read on lms.lesson_progress for select
  using (user_id = (select app.uid())
         or exists (select 1 from lms.lessons l where l.id = lesson_id
                    and app.can_staff_course(l.course_id, array['org_admin','instructor','analyst'])));
create policy qa_read on lms.quiz_attempts for select
  using (user_id = (select app.uid())
         or app.can_staff_course(course_id, array['org_admin','instructor']));

-- certificates
create policy cert_read on lms.certificates for select
  using (user_id = (select app.uid())
         or app.has_org_role(issuer_org_id, array['org_admin','cme_officer'])
         or (select app.has_platform_role(array['platform_admin','support'])));

-- kyc
create policy kyc_read on lms.kyc_submissions for select
  using (user_id = (select app.uid()) or (select app.has_platform_role(array['kyc_officer','platform_admin'])));
create policy kyc_submit on lms.kyc_submissions for insert
  with check (user_id = (select app.uid()) and status = 'pending' and reviewed_by is null);
create policy kyc_review on lms.kyc_submissions for update
  using ((select app.has_platform_role(array['kyc_officer'])))
  with check ((select app.has_platform_role(array['kyc_officer'])) and reviewed_by = (select app.uid()));

-- consents
create policy consent_self on lms.consents for all
  using (user_id = (select app.uid())) with check (user_id = (select app.uid()));
create policy consent_org_read on lms.consents for select
  using (app.has_org_role(org_id, array['org_admin','analyst']));

-- ---------------------------------------------------------------------
-- 6. Hàm "cửa sổ hẹp" (SECURITY DEFINER) cho các truy cập đặc biệt
-- ---------------------------------------------------------------------

-- Trang verify chứng chỉ công khai: chỉ trả về field tối thiểu
create or replace function app.verify_certificate(p_serial text)
returns table (serial_no text, holder_name text, course_title text, credits numeric,
               issued_at timestamptz, issuer text, is_valid boolean)
language sql stable security definer set search_path = pg_catalog, lms as $$
  select ce.serial_no, u.full_name, c.title, ce.credits, ce.issued_at, o.name, ce.revoked_at is null
  from lms.certificates ce
  join lms.users u on u.id = ce.user_id
  join lms.courses c on c.id = ce.course_id
  join lms.organizations o on o.id = ce.issuer_org_id
  where ce.serial_no = p_serial
$$;

-- Báo cáo nhà tài trợ: chỉ số tổng hợp, ẩn nhóm nhỏ (k-anonymity), không trả PII
create or replace function app.sponsor_course_stats(p_course uuid, k int default 10)
returns table (hcp_type text, province_code text, enrolled bigint, completed bigint)
language plpgsql stable security definer set search_path = pg_catalog, lms as $$
begin
  if not exists (select 1 from lms.courses c where c.id = p_course
                 and (app.has_org_role(c.sponsor_org_id, array['analyst','org_admin'])
                      or app.has_platform_role(array['platform_admin']))) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
    select coalesce(h.hcp_type, 'unknown'), coalesce(h.province_code, 'unknown'),
           count(*), count(*) filter (where e.status = 'completed')
    from lms.enrollments e
    left join lms.hcp_profiles h on h.user_id = e.user_id
    where e.course_id = p_course
    group by 1, 2
    having count(*) >= k;
end $$;

-- ---------------------------------------------------------------------
-- 7. GRANT (least privilege). RLS chỉ lọc dòng; GRANT quyết định bảng/cột.
-- ---------------------------------------------------------------------
reset role;
grant usage on schema app, lms to app_user, app_worker;
grant execute on all functions in schema app to app_user, app_worker;

grant select on all tables in schema lms to app_user;
grant insert on lms.courses, lms.lessons, lms.enrollments, lms.kyc_submissions,
               lms.hcp_profiles, lms.consents, lms.org_memberships to app_user;
grant update (full_name, email, phone) on lms.users to app_user;
grant update (title, status, visibility, allowed_hcp_types, enrollment_mode, cme_credits) on lms.courses to app_user;
grant update, delete on lms.lessons, lms.org_memberships, lms.consents to app_user;
grant update (verification_status, verified_until) on lms.hcp_profiles to app_user;   -- policy chỉ cho kyc_officer
grant update (status, reviewed_by, reviewed_at, note) on lms.kyc_submissions to app_user;

grant select, insert, update on all tables in schema lms to app_worker;   -- job hệ thống
