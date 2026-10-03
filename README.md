# 야구타임 (1단계: 데이터와 보안)

KBO 팬 커뮤니티 웹 앱. React(Vite) + Supabase.

## 1. Supabase 준비

1. [supabase.com](https://supabase.com)에서 새 프로젝트를 만듭니다. 지역은 가까운 곳(예: Northeast Asia, Seoul)을 고르세요.
2. **이메일 확인 끄기.** 이 앱은 아이디를 내부용 이메일(`아이디@users.yagutime.app`)로 바꿔 가입시키기 때문에, 확인 메일이 실제로 갈 수 없습니다.
   Authentication 메뉴의 Email 공급자 설정에서 **Confirm email** 을 끄세요.
3. **비밀번호 규칙 맞추기.** Authentication 설정의 비밀번호 항목에서 최소 길이를 8로, 요구 조건을 "소문자, 대문자, 숫자"(Lowercase, uppercase letters and digits)로 설정하세요. 앱에서도 같은 규칙(`src/lib/utils.js` 의 `PASSWORD_RULES`)을 검사하지만 서버 설정이 최종 기준이에요.
4. **스키마 실행.** SQL Editor를 열고 `supabase/schema.sql` 전체를 붙여 넣어 실행합니다.
   이미 예전 `schema.sql`을 실행한 프로젝트라면 `schema.sql` 대신 `supabase/migrations/`의 파일을 날짜 순서대로 한 번씩 실행하세요.
5. **키 복사.** Project Settings > API 에서 Project URL과 anon(publishable) 키를 복사합니다.

> 대시보드 메뉴 이름은 Supabase 업데이트에 따라 조금씩 바뀔 수 있어요.

## 2. 로컬 실행

```bash
npm install
cp .env.example .env.local   # 복사한 URL과 anon 키를 채워 넣기
npm run dev
```

브라우저에서 표시된 주소(기본 http://localhost:5173)로 접속하면 됩니다.

## 3. 폴더 구조

```
supabase/schema.sql        DB 테이블, RLS 정책, RPC 함수
src/lib/supabase.js        Supabase 클라이언트
src/lib/api.js             서버 호출 모음 + 에러 문구 변환
src/lib/utils.js           날짜, 승률, 입력 검증 등
src/hooks/useAuth.js       로그인 세션과 프로필
src/constants/             팀 테마, 게시판, 정책 표시값
src/data/games.js          샘플 경기 일정 (2단계에서 실데이터로 교체)
src/components/            화면 컴포넌트 (home/, board/ 하위 포함)
```

화면 주소: `/` 홈, `/board/:게시판` 목록, `/board/:게시판/:글id` 상세, `/board/:게시판/write` 글쓰기, `/my` MY

## 4. 보안 설계

- `posts`, `comments`, `post_likes` 는 RLS를 켜고 정책을 두지 않아 브라우저에서 직접 읽거나 쓸 수 없습니다. 모든 접근은 RPC 함수로만 합니다.
- RPC 응답에는 작성자 id가 없습니다. 익명 글과 댓글은 서버에서 이미 "익명", "익명1", "익명(글쓴이)" 로 바뀐 이름만 내려옵니다.
- 팀 자유게시판은 서버가 호출자의 응원팀 기준으로만 보여 주고 쓰게 합니다. 다른 팀 게시판 글 id를 알아도 열 수 없습니다.
- 응원팀 변경(`change_team`)은 행 잠금(`FOR UPDATE`)으로 처리해, 요청을 동시에 여러 번 보내도 무료 변경은 한 번만 쓰입니다.
- 공감은 1인 1회(기본키, 내 글에도 가능), 글 10초 / 댓글 3초 간격 제한을 서버에서 검사합니다.
- 서로 다른 5명이 신고한 글·댓글은 자동으로 숨겨지고(`hidden_at`), 내가 차단한 사람의 글·댓글은 서버가 빼고 보냅니다. 익명 글에서 차단하면 그 사람의 익명 글만 가려서 익명 작성자가 드러나지 않게 합니다.
- 회원 탈퇴(`delete_account`)는 계정과 그 사람의 모든 데이터를 지웁니다. 가입할 때 약관 동의가 없으면 서버가 가입을 거부합니다.
- `profiles`, `attendance` 는 RLS 정책으로 본인 데이터만 다룹니다. 직관 기록은 내 현재 응원팀으로만 추가할 수 있습니다.
- anon 키는 공개되는 키라 괜찮지만, **service_role 키는 절대 프론트엔드에 넣지 마세요.**

## 5. 경기 일정 입력 (운영자)

앱 홈의 경기 카드는 `games` 테이블을 보여 줍니다. 일정 올리기, 매일 선발·결과 입력, 일정 변경 처리는 [docs/운영_경기관리.md](docs/운영_경기관리.md)를 보세요. (웹은 아직 샘플 일정을 씁니다)

## 5-1. 신고 처리 (운영자)

운영자 화면은 아직 없어서 SQL Editor에서 처리합니다. 스토어 심사 기준상 신고는 24시간 안에 확인하는 게 좋아요.

```sql
-- 확인 안 한 신고 (최근 순)
select r.created_at, r.reason, r.detail, r.post_id, r.comment_id,
       coalesce(p.title, c.body) as 내용, coalesce(p.hidden_at, c.hidden_at) as 숨김
  from public.reports r
  left join public.posts p on p.id = r.post_id
  left join public.comments c on c.id = r.comment_id
 where r.status = 'open'
 order by r.created_at desc;

-- 문제없는 글이면 다시 보이게 / 문제 있는 글이면 삭제
update public.posts set hidden_at = null where id = '글 id';
delete from public.posts where id = '글 id';

-- 처리 끝난 신고 닫기
update public.reports set status = 'resolved' where post_id = '글 id';
```

## 5-2. 금칙어 (운영자)

글 제목·본문, 댓글, 닉네임에 금칙어가 있으면 서버가 거부합니다. 숫자·기호를 끼운 변형("시1발", "f.u.c.k")도 걸러요. 띄어쓰기는 단어 경계로 봐서 "역시 발이 빠르다" 같은 정상 문장은 통과합니다.

```sql
-- 금칙어 추가 / 삭제
insert into public.banned_words (word) values ('새 금칙어');
delete from public.banned_words where word = '지울 단어';

-- 금칙어가 들어 있지만 정상적인 말 (잘못 걸리는 경우) 허용
insert into public.allowed_words (word) values ('시발점');

-- 검사해 보기
select public.has_banned_word('검사할 문장');

-- 금칙어 추가 전에 이미 올라온 글 찾기 (새 단어는 기존 글에 자동 적용되지 않음)
select id, board, title, created_at from public.posts
 where public.has_banned_word(title || ' ' || body) order by created_at desc;
select id, post_id, body, created_at from public.comments
 where public.has_banned_word(body) order by created_at desc;
```

목록은 앱·웹에 내려보내지 않습니다. 사용자가 우회하는 표현을 쓰면 신고로 들어오니, 신고 처리할 때 새 표현을 금칙어에 추가해 주세요.

## 6. 테스트 팁

유예 기간이나 잠금을 바로 확인하고 싶으면 SQL Editor에서 시간을 당기면 됩니다.

```sql
-- 24시간 유예 끝내기
update public.profiles set team_grace_until = now() - interval '1 minute' where username = '아이디';

-- 3개월 잠금 풀기
update public.profiles set team_locked_until = now() - interval '1 minute' where username = '아이디';
```

동시 요청 방어를 확인하려면, 유예 중인 계정으로 브라우저 콘솔에서 서로 다른 팀으로 `change_team` 을 동시에 두 번 호출해 보세요. 하나만 성공하고 나머지는 `team_locked` 로 거부돼야 합니다.

## 7. 알려진 한계 (다음 단계)

- 경기 일정은 아직 샘플이고, 진행 중 경기의 직관 결과를 사용자가 직접 고릅니다 → 2단계에서 실제 일정 연동 + 종료 후 자동 확정
- 대시보드에서 메타데이터 없이 직접 만든 사용자는 프로필 생성 트리거에서 거부됩니다 (앱의 회원가입으로만 가입)
- 아이디 기반 가입이라 비밀번호 찾기가 없습니다 → 3단계에서 복구 수단 검토
- 구장 게시판, 신고·차단·탈퇴 화면은 앱(`../yagutime-app`)에만 있습니다. 웹은 서버 변경에 맞춰 깨지지 않게만 고쳤어요
- 이용약관·개인정보처리방침(`src/constants/legal.js`)은 법률 검토 전 초안입니다
- 글 목록은 최근 50개까지만 보입니다 → 3단계에서 페이지네이션
