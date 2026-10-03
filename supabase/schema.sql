-- =====================================================================
-- 야구타임 1단계 스키마 (Supabase / Postgres)
-- Supabase 대시보드 > SQL Editor 에 전체를 붙여 넣고 한 번 실행하세요.
--
-- 보안 설계 요약
--   * posts, comments, post_likes 테이블은 RLS를 켜고 정책을 두지 않아
--     클라이언트가 직접 읽거나 쓸 수 없습니다. 모든 접근은 아래 RPC 함수로만 합니다.
--   * RPC는 익명 글/댓글의 작성자 id와 닉네임을 응답에 아예 담지 않습니다.
--   * 팀 자유게시판은 서버가 호출자의 응원팀 기준으로만 보여 주고 쓰게 합니다.
--   * 응원팀 변경은 행 잠금(FOR UPDATE)으로 처리해 무료 변경 중복 사용을 막습니다.
--   * profiles, attendance 는 RLS 정책으로 본인 데이터만 다룰 수 있습니다.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. 정책 값 (클라이언트 src/constants/policy.js 의 표시용 값과 맞춰 주세요)
-- ---------------------------------------------------------------------
create or replace function public.policy_team_lock() returns interval
language sql immutable as $$ select interval '3 months' $$;

create or replace function public.policy_team_grace() returns interval
language sql immutable as $$ select interval '24 hours' $$;

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
  insert into public.profiles (id, username, nickname, default_anon)
  values (new.id, v_username, v_nickname,
          coalesce((new.raw_user_meta_data->>'default_anon')::boolean, true));
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
  board      text not null check (board in ('team', 'all', 'party', 'trade')),
  team_id    text references public.teams(id),
  author_id  uuid not null references public.profiles(id) on delete cascade,
  is_anon    boolean not null,
  title      text not null check (char_length(title) between 1 and 100),
  body       text not null check (char_length(body) between 1 and 5000),
  meta       jsonb,
  created_at timestamptz not null default now(),
  check ((board = 'team') = (team_id is not null))
);
create index posts_board_idx on public.posts (board, team_id, created_at desc);
create index posts_author_idx on public.posts (author_id, created_at desc);

create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  is_anon    boolean not null,
  body       text not null check (char_length(body) between 1 and 1000),
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
  created_at    timestamptz
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
         (select count(*) from public.comments c where c.post_id = p.id),
         p.meta, p.created_at
    from public.posts p
    join public.profiles pr on pr.id = p.author_id
   where auth.uid() is not null
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
  if p.id is null or (p.board = 'team' and p.team_id is distinct from me.team_id) then
    raise exception 'not_found';
  end if;
  return p;
end $$;

create or replace function public.create_post(
  p_board text, p_title text, p_body text, p_is_anon boolean, p_meta jsonb default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me     public.profiles := public.require_user();
  v_meta jsonb := null;
  v_id   uuid;
begin
  if me.team_id is null then raise exception 'team_required'; end if;
  if p_board not in ('team', 'all', 'party', 'trade') then raise exception 'invalid_board'; end if;

  -- 도배 방지: 10초에 글 1개
  if exists (select 1 from public.posts
              where author_id = me.id and created_at > now() - interval '10 seconds') then
    raise exception 'too_fast';
  end if;

  if p_board = 'party' then
    if coalesce(trim(p_meta->>'date'), '') = ''
       or not exists (select 1 from public.teams where home_stadium = p_meta->>'stadium')
       or coalesce(p_meta->>'people', '') !~ '^[0-9]{1,2}$'
       or (p_meta->>'people')::int not between 1 and 20 then
      raise exception 'invalid_meta';
    end if;
    v_meta := jsonb_build_object(
      'date', left(trim(p_meta->>'date'), 30),
      'stadium', p_meta->>'stadium',
      'people', (p_meta->>'people')::int);
  elsif p_board = 'trade' then
    if coalesce(p_meta->>'kind', '') not in ('팝니다', '삽니다')
       or coalesce(p_meta->>'price', '') !~ '^[0-9]{1,9}$'
       or (p_meta->>'price')::int <= 0 then
      raise exception 'invalid_meta';
    end if;
    v_meta := jsonb_build_object('kind', p_meta->>'kind', 'price', (p_meta->>'price')::int);
  end if;

  insert into public.posts (board, team_id, author_id, is_anon, title, body, meta)
  values (p_board,
          case when p_board = 'team' then me.team_id end,
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
  if p.author_id = auth.uid() then raise exception 'own_post'; end if;
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
  result     text not null check (result in ('W', 'D', 'L')),
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
-- 5. 함수 실행 권한 정리
-- ---------------------------------------------------------------------
-- 내부용 함수는 클라이언트가 직접 부를 수 없게
revoke execute on function public.require_user()              from public, anon, authenticated;
revoke execute on function public._visible_posts()            from public, anon, authenticated;
revoke execute on function public._accessible_post(uuid)      from public, anon, authenticated;
revoke execute on function public.handle_new_user()           from public, anon, authenticated;

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

-- 가입 전 중복 확인은 비로그인 상태에서도 가능
grant execute on function public.check_signup_available(text, text) to anon, authenticated;
