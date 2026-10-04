-- =====================================================================
-- 서비스 이름 변경 (야구타임 → 덕아웃): '덕아웃' 이 들어간 닉네임을 예약어로 막음 (운영자 사칭 방지)
-- 20261004_3_banned_words.sql 을 실행한 뒤에 한 번만 실행하세요.
-- =====================================================================
create or replace function public.is_reserved_nickname(n text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(n, '') ilike any (array['%익명%', '%운영자%', '%관리자%', '%야구타임%', '%덕아웃%'])
      or public.has_banned_word(n)
$$;
