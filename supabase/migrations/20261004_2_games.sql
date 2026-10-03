-- =====================================================================
-- 야구타임 경기 일정 (2026-10-04)
-- 20261004_1_release_prep.sql 을 실행한 뒤에 한 번만 실행하세요.
--
--   1. games: 경기 일정·선발투수·최종 점수. 운영자가 대시보드에서 입력, 앱은 읽기만
--   2. games_import + apply_games_import(): 일정 CSV 를 올린 뒤 한 번에 반영 (같은 id 는 덮어씀)
--   3. 직관 기록: 경기만 고르면 상대·구장·날짜를 서버가 채우고, 결과는 최종 점수 입력 시 자동 기록
--
-- 운영 방법은 docs/운영_경기관리.md 를 보세요.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. 경기
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
-- 2. 일정 CSV 가져오기
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
-- 3. 직관 기록과 경기 연결
-- ---------------------------------------------------------------------
-- 결과는 경기가 끝나 점수가 입력되기 전까지 비어 있을 수 있음 (앱은 '결과 대기'로 표시)
alter table public.attendance alter column result drop not null;

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

commit;
