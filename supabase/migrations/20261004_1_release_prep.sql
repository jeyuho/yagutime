-- =====================================================================
-- 야구타임 출시 준비 변경 (2026-10-04)
-- 이미 schema.sql 을 실행한 Supabase 프로젝트에 한 번만 실행하세요.
-- (새 프로젝트라면 이 파일 대신 최신 schema.sql 만 실행하면 됩니다.)
--
--   1. 내 글에도 공감 가능
--   2. 구장별 게시판 (board = 'stadium')
--   3. 거래 게시판 삭제 (기존 거래 글과 댓글·공감도 삭제됨, 되돌릴 수 없음)
--   4. 신고 (5명 신고 시 자동 숨김), 차단, 회원 탈퇴, 약관 동의 기록
--
-- 전체가 하나의 트랜잭션이라 중간에 오류가 나면 아무것도 바뀌지 않아요.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 0. 정책 값
-- ---------------------------------------------------------------------
-- 서로 다른 사용자 이 수만큼 신고하면 글·댓글을 자동으로 숨김
create or replace function public.policy_report_hide() returns int
language sql immutable as $$ select 5 $$;

-- ---------------------------------------------------------------------
-- 1. 구장
-- ---------------------------------------------------------------------
create table public.stadiums (
  id   text primary key,
  name text not null unique
);

insert into public.stadiums (id, name) values
  ('jamsil',   '잠실야구장'),
  ('suwon',    '수원KT위즈파크'),
  ('incheon',  '인천SSG랜더스필드'),
  ('daegu',    '대구삼성라이온즈파크'),
  ('gwangju',  '광주-기아 챔피언스 필드'),
  ('changwon', '창원NC파크'),
  ('sajik',    '사직야구장'),
  ('daejeon',  '대전 한화생명 볼파크'),
  ('gocheok',  '고척스카이돔');

alter table public.stadiums enable row level security;
create policy "stadiums are readable" on public.stadiums for select using (true);

-- ---------------------------------------------------------------------
-- 2. 거래 게시판 삭제 + 게시판 종류 변경
-- ---------------------------------------------------------------------
delete from public.posts where board = 'trade';  -- 댓글·공감은 on delete cascade 로 같이 삭제

alter table public.posts    add column stadium_id text references public.stadiums(id);
alter table public.posts    add column hidden_at  timestamptz;  -- 신고 누적으로 숨겨진 시각
alter table public.comments add column hidden_at  timestamptz;

-- board 관련 check 제약을 이름과 상관없이 모두 지우고 새로 만듦
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
     where conrelid = 'public.posts'::regclass and contype = 'c'
       and pg_get_constraintdef(oid) like '%board%'
  loop
    execute format('alter table public.posts drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.posts add constraint posts_board_check
  check (board in ('team', 'all', 'party', 'stadium'));
alter table public.posts add constraint posts_team_board_check
  check ((board = 'team') = (team_id is not null));
alter table public.posts add constraint posts_stadium_board_check
  check ((board = 'stadium') = (stadium_id is not null));

create index posts_stadium_idx on public.posts (stadium_id, created_at desc) where board = 'stadium';

-- ---------------------------------------------------------------------
-- 3. 약관 동의
-- ---------------------------------------------------------------------
alter table public.profiles add column terms_agreed_at timestamptz;

-- 회원가입 시 프로필 자동 생성. 약관(이용약관, 개인정보처리방침, 만 14세 이상) 동의가 없으면 가입 거부
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_username text := lower(coalesce(new.raw_user_meta_data->>'username', ''));
  v_nickname text := trim(coalesce(new.raw_user_meta_data->>'nickname', ''));
begin
  -- 아이디는 이메일 앞부분과 같아야 함 (메타데이터 위조 방지)
  if split_part(new.email, '@', 1) <> v_username then
    raise exception 'username_mismatch';
  end if;
  if public.is_reserved_nickname(v_nickname) then
    raise exception 'nickname_reserved';
  end if;
  if coalesce(new.raw_user_meta_data->>'terms_agreed', '') <> 'true' then
    raise exception 'terms_required';
  end if;
  insert into public.profiles (id, username, nickname, default_anon, terms_agreed_at)
  values (new.id, v_username, v_nickname,
          coalesce((new.raw_user_meta_data->>'default_anon')::boolean, true), now());
  return new;
end $$;

-- ---------------------------------------------------------------------
-- 4. 차단
-- ---------------------------------------------------------------------
-- anon_only: 익명 글·댓글에서 차단한 경우 그 사람의 익명 글·댓글만 가림.
--   (닉네임 글까지 가리면 어떤 닉네임 글이 사라졌는지로 익명 작성자가 누군지 알 수 있기 때문)
-- label: 차단할 때 화면에 보이던 이름 (예: 익명3). 차단 목록에 이것만 보여 줌
create table public.blocks (
  id         uuid not null default gen_random_uuid() unique,
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  anon_only  boolean not null,
  label      text not null check (char_length(label) between 1 and 20),
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id, anon_only),
  check (blocker_id <> blocked_id)
);

alter table public.blocks enable row level security;
revoke all on public.blocks from anon, authenticated;

