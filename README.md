# 야구타임 (1단계: 데이터와 보안)

KBO 팬 커뮤니티 웹 앱. React(Vite) + Supabase.

## 1. Supabase 준비

1. [supabase.com](https://supabase.com)에서 새 프로젝트를 만듭니다. 지역은 가까운 곳(예: Northeast Asia, Seoul)을 고르세요.
2. **이메일 확인 끄기.** 이 앱은 아이디를 내부용 이메일(`아이디@users.yagutime.app`)로 바꿔 가입시키기 때문에, 확인 메일이 실제로 갈 수 없습니다.
   Authentication 메뉴의 Email 공급자 설정에서 **Confirm email** 을 끄세요.
3. **비밀번호 규칙 맞추기.** Authentication 설정의 비밀번호 항목에서 최소 길이를 8로, 요구 조건을 "소문자, 대문자, 숫자"(Lowercase, uppercase letters and digits)로 설정하세요. 앱에서도 같은 규칙(`src/lib/utils.js` 의 `PASSWORD_RULES`)을 검사하지만 서버 설정이 최종 기준이에요.
4. **스키마 실행.** SQL Editor를 열고 `supabase/schema.sql` 전체를 붙여 넣어 실행합니다.
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
- 공감은 1인 1회(기본키), 내 글 공감 금지, 글 10초 / 댓글 3초 간격 제한을 서버에서 검사합니다.
- `profiles`, `attendance` 는 RLS 정책으로 본인 데이터만 다룹니다. 직관 기록은 내 현재 응원팀으로만 추가할 수 있습니다.
- anon 키는 공개되는 키라 괜찮지만, **service_role 키는 절대 프론트엔드에 넣지 마세요.**

## 5. 테스트 팁

유예 기간이나 잠금을 바로 확인하고 싶으면 SQL Editor에서 시간을 당기면 됩니다.

```sql
-- 24시간 유예 끝내기
update public.profiles set team_grace_until = now() - interval '1 minute' where username = '아이디';

-- 3개월 잠금 풀기
update public.profiles set team_locked_until = now() - interval '1 minute' where username = '아이디';
```

동시 요청 방어를 확인하려면, 유예 중인 계정으로 브라우저 콘솔에서 서로 다른 팀으로 `change_team` 을 동시에 두 번 호출해 보세요. 하나만 성공하고 나머지는 `team_locked` 로 거부돼야 합니다.

## 6. 알려진 한계 (다음 단계)

- 경기 일정은 아직 샘플이고, 진행 중 경기의 직관 결과를 사용자가 직접 고릅니다 → 2단계에서 실제 일정 연동 + 종료 후 자동 확정
- 대시보드에서 메타데이터 없이 직접 만든 사용자는 프로필 생성 트리거에서 거부됩니다 (앱의 회원가입으로만 가입)
- 아이디 기반 가입이라 비밀번호 찾기가 없습니다 → 3단계에서 복구 수단 검토
- 글 목록은 최근 50개까지만 보입니다 → 3단계에서 페이지네이션
