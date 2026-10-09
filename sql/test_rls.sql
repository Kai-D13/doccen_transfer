-- =====================================================================
-- Kiểm thử RLS cho prototype (chạy sau 001_schema_rls.sql trên DB trống)
--   psql -v ON_ERROR_STOP=1 -f 001_schema_rls.sql -f test_rls.sql
-- Production: chuyển thành pgTAP và chạy trong CI.
-- =====================================================================
\set QUIET on
\o /dev/null

-- ---------- Seed (chạy bằng superuser, bỏ qua RLS) ----------
insert into lms.organizations (id, slug, name, type) values
  ('00000000-0000-0000-0000-0000000000a1', 'buymed',  'Buymed',              'distributor'),
  ('00000000-0000-0000-0000-0000000000a2', 'pharmax', 'PharmaX (sponsor)',   'pharma'),
  ('00000000-0000-0000-0000-0000000000a3', 'cmeu',    'ĐH Y Dược (CME)',     'cme_provider');

insert into lms.users (id, full_name) values
  ('00000000-0000-0000-0000-000000000001', 'DS. Verified Pharmacist'),
  ('00000000-0000-0000-0000-000000000002', 'Unverified User'),
  ('00000000-0000-0000-0000-000000000003', 'Buymed Editor'),
  ('00000000-0000-0000-0000-000000000004', 'PharmaX Analyst'),
  ('00000000-0000-0000-0000-000000000005', 'KYC Officer'),
  ('00000000-0000-0000-0000-000000000006', 'SV. Student'),
  ('00000000-0000-0000-0000-000000000007', 'BS. Verified Doctor'),
  ('00000000-0000-0000-0000-000000000008', 'CME Officer');

insert into lms.hcp_profiles (user_id, hcp_type, license_no, verification_status, province_code) values
  ('00000000-0000-0000-0000-000000000001', 'pharmacist', 'CCHN-001', 'approved', '79'),
  ('00000000-0000-0000-0000-000000000002', 'pharmacist', null,       'pending',  '79'),
  ('00000000-0000-0000-0000-000000000006', 'student',    null,       'approved', '01'),
  ('00000000-0000-0000-0000-000000000007', 'doctor',     'CCHN-007', 'approved', '01');

insert into lms.org_memberships values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000003', 'content_editor'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000004', 'analyst'),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000008', 'cme_officer');
insert into lms.platform_roles values ('00000000-0000-0000-0000-000000000005', 'kyc_officer');

insert into lms.courses (id, org_id, sponsor_org_id, cme_provider_org_id, title, status, visibility, allowed_hcp_types, cme_credits) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a1', null, null,
     'GPP cơ bản (public)', 'published', 'public', null, null),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2',
     '00000000-0000-0000-0000-0000000000a3', 'Kháng sinh kê đơn (HCP, dược sĩ)', 'published', 'verified_hcp', array['pharmacist'], 4),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000a1', null, null,
     'Bản nháp', 'draft', 'public', null, null);

insert into lms.lessons (course_id, title, position) values
  ('00000000-0000-0000-0000-0000000000c1', 'Bài 1', 1),
  ('00000000-0000-0000-0000-0000000000c2', 'Bài 1', 1),
  ('00000000-0000-0000-0000-0000000000c3', 'Bài nháp', 1);

-- 12 học viên giả cho báo cáo tổng hợp (k = 10)
insert into lms.users (id, full_name)
  select ('00000000-0000-0000-0000-1000000000' || lpad(g::text, 2, '0'))::uuid, 'Learner ' || g
  from generate_series(10, 21) g;
insert into lms.hcp_profiles (user_id, hcp_type, verification_status, province_code)
  select ('00000000-0000-0000-0000-1000000000' || lpad(g::text, 2, '0'))::uuid, 'pharmacist', 'approved', '79'
  from generate_series(10, 21) g;
insert into lms.enrollments (user_id, course_id, status)
  select ('00000000-0000-0000-0000-1000000000' || lpad(g::text, 2, '0'))::uuid,
         '00000000-0000-0000-0000-0000000000c2', case when g % 2 = 0 then 'completed' else 'in_progress' end
  from generate_series(10, 21) g;
insert into lms.enrollments (user_id, course_id) values
  ('00000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-0000000000c1');   -- doctor, 1 người ở tỉnh 01

-- ---------- Helpers ----------
create or replace function pg_temp.check(name text, ok boolean) returns void language plpgsql as $$
begin
  if ok then raise notice 'PASS  %', name; else raise exception 'FAIL  %', name; end if;
end $$;

create or replace function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('app.user_id', coalesce(u, ''), false);
$$;

grant execute on all functions in schema pg_temp to app_user;
set role app_user;

-- ---------- 1. Anonymous ----------
select pg_temp.as_user(null);
select pg_temp.check('anon chỉ thấy khóa public đã publish',
  (select array_agg(title order by title) from lms.courses) = array['GPP cơ bản (public)']);