-- 내부용: 호출자가 이 작성자의 (익명 여부에 따른) 글을 차단했는지
create or replace function public._is_blocked(p_author uuid, p_is_anon boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks b
     where b.blocker_id = auth.uid() and b.blocked_id = p_author
       and (not b.anon_only or p_is_anon))
$$;

-- ---------------------------------------------------------------------
-- 5. 신고
-- ---------------------------------------------------------------------
create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  post_id     uuid references public.posts(id) on delete cascade,
  comment_id  uuid references public.comments(id) on delete cascade,
  reason      text not null check (reason in ('abuse', 'sexual', 'spam', 'scam', 'other')),
  detail      text check (char_length(detail) <= 500),
  status      text not null default 'open' check (status in ('open', 'resolved')),
  created_at  timestamptz not null default now(),
  check ((post_id is null) <> (comment_id is null)),
  unique (reporter_id, post_id),
  unique (reporter_id, comment_id)
);
create index reports_open_idx on public.reports (status, created_at desc);

alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. 글 응답 형태와 조회 함수 (숨김·차단 반영, 구장 추가)
-- ---------------------------------------------------------------------
alter type public.post_view add attribute stadium_id text;

create or replace function public._visible_posts() returns setof public.post_view
language sql stable security definer set search_path = public as $$
  select p.id, p.board, p.team_id, p.title, p.body,
         case when p.is_anon then '익명' else pr.nickname end,
         p.author_id = auth.uid(),
         p.is_anon,
         (select count(*) from public.post_likes l where l.post_id = p.id),
         exists (select 1 from public.post_likes l where l.post_id = p.id and l.user_id = auth.uid()),
         (select count(*) from public.comments c
           where c.post_id = p.id and c.hidden_at is null
             and not public._is_blocked(c.author_id, c.is_anon)),
         p.meta, p.created_at, p.stadium_id
    from public.posts p
    join public.profiles pr on pr.id = p.author_id
   where auth.uid() is not null
     and p.hidden_at is null
     and not public._is_blocked(p.author_id, p.is_anon)
     and (p.board <> 'team'
          or p.team_id = (select team_id from public.profiles where id = auth.uid()))
$$;

create or replace function public.list_stadium_posts(p_stadium text, p_limit int default 50)
returns setof public.post_view
language sql stable security definer set search_path = public as $$
  select * from public._visible_posts() v
   where v.board = 'stadium' and v.stadium_id = p_stadium
   order by v.created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;

-- 내부용: 호출자가 열 수 있는 글 (숨김·차단·다른 팀 게시판이면 not_found)
create or replace function public._accessible_post(p_id uuid) returns public.posts
language plpgsql stable security definer set search_path = public as $$
declare
  me public.profiles := public.require_user();
  p  public.posts;
begin
  select * into p from public.posts where id = p_id;
  if p.id is null
     or p.hidden_at is not null
     or public._is_blocked(p.author_id, p.is_anon)
     or (p.board = 'team' and p.team_id is distinct from me.team_id) then
    raise exception 'not_found';
  end if;
  return p;
end $$;

