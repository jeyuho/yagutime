-- =====================================================================
-- 야구타임 금칙어 필터 (2026-10-04)
-- 20261004_2_games.sql 을 실행한 뒤에 한 번만 실행하세요.
--
--   * banned_words: 금칙어. 글 제목·본문, 댓글, 닉네임에 들어 있으면 서버가 거부 ('banned_word', 닉네임은 'nickname_reserved')
--   * allowed_words: 금칙어가 들어 있지만 정상적인 말 (시발점, 홍어회 등). 먼저 지운 뒤 검사
--   * 비교할 때 숫자·기호를 빼고 소문자로 바꿔서 "시1발", "F.U.C.K" 도 걸러냄.
--     띄어쓰기는 단어 경계로 남김 ("역시 발이 빠르다" 가 '시발'로 잘못 걸리지 않게. 대신 일부러 띄운 "시 발" 은 통과)
--   * 목록은 클라이언트에 내려보내지 않음 (우회 방법을 알려 주지 않도록). 운영자가 대시보드에서 추가·삭제
--   * 이미 올라온 글에는 적용되지 않음. README "금칙어" 의 조회 SQL 로 찾아 처리
-- =====================================================================
begin;

create table public.banned_words (
  word       text primary key check (char_length(word) between 1 and 30),
  created_at timestamptz not null default now()
);
create table public.allowed_words (
  word       text primary key check (char_length(word) between 1 and 30),
  created_at timestamptz not null default now()
);
alter table public.banned_words  enable row level security;
alter table public.allowed_words enable row level security;
revoke all on public.banned_words, public.allowed_words from anon, authenticated;

-- 시작용 목록. 운영하면서 계속 보강하세요 (insert into public.banned_words (word) values ('...');)
insert into public.banned_words (word) values
  ('씨발'),
  ('시발'),
  ('씨빨'),
  ('씨바'),
  ('씨팔'),
  ('시팔'),
  ('씨부랄'),
  ('ㅅㅂ'),
  ('ㅆㅂ'),
  ('ㅆㅃ'),
  ('ㅅㅃ'),
  ('썅'),
  ('쌍년'),
  ('쌍놈'),
  ('병신'),
  ('븅신'),
  ('빙신'),
  ('ㅄ'),
  ('ㅂㅅ'),
  ('좆'),
  ('좃'),
  ('졷'),
  ('씹새'),
  ('씹창'),
  ('씹년'),
  ('씹놈'),
  ('개새끼'),
  ('개새기'),
  ('개세끼'),
  ('개색기'),
  ('개색히'),
  ('개쌔끼'),
  ('개씨발'),
  ('지랄'),
  ('ㅈㄹ'),
  ('염병'),
  ('엠창'),
  ('느금'),
  ('니애미'),
  ('니앰'),
  ('니미럴'),
  ('애미뒤'),
  ('애비뒤'),
  ('애미없'),
  ('애비없'),
  ('섹스'),
  ('창녀'),
  ('창년'),
  ('걸레년'),
  ('딸딸이'),
  ('홍어'),
  ('전라디언'),
  ('쪽바리'),
  ('짱깨'),
  ('한남충'),
  ('김치녀'),
  ('메갈'),
  ('틀딱'),
  ('애자'),
  ('fuck'),
  ('fck'),
  ('fuk'),
  ('shit'),
  ('bitch'),
  ('asshole'),
  ('motherfucker'),
  ('nigger');
insert into public.allowed_words (word) values
  ('시발점'),
  ('시발역'),
  ('홍어회'),
  ('홍어삼합'),
  ('홍어애'),
  ('홍어탕'),
  ('애자일'),
  ('유니섹스'),
  ('메갈로돈');

-- 비교용 정리: 소문자로, 한글·자모·영문과 띄어쓰기만 남김 (줄바꿈·탭은 띄어쓰기로)
create or replace function public._normalize_text(t text) returns text
language sql immutable as $$
  select regexp_replace(regexp_replace(lower(coalesce(t, '')), '\s+', ' ', 'g'), '[^가-힣ㄱ-ㅎㅏ-ㅣa-z ]', '', 'g')