-- ---------- 2. Dược sĩ chưa xác thực ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
select pg_temp.check('unverified KHÔNG thấy khóa verified_hcp',
  not exists (select 1 from lms.courses where id = '00000000-0000-0000-0000-0000000000c2'));
select pg_temp.check('unverified KHÔNG thấy lesson của khóa HCP',
  not exists (select 1 from lms.lessons where course_id = '00000000-0000-0000-0000-0000000000c2'));

-- ---------- 3. Dược sĩ đã xác thực ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.check('pharmacist verified thấy khóa HCP dành cho dược sĩ',
  exists (select 1 from lms.courses where id = '00000000-0000-0000-0000-0000000000c2'));
select pg_temp.check('pharmacist KHÔNG thấy bản nháp',
  not exists (select 1 from lms.courses where id = '00000000-0000-0000-0000-0000000000c3'));
insert into lms.enrollments (user_id, course_id) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c2');
select pg_temp.check('pharmacist tự ghi danh được',
  (select count(*) from lms.enrollments) = 1);   -- chỉ thấy enrollment của chính mình

do $$ begin
  insert into lms.enrollments (user_id, course_id) values
    ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000c1');
  raise exception 'FAIL  không được ghi danh hộ người khác';
exception when insufficient_privilege then raise notice 'PASS  không ghi danh hộ người khác';
end $$;

do $$ begin
  update lms.enrollments set status = 'completed';   -- learner tự đánh dấu hoàn thành
  raise exception 'FAIL  learner tự set completed';
exception when insufficient_privilege then raise notice 'PASS  learner không tự set completed (không có GRANT UPDATE)';
end $$;

do $$ begin
  update lms.hcp_profiles set verification_status = 'approved' where user_id = app.uid();
  if found then raise exception 'FAIL  tự duyệt KYC'; end if;
  raise notice 'PASS  learner không tự duyệt KYC (0 dòng bị ảnh hưởng)';
end $$;

-- ---------- 4. Bác sĩ đã xác thực, khóa chỉ cho dược sĩ ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000007');
select pg_temp.check('doctor KHÔNG thấy khóa allowed_hcp_types = pharmacist',
  not exists (select 1 from lms.courses where id = '00000000-0000-0000-0000-0000000000c2'));

-- ---------- 5. Sinh viên ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000006');
select pg_temp.check('student KHÔNG thấy nội dung verified_hcp',
  not exists (select 1 from lms.courses where visibility = 'verified_hcp'));

-- ---------- 6. Content editor của Buymed ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000003');
select pg_temp.check('editor thấy bản nháp của org mình',
  exists (select 1 from lms.courses where id = '00000000-0000-0000-0000-0000000000c3'));
do $$ begin
  update lms.courses set status = 'published' where id = '00000000-0000-0000-0000-0000000000c3';
  raise exception 'FAIL  editor tự publish';
exception when insufficient_privilege then raise notice 'PASS  editor không tự publish được';
end $$;
select pg_temp.check('editor KHÔNG xem được enrollment (không có vai trò analyst/admin)',
  not exists (select 1 from lms.enrollments));

-- ---------- 7. Analyst nhà tài trợ ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000004');
select pg_temp.check('sponsor analyst KHÔNG đọc được dữ liệu dòng enrollment',
  not exists (select 1 from lms.enrollments));
select pg_temp.check('sponsor analyst KHÔNG đọc được hcp_profiles',
  not exists (select 1 from lms.hcp_profiles));
select pg_temp.check('sponsor thấy số liệu tổng hợp (nhóm ≥ k)',
  (select enrolled from app.sponsor_course_stats('00000000-0000-0000-0000-0000000000c2')
   where hcp_type = 'pharmacist' and province_code = '79') = 13);
do $$ begin
  perform * from app.sponsor_course_stats('00000000-0000-0000-0000-0000000000c1');
  raise exception 'FAIL  sponsor xem báo cáo khóa không tài trợ';
exception when insufficient_privilege then raise notice 'PASS  sponsor không xem báo cáo khóa không tài trợ';
end $$;

-- ---------- 8. CME officer ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000008');
select pg_temp.check('CME officer thấy enrollment khóa mình bảo trợ',
  (select count(*) from lms.enrollments where course_id = '00000000-0000-0000-0000-0000000000c2') = 13);
select pg_temp.check('CME officer KHÔNG thấy enrollment khóa khác',
  not exists (select 1 from lms.enrollments where course_id = '00000000-0000-0000-0000-0000000000c1'));

-- ---------- 9. KYC officer ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000005');
update lms.hcp_profiles set verification_status = 'approved'
  where user_id = '00000000-0000-0000-0000-000000000002';
select pg_temp.check('KYC officer duyệt được hồ sơ',
  (select verification_status from lms.hcp_profiles where user_id = '00000000-0000-0000-0000-000000000002') = 'approved');

-- user 2 giờ đã xác thực -> thấy khóa HCP
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
select pg_temp.check('sau khi duyệt KYC, user thấy khóa HCP',
  exists (select 1 from lms.courses where id = '00000000-0000-0000-0000-0000000000c2'));

reset role;
\o
\echo 'ALL RLS TESTS PASSED'
