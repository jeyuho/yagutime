-- =====================================================================
-- 야구타임 스키마 (Supabase / Postgres)
-- 새 프로젝트: Supabase 대시보드 > SQL Editor 에 전체를 붙여 넣고 한 번 실행하세요.
-- 이미 예전 schema.sql 을 실행한 프로젝트: supabase/migrations/ 의 파일을 날짜 순서대로 실행하세요.
--
-- 보안 설계 요약
--   * posts, comments, post_likes 테이블은 RLS를 켜고 정책을 두지 않아
--     클라이언트가 직접 읽거나 쓸 수 없습니다. 모든 접근은 아래 RPC 함수로만 합니다.
--   * RPC는 익명 글/댓글의 작성자 id와 닉네임을 응답에 아예 담지 않습니다.
--   * 팀 자유게시판은 서버가 호출자의 응원팀 기준으로만 보여 주고 쓰게 합니다.
--   * 응원팀 변경은 행 잠금(FOR UPDATE)으로 처리해 무료 변경 중복 사용을 막습니다.
--   * profiles, attendance 는 RLS 정책으로 본인 데이터만 다룰 수 있습니다.
--   * games(경기 일정)는 누구나 읽기만 가능하고, 운영자가 대시보드에서 입력합니다 (docs/운영_경기관리.md).
--   * 신고가 policy_report_hide() 명 이상 쌓인 글·댓글과 내가 차단한 사람의 글·댓글은 서버가 빼고 보냅니다.
--     익명 글에서 차단하면 그 사람의 익명 글만 가려, 사라진 닉네임 글로 익명 작성자를 추측할 수 없게 합니다.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. 정책 값 (클라이언트 src/constants/policy.js 의 표시용 값과 맞춰 주세요)
-- ---------------------------------------------------------------------
create or replace function public.policy_team_lock() returns interval
language sql immutable as $$ select interval '3 months' $$;

create or replace function public.policy_team_grace() returns interval
language sql immutable as $$ select interval '24 hours' $$;

-- 서로 다른 사용자 이 수만큼 신고하면 글·댓글을 자동으로 숨김
create or replace function public.policy_report_hide() returns int
language sql immutable as $$ select 5 $$;

-- ---------------------------------------------------------------------
-- 1. 구단
-- ---------------------------------------------------------------------
create table public.teams (
  id           text primary key,
  name         text not null,
  short_name   text not null,
  home_stadium text not null
);

insert into public.teams (id, name, short_name, home_stadium) values
  ('nc',      'NC 다이노스',   'NC',   '창원NC파크'),
  ('kia',     'KIA 타이거즈',  'KIA',  '광주-기아 챔피언스 필드'),
  ('samsung', '삼성 라이온즈', '삼성', '대구삼성라이온즈파크'),
  ('lg',      'LG 트윈스',     'LG',   '잠실야구장'),
  ('doosan',  '두산 베어스',   '두산', '잠실야구장'),
  ('kt',      'KT 위즈',       'KT',   '수원KT위즈파크'),
  ('ssg',     'SSG 랜더스',    'SSG',  '인천SSG랜더스필드'),
  ('lotte',   '롯데 자이언츠', '롯데', '사직야구장'),
  ('hanwha',  '한화 이글스',   '한화', '대전 한화생명 볼파크'),
  ('kiwoom',  '키움 히어로즈', '키움', '고척스카이돔');

alter table public.teams enable row level security;
create policy "teams are readable" on public.teams for select using (true);

-- 구장 (구장별 게시판)
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
-- 2. 프로필 (auth.users 와 1:1)
-- ---------------------------------------------------------------------
create table public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  username          text not null unique check (username ~ '^[a-z0-9_]{4,16}$'),
  nickname          text not null unique check (nickname ~ '^[가-힣a-zA-Z0-9_]{2,10}$'),
  default_anon      boolean not null default true,
  team_id           text references public.teams(id),
  team_locked_until timestamptz,
  team_grace_until  timestamptz,
  grace_used        boolean not null default false,
  terms_agreed_at   timestamptz,  -- 이용약관·개인정보처리방침·만 14세 이상 동의 시각
  created_at        timestamptz not null default now()
);

alter table public.profiles enable row level security;
-- 본인 행만 읽기 가능. 쓰기 정책은 없음 → 트리거와 RPC로만 변경됩니다.
create policy "read own profile" on public.profiles
  for select to authenticated using (id = auth.uid());

create or replace function public.is_reserved_nickname(n text) returns boolean
language sql immutable as $$
  select coalesce(n, '') ilike any (array['%익명%', '%운영자%', '%관리자%', '%야구타임%'])