-- ---------------------------------------------------------------------
-- 7. 글쓰기: 거래 제거, 구장 게시판 추가 (구장은 p_meta = {"stadium": "jamsil"})
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 8. 공감: 내 글에도 가능
-- ---------------------------------------------------------------------
create or replace function public.toggle_like(p_post uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  p public.posts := public._accessible_post(p_post);
begin
  delete from public.post_likes where post_id = p.id and user_id = auth.uid();
  if found then return false; end if;
  insert into public.post_likes (post_id, user_id) values (p.id, auth.uid());
  return true;
end $$;

-- ---------------------------------------------------------------------
-- 9. 댓글 목록: 숨김·차단 반영 (익명 번호는 숨김과 상관없이 처음 매긴 그대로)
-- ---------------------------------------------------------------------
create or replace function public.list_comments(p_post uuid)
returns table (id uuid, body text, author_name text, is_writer boolean, is_mine boolean, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  p public.posts := public._accessible_post(p_post);
begin
  return query
  with anon_order as (
    select c.author_id, row_number() over (order by min(c.created_at)) as n
      from public.comments c
     where c.post_id = p.id and c.is_anon and c.author_id <> p.author_id
     group by c.author_id
  )
  select c.id, c.body,
         case
           when c.is_anon and c.author_id = p.author_id then '익명(글쓴이)'
           when c.is_anon then '익명' || ao.n
           when c.author_id = p.author_id then pr.nickname || ' (글쓴이)'
           else pr.nickname
         end,
         c.author_id = p.author_id,
         c.author_id = auth.uid(),
         c.created_at
    from public.comments c
    join public.profiles pr on pr.id = c.author_id
    left join anon_order ao on ao.author_id = c.author_id
   where c.post_id = p.id
     and c.hidden_at is null
     and not public._is_blocked(c.author_id, c.is_anon)
   order by c.created_at;
end $$;

-- ---------------------------------------------------------------------
-- 10. 신고 / 차단 / 탈퇴 RPC
-- ---------------------------------------------------------------------
-- 글 또는 댓글 하나를 신고. 같은 사람은 같은 대상에 한 번만. 신고자가 policy_report_hide() 명 이상이면 자동 숨김
create or replace function public.report_content(
  p_post uuid, p_comment uuid, p_reason text, p_detail text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me        public.profiles := public.require_user();
  v_post    public.posts;
  v_comment public.comments;
  v_detail  text := left(nullif(trim(coalesce(p_detail, '')), ''), 500);
  v_count   int;
begin
  if (p_post is null) = (p_comment is null) then raise exception 'invalid_target'; end if;
  if coalesce(p_reason, '') not in ('abuse', 'sexual', 'spam', 'scam', 'other') then
    raise exception 'invalid_reason';
  end if;

  if p_post is not null then
    v_post := public._accessible_post(p_post);
    if v_post.author_id = me.id then raise exception 'own_content'; end if;
    insert into public.reports (reporter_id, post_id, reason, detail)
    values (me.id, v_post.id, p_reason, v_detail)
    on conflict do nothing;
    if not found then raise exception 'already_reported'; end if;
    select count(*) into v_count from public.reports where post_id = v_post.id;
    if v_count >= public.policy_report_hide() then
      update public.posts set hidden_at = now() where id = v_post.id and hidden_at is null;
    end if;
  else
    select * into v_comment from public.comments where id = p_comment and hidden_at is null;
    if v_comment.id is null or public._is_blocked(v_comment.author_id, v_comment.is_anon) then
      raise exception 'not_found';
    end if;
    perform public._accessible_post(v_comment.post_id);
    if v_comment.author_id = me.id then raise exception 'own_content'; end if;
    insert into public.reports (reporter_id, comment_id, reason, detail)
    values (me.id, v_comment.id, p_reason, v_detail)
    on conflict do nothing;
    if not found then raise exception 'already_reported'; end if;
    select count(*) into v_count from public.reports where comment_id = v_comment.id;
    if v_count >= public.policy_report_hide() then
      update public.comments set hidden_at = now() where id = v_comment.id and hidden_at is null;
    end if;
  end if;
end $$;

-- 글 또는 댓글의 작성자를 차단. 작성자 id 는 응답에 담지 않음
create or replace function public.block_author(p_post uuid, p_comment uuid, p_label text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  me        public.profiles := public.require_user();
  v_author  uuid;
  v_anon    boolean;
  v_post    public.posts;
  v_comment public.comments;
  v_label   text;
begin
  if (p_post is null) = (p_comment is null) then raise exception 'invalid_target'; end if;

  if p_post is not null then
    v_post := public._accessible_post(p_post);
    v_author := v_post.author_id;
    v_anon := v_post.is_anon;
  else
    select * into v_comment from public.comments where id = p_comment;
    if v_comment.id is null then raise exception 'not_found'; end if;
    perform public._accessible_post(v_comment.post_id);
    v_author := v_comment.author_id;
    v_anon := v_comment.is_anon;
  end if;

  if v_author = me.id then raise exception 'own_content'; end if;

  -- 익명이면 화면에 보이던 이름(익명3 등), 아니면 닉네임
  if v_anon then
    v_label := left(coalesce(nullif(trim(coalesce(p_label, '')), ''), '익명'), 20);
  else
    select nickname into v_label from public.profiles where id = v_author;
  end if;

  insert into public.blocks (blocker_id, blocked_id, anon_only, label)
  values (me.id, v_author, v_anon, v_label)
  on conflict do nothing;
end $$;

create or replace function public.list_blocks()
returns table (id uuid, label text, anon_only boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select b.id, b.label, b.anon_only, b.created_at
    from public.blocks b
   where b.blocker_id = auth.uid()
   order by b.created_at desc
$$;

create or replace function public.unblock(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.blocks where id = p_id and blocker_id = auth.uid();
end $$;

-- 회원 탈퇴: 계정을 지우면 프로필, 글, 댓글, 공감, 직관 기록, 신고, 차단이 모두 cascade 로 삭제됨
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from auth.users where id = auth.uid();
end $$;

-- ---------------------------------------------------------------------
-- 11. 함수 실행 권한
-- ---------------------------------------------------------------------
revoke execute on function public._is_blocked(uuid, boolean) from public, anon, authenticated;

revoke execute on function public.list_stadium_posts(text, int)               from public, anon;
revoke execute on function public.report_content(uuid, uuid, text, text)      from public, anon;
revoke execute on function public.block_author(uuid, uuid, text)              from public, anon;
revoke execute on function public.list_blocks()                               from public, anon;
revoke execute on function public.unblock(uuid)                               from public, anon;
revoke execute on function public.delete_account()                            from public, anon;

grant execute on function public.list_stadium_posts(text, int)                to authenticated;
grant execute on function public.report_content(uuid, uuid, text, text)       to authenticated;
grant execute on function public.block_author(uuid, uuid, text)               to authenticated;
grant execute on function public.list_blocks()                                to authenticated;
grant execute on function public.unblock(uuid)                                to authenticated;
grant execute on function public.delete_account()                             to authenticated;

commit;