$$;

create or replace function public.has_banned_word(t text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v text := public._normalize_text(t);
  a record;
begin
  if trim(v) = '' then return false; end if;
  -- 허용 단어는 긴 것부터 구분자로 바꿔서, 지운 자리 앞뒤 글자가 붙어 새 금칙어가 되지 않게 함
  for a in select public._normalize_text(word) as w from public.allowed_words order by char_length(word) desc loop
    if a.w <> '' then v := replace(v, a.w, '|'); end if;
  end loop;
  return exists (
    select 1 from public.banned_words b
     where trim(public._normalize_text(b.word)) <> ''
       and position(public._normalize_text(b.word) in v) > 0);
end $$;

-- 닉네임: 예약어 + 금칙어 (회원가입 트리거와 가입 전 중복 확인이 이 함수를 씀)
create or replace function public.is_reserved_nickname(n text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(n, '') ilike any (array['%익명%', '%운영자%', '%관리자%', '%야구타임%'])
      or public.has_banned_word(n)
$$;

-- 글쓰기 / 댓글에 금칙어 검사 추가 (나머지는 그대로)
create or replace function public.create_post(
  p_board text, p_title text, p_body text, p_is_anon boolean, p_meta jsonb default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me        public.profiles := public.require_user();
  v_meta    jsonb := null;
  v_stadium text := null;
  v_id      uuid;
begin
  if me.team_id is null then raise exception 'team_required'; end if;
  if p_board not in ('team', 'all', 'party', 'stadium') then raise exception 'invalid_board'; end if;
  if public.has_banned_word(coalesce(p_title, '') || ' ' || coalesce(p_body, '')) then raise exception 'banned_word'; end if;

  -- 도배 방지: 10초에 글 1개
  if exists (select 1 from public.posts
              where author_id = me.id and created_at > now() - interval '10 seconds') then
    raise exception 'too_fast';
  end if;

  if p_board = 'party' then
    if coalesce(trim(p_meta->>'date'), '') = ''
       or not exists (select 1 from public.stadiums where name = p_meta->>'stadium')
       or coalesce(p_meta->>'people', '') !~ '^[0-9]{1,2}$'
       or (p_meta->>'people')::int not between 1 and 20 then
      raise exception 'invalid_meta';
    end if;
    v_meta := jsonb_build_object(
      'date', left(trim(p_meta->>'date'), 30),
      'stadium', p_meta->>'stadium',
      'people', (p_meta->>'people')::int);
  elsif p_board = 'stadium' then
    select id into v_stadium from public.stadiums where id = p_meta->>'stadium';
    if v_stadium is null then raise exception 'invalid_meta'; end if;
  end if;

  insert into public.posts (board, team_id, stadium_id, author_id, is_anon, title, body, meta)
  values (p_board,
          case when p_board = 'team' then me.team_id end,
          v_stadium,
          me.id, coalesce(p_is_anon, true), trim(p_title), trim(p_body), v_meta)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.create_comment(p_post uuid, p_body text, p_is_anon boolean)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  p      public.posts := public._accessible_post(p_post);
  v_anon boolean := coalesce(p_is_anon, true);
  v_id   uuid;
begin
  if public.has_banned_word(p_body) then raise exception 'banned_word'; end if;
  if exists (select 1 from public.comments
              where author_id = auth.uid() and created_at > now() - interval '3 seconds') then
    raise exception 'too_fast';
  end if;
  -- 익명 글의 작성자는 익명으로만 댓글 가능 (닉네임 댓글이면 작성자가 드러남)
  if p.is_anon and p.author_id = auth.uid() then
    v_anon := true;
  end if;
  insert into public.comments (post_id, author_id, is_anon, body)
  values (p.id, auth.uid(), v_anon, trim(p_body))
  returning id into v_id;
  return v_id;
end $$;

revoke execute on function public.has_banned_word(text) from public, anon, authenticated;

commit;