$$;

-- 회원가입 시 프로필 자동 생성
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

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 가입 전 중복 확인 (비로그인 상태에서 호출)
create or replace function public.check_signup_available(p_username text, p_nickname text)
returns table (username_taken boolean, nickname_taken boolean, nickname_reserved boolean)
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where username = lower(p_username)),
         exists (select 1 from public.profiles where nickname = trim(p_nickname)),
         public.is_reserved_nickname(trim(p_nickname))
$$;

-- 내부용: 로그인한 사용자의 프로필
create or replace function public.require_user() returns public.profiles
language plpgsql stable security definer set search_path = public as $$
declare me public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then
    raise exception 'not_authenticated';
  end if;
  return me;
end $$;

-- 응원팀 확정 / 변경
--   첫 선택: 24시간 유예 시작 + 3개월 잠금
--   유예 중: 1회 무료 변경 (변경 시점부터 다시 3개월 잠금)
--   잠금 만료 후: 변경 가능 (다시 3개월 잠금)
create or replace function public.change_team(p_team text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare me public.profiles;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.teams where id = p_team) then
    raise exception 'invalid_team';
  end if;

  -- 같은 사용자의 동시 요청을 직렬화
  select * into me from public.profiles where id = auth.uid() for update;
  if me.id is null then raise exception 'not_authenticated'; end if;

  if me.team_id is null then
    update public.profiles
       set team_id = p_team,
           team_locked_until = now() + public.policy_team_lock(),
           team_grace_until  = now() + public.policy_team_grace(),
           grace_used = false
     where id = me.id
    returning * into me;
  elsif me.team_id = p_team then
    raise exception 'same_team';
  elsif not me.grace_used and me.team_grace_until > now() then
    update public.profiles
       set team_id = p_team,
           team_locked_until = now() + public.policy_team_lock(),
           grace_used = true
     where id = me.id
    returning * into me;
  elsif me.team_locked_until <= now() then
    update public.profiles
       set team_id = p_team,
           team_locked_until = now() + public.policy_team_lock()
     where id = me.id
    returning * into me;
  else
    raise exception 'team_locked';
  end if;
  return me;
end $$;

create or replace function public.set_default_anon(p_value boolean) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare me public.profiles;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.profiles set default_anon = p_value where id = auth.uid() returning * into me;
  return me;
end $$;

-- ---------------------------------------------------------------------
-- 3. 게시글 / 댓글 / 공감
-- ---------------------------------------------------------------------
create table public.posts (
  id         uuid primary key default gen_random_uuid(),
  board      text not null constraint posts_board_check check (board in ('team', 'all', 'party', 'stadium')),
  team_id    text references public.teams(id),
  stadium_id text references public.stadiums(id),
  author_id  uuid not null references public.profiles(id) on delete cascade,
  is_anon    boolean not null,
  title      text not null check (char_length(title) between 1 and 100),
  body       text not null check (char_length(body) between 1 and 5000),
  meta       jsonb,
  hidden_at  timestamptz,  -- 신고 누적으로 숨겨진 시각
  created_at timestamptz not null default now(),
  constraint posts_team_board_check check ((board = 'team') = (team_id is not null)),
  constraint posts_stadium_board_check check ((board = 'stadium') = (stadium_id is not null))
);
create index posts_board_idx on public.posts (board, team_id, created_at desc);
create index posts_author_idx on public.posts (author_id, created_at desc);
create index posts_stadium_idx on public.posts (stadium_id, created_at desc) where board = 'stadium';

create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  is_anon    boolean not null,
  body       text not null check (char_length(body) between 1 and 1000),
  hidden_at  timestamptz,
  created_at timestamptz not null default now()
);
create index comments_post_idx on public.comments (post_id, created_at);
create index comments_author_idx on public.comments (author_id, created_at desc);

create table public.post_likes (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- RLS 켜고 정책 없음 = 클라이언트 직접 접근 전부 차단
alter table public.posts      enable row level security;
alter table public.comments   enable row level security;
alter table public.post_likes enable row level security;
revoke all on public.posts, public.comments, public.post_likes from anon, authenticated;

-- 차단
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

-- 신고
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

-- 클라이언트로 내보내는 글 형태 (author_id 없음)
create type public.post_view as (
  id            uuid,
  board         text,
  team_id       text,
  title         text,
  body          text,
  author_name   text,
  is_mine       boolean,
  is_anon       boolean,
  like_count    bigint,
  liked_by_me   boolean,
  comment_count bigint,
  meta          jsonb,
  created_at    timestamptz,
  stadium_id    text
);

-- 내부용: 호출자가 볼 수 있는 글 (팀 게시판은 내 응원팀 것만)
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

create or replace function public.list_posts(p_board text, p_limit int default 50)
returns setof public.post_view
language sql stable security definer set search_path = public as $$
  select * from public._visible_posts() v
   where v.board = p_board
   order by v.created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;

create or replace function public.list_stadium_posts(p_stadium text, p_limit int default 50)
returns setof public.post_view
language sql stable security definer set search_path = public as $$
  select * from public._visible_posts() v
   where v.board = 'stadium' and v.stadium_id = p_stadium
   order by v.created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;

create or replace function public.get_post(p_id uuid)
returns setof public.post_view
language sql stable security definer set search_path = public as $$
  select * from public._visible_posts() v where v.id = p_id
$$;

create or replace function public.list_hot_posts(p_limit int default 3)
returns setof public.post_view
language sql stable security definer set search_path = public as $$
  select * from public._visible_posts() v
   order by v.like_count desc, v.created_at desc
   limit least(greatest(coalesce(p_limit, 3), 1), 20)
$$;

-- 내부용: 호출자가 이 글에 접근할 수 있는지 확인하고 글을 돌려줌
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

create or replace function public.delete_post(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.posts where id = p_id and author_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
end $$;

-- 공감 토글. 반환값 = 토글 후 공감 상태
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

-- 댓글 목록: 익명은 글마다 익명1, 익명2… 번호, 익명 글 작성자는 익명(글쓴이)
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

create or replace function public.create_comment(p_post uuid, p_body text, p_is_anon boolean)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  p      public.posts := public._accessible_post(p_post);
  v_anon boolean := coalesce(p_is_anon, true);
  v_id   uuid;
begin
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

-- 신고 / 차단 / 탈퇴
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
-- 4. 직관 기록 (본인 데이터만, RLS 정책으로 직접 접근)
-- ---------------------------------------------------------------------
create table public.attendance (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  team_id    text not null references public.teams(id),
  game_id    text,
  game_date  date not null default current_date,
  opponent   text not null references public.teams(id),
  stadium    text not null,
  result     text check (result in ('W', 'D', 'L')),  -- 경기 종료 전에는 비어 있음 (games 점수 입력 시 자동 기록)
  score      text check (score ~ '^[0-9]{1,2}:[0-9]{1,2}$'),
  created_at timestamptz not null default now(),
  unique (user_id, team_id, game_id),
  check (opponent <> team_id)
);
create index attendance_user_idx on public.attendance (user_id, team_id, game_date desc);

alter table public.attendance enable row level security;
create policy "read own attendance" on public.attendance
  for select to authenticated using (user_id = auth.uid());
create policy "insert own attendance for my team" on public.attendance
  for insert to authenticated
  with check (user_id = auth.uid()
              and team_id = (select team_id from public.profiles where id = auth.uid()));
create policy "delete own attendance" on public.attendance
  for delete to authenticated using (user_id = auth.uid());
revoke update on public.attendance from anon, authenticated;

-- ---------------------------------------------------------------------
-- 4-1. 경기
-- ---------------------------------------------------------------------
-- id: 경기 고유 번호. 비워 두고 가져오면 '날짜-원정팀-홈팀-차수' 로 자동 생성 (예: 20261004-doosan-nc-0)
-- game_no: 0 = 일반 경기, 1 / 2 = 더블헤더 1차전 / 2차전
-- status: scheduled(예정, 시작 시각이 지나면 앱이 '경기 중'으로 표시) / final(종료, 점수 필수) / canceled(취소)
create table public.games (
  id           text primary key check (id ~ '^[0-9A-Za-z_-]{1,40}$'),
  game_date    date not null,
  start_time   time,
  away_team    text not null references public.teams(id),
  home_team    text not null references public.teams(id),
  stadium_id   text not null references public.stadiums(id),
  game_no      smallint not null default 0 check (game_no between 0 and 2),
  status       text not null default 'scheduled' check (status in ('scheduled', 'final', 'canceled')),
  away_starter text check (char_length(away_starter) <= 20),
  home_starter text check (char_length(home_starter) <= 20),
  away_score   smallint check (away_score between 0 and 99),
  home_score   smallint check (home_score between 0 and 99),
  naver_url    text check (naver_url ~ '^https://(m\.)?sports\.naver\.com/'),
  updated_at   timestamptz not null default now(),
  check (away_team <> home_team),
  check ((status = 'final') = (away_score is not null and home_score is not null))
);
create index games_date_idx on public.games (game_date, start_time);
create index games_away_idx on public.games (away_team, game_date);
create index games_home_idx on public.games (home_team, game_date);

-- 일정은 공개 정보라 누구나 읽기 가능. 쓰기 정책은 없음 → 운영자가 대시보드(SQL Editor / Table Editor)에서만 수정
alter table public.games enable row level security;
create policy "games are readable" on public.games for select using (true);
revoke insert, update, delete on public.games from anon, authenticated;

create or replace function public._touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger games_touch before update on public.games
  for each row execute function public._touch_updated_at();

-- ---------------------------------------------------------------------
-- 4-2. 일정 CSV 가져오기
-- ---------------------------------------------------------------------
-- 운영자가 Table Editor 에서 이 테이블에 CSV 를 import 한 뒤
--   select public.apply_games_import();
-- 를 실행하면 games 에 반영하고 이 테이블을 비움. 빈 칸은 기존 값을 그대로 둠
create table public.games_import (
  id           text,
  game_date    date,
  start_time   time,
  away_team    text,
  home_team    text,
  stadium_id   text,
  game_no      smallint,
  status       text,
  away_starter text,
  home_starter text,
  away_score   smallint,
  home_score   smallint,
  naver_url    text
);
alter table public.games_import enable row level security;
revoke all on public.games_import from anon, authenticated;

create or replace function public.apply_games_import() returns int
language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  insert into public.games as g
    (id, game_date, start_time, away_team, home_team, stadium_id, game_no,
     status, away_starter, home_starter, away_score, home_score, naver_url)
  select coalesce(nullif(trim(i.id), ''),
                  to_char(i.game_date, 'YYYYMMDD') || '-' || i.away_team || '-' || i.home_team || '-' || coalesce(i.game_no, 0)),
         i.game_date, i.start_time, i.away_team, i.home_team,
         -- 구장을 비워 두면 홈팀 구장
         coalesce(nullif(trim(i.stadium_id), ''),
                  (select s.id from public.stadiums s join public.teams t on t.home_stadium = s.name where t.id = i.home_team)),
         coalesce(i.game_no, 0),
         coalesce(nullif(trim(i.status), ''), 'scheduled'),
         nullif(trim(i.away_starter), ''), nullif(trim(i.home_starter), ''),
         i.away_score, i.home_score, nullif(trim(i.naver_url), '')
    from public.games_import i
  on conflict (id) do update set
    game_date    = excluded.game_date,
    start_time   = coalesce(excluded.start_time, g.start_time),
    away_team    = excluded.away_team,
    home_team    = excluded.home_team,
    stadium_id   = excluded.stadium_id,
    game_no      = excluded.game_no,
    status       = case when excluded.status = 'scheduled' and g.status <> 'scheduled'
                             and excluded.away_score is null then g.status  -- 빈 일정 파일로 종료·취소 상태를 되돌리지 않음
                        else excluded.status end,
    away_starter = coalesce(excluded.away_starter, g.away_starter),
    home_starter = coalesce(excluded.home_starter, g.home_starter),
    away_score   = coalesce(excluded.away_score, g.away_score),
    home_score   = coalesce(excluded.home_score, g.home_score),
    naver_url    = coalesce(excluded.naver_url, g.naver_url);
  get diagnostics v_count = row_count;
  delete from public.games_import;
  return v_count;
end $$;
revoke execute on function public.apply_games_import() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4-3. 직관 기록과 경기 연결
-- ---------------------------------------------------------------------

-- 직관 기록 추가 시: games 에 있는 경기면 상대·구장·날짜·결과를 서버가 채움.
-- (예전 샘플 일정처럼 games 에 없는 경기는 예전 방식대로 클라이언트 값과 결과가 필요)
create or replace function public._attendance_from_game() returns trigger
language plpgsql security definer set search_path = public as $$
declare g public.games;
begin
  select * into g from public.games where id = new.game_id;
  if g.id is null then
    if new.result is null then raise exception 'result_required'; end if;
    return new;
  end if;
  if new.team_id not in (g.away_team, g.home_team) then raise exception 'not_my_game'; end if;
  if g.status = 'canceled' then raise exception 'game_canceled'; end if;
  new.game_date := g.game_date;
  new.opponent  := case when g.home_team = new.team_id then g.away_team else g.home_team end;
  new.stadium   := (select name from public.stadiums where id = g.stadium_id);
  new.result    := public._game_result(g, new.team_id);
  new.score     := public._game_score(g, new.team_id);
  return new;
end $$;

-- 내 팀 기준 결과 / 점수 (종료 전이면 null)
create or replace function public._game_result(g public.games, p_team text) returns text
language sql immutable as $$
  select case when g.status <> 'final' then null
              when (case when g.home_team = p_team then g.home_score - g.away_score else g.away_score - g.home_score end) > 0 then 'W'
              when g.home_score = g.away_score then 'D'
              else 'L' end
$$;

create or replace function public._game_score(g public.games, p_team text) returns text
language sql immutable as $$
  select case when g.status <> 'final' then null
              when g.home_team = p_team then g.home_score || ':' || g.away_score
              else g.away_score || ':' || g.home_score end
$$;

create trigger attendance_from_game before insert on public.attendance
  for each row execute function public._attendance_from_game();

-- 운영자가 점수를 입력·수정하거나 취소하면 그 경기의 직관 기록 결과를 다시 계산
create or replace function public._sync_attendance_results() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.attendance a
     set result = public._game_result(new, a.team_id),
         score  = public._game_score(new, a.team_id),
         game_date = new.game_date
   where a.game_id = new.id;
  return null;
end $$;

create trigger games_sync_attendance after update on public.games
  for each row
  when (old.status is distinct from new.status
        or old.away_score is distinct from new.away_score
        or old.home_score is distinct from new.home_score
        or old.game_date is distinct from new.game_date)
  execute function public._sync_attendance_results();

revoke execute on function public._attendance_from_game()    from public, anon, authenticated;
revoke execute on function public._sync_attendance_results() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. 함수 실행 권한 정리
-- ---------------------------------------------------------------------
-- 내부용 함수는 클라이언트가 직접 부를 수 없게
revoke execute on function public.require_user()              from public, anon, authenticated;
revoke execute on function public._visible_posts()            from public, anon, authenticated;
revoke execute on function public._accessible_post(uuid)      from public, anon, authenticated;
revoke execute on function public.handle_new_user()           from public, anon, authenticated;
revoke execute on function public._is_blocked(uuid, boolean)  from public, anon, authenticated;

-- 로그인 사용자 전용 RPC
revoke execute on function public.change_team(text)                              from public, anon;
revoke execute on function public.set_default_anon(boolean)                      from public, anon;
revoke execute on function public.list_posts(text, int)                          from public, anon;
revoke execute on function public.get_post(uuid)                                 from public, anon;
revoke execute on function public.list_hot_posts(int)                            from public, anon;
revoke execute on function public.create_post(text, text, text, boolean, jsonb)  from public, anon;
revoke execute on function public.delete_post(uuid)                              from public, anon;
revoke execute on function public.toggle_like(uuid)                              from public, anon;
revoke execute on function public.list_comments(uuid)                            from public, anon;
revoke execute on function public.create_comment(uuid, text, boolean)            from public, anon;
revoke execute on function public.list_stadium_posts(text, int)                 from public, anon;
revoke execute on function public.report_content(uuid, uuid, text, text)        from public, anon;
revoke execute on function public.block_author(uuid, uuid, text)                from public, anon;
revoke execute on function public.list_blocks()                                 from public, anon;
revoke execute on function public.unblock(uuid)                                 from public, anon;
revoke execute on function public.delete_account()                              from public, anon;

grant execute on function public.change_team(text)                              to authenticated;
grant execute on function public.set_default_anon(boolean)                      to authenticated;
grant execute on function public.list_posts(text, int)                          to authenticated;
grant execute on function public.get_post(uuid)                                 to authenticated;
grant execute on function public.list_hot_posts(int)                            to authenticated;
grant execute on function public.create_post(text, text, text, boolean, jsonb)  to authenticated;
grant execute on function public.delete_post(uuid)                              to authenticated;
grant execute on function public.toggle_like(uuid)                              to authenticated;
grant execute on function public.list_comments(uuid)                            to authenticated;
grant execute on function public.create_comment(uuid, text, boolean)            to authenticated;
grant execute on function public.list_stadium_posts(text, int)                 to authenticated;
grant execute on function public.report_content(uuid, uuid, text, text)        to authenticated;
grant execute on function public.block_author(uuid, uuid, text)                to authenticated;
grant execute on function public.list_blocks()                                 to authenticated;
grant execute on function public.unblock(uuid)                                 to authenticated;
grant execute on function public.delete_account()                              to authenticated;

-- 가입 전 중복 확인은 비로그인 상태에서도 가능
grant execute on function public.check_signup_available(text, text) to anon, authenticated;
