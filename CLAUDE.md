# 야구타임

KBO 팬 커뮤니티 웹 앱. React 18 + Vite 6 + Tailwind v4 + Supabase(Auth, Postgres RPC). 모바일 우선(max-w-md) 다크 UI. 현재 1단계(데이터와 보안).

## 명령어

```bash
npm run dev      # 개발 서버 (http://localhost:5173)
npm run build    # 프로덕션 빌드 (dist/)
```

테스트·린트 설정은 없습니다. 변경 후에는 `npm run build` 로 최소한 컴파일을 확인하세요.
`.env.local` 에 `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` 가 없으면 앱은 설정 안내 화면만 띄웁니다 (`src/lib/supabase.js` 의 `configError`).

## 구조

```
supabase/schema.sql      테이블, RLS 정책, RPC 함수, 가입 트리거 (SQL Editor에서 통째로 실행)
src/App.jsx              라우터 루트. 로그인/프로필/응원팀 상태에 따라 AuthScreen · TeamModal · Shell 분기
src/hooks/useAuth.js     세션 + profiles 행 로드
src/lib/api.js           모든 서버 호출(api 객체)과 에러 코드 → 한국어 문구(errorText)
src/lib/utils.js         날짜/승률 포맷, 응원팀 잠금 상태, 가입 입력 검증(ID_RE, NICK_RE, PASSWORD_RULES)
src/constants/theme.js   색 토큰, 10개 구단 테마(TEAMS), 게시판 정의(BOARDS)
src/constants/policy.js  응원팀 잠금/유예 표시값 (schema.sql 의 policy_* 함수와 맞춰야 함)
src/data/games.js        샘플 경기 일정 (2단계에서 실데이터로 교체 예정)
src/components/          화면. common.jsx 에 공용 UI(Segmented, fieldStyle, Spinner 등)
  home/, board/          홈(경기 카드·스코어보드), 게시판(목록·상세·글쓰기)
```

라우트: `/` 홈, `/board/:board`, `/board/:board/:id`, `/board/:board/write`, `/my`

## 보안 규칙 (깨면 안 됨)

- `posts`, `comments`, `post_likes` 는 RLS on + 정책 없음 → **클라이언트에서 `supabase.from()` 으로 직접 접근하지 말고 RPC만 사용**. 새 기능도 `schema.sql` 에 `security definer` RPC를 추가하고 `api.js` 에서 호출.
- RPC 응답에 작성자 id를 넣지 않음. 익명 이름("익명", "익명1", "익명(글쓴이)")은 서버에서 만듦.
- 팀 게시판 접근, 응원팀 변경(`FOR UPDATE` 잠금), 공감/작성 간격 제한은 모두 서버가 판정. 클라이언트 값은 표시용.
- `profiles`, `attendance` 만 RLS 정책으로 본인 행 직접 접근 허용.
- service_role 키는 절대 프론트엔드/`.env` 에 넣지 않음. anon 키만 사용.

## 클라이언트-서버 짝 맞추기

같은 규칙이 양쪽에 있으므로 한쪽을 바꾸면 다른 쪽도 같이 바꿀 것:

| 클라이언트 | 서버 |
|---|---|
| `utils.js` `ID_RE`, `NICK_RE`, 예약어 `RESERVED` | `schema.sql` profiles check 제약, `is_reserved_nickname` |
| `utils.js` `PASSWORD_RULES` | Supabase 대시보드 Auth 비밀번호 설정 (README 1-3) |
| `constants/policy.js` | `schema.sql` `policy_team_lock`, `policy_team_grace` |
| `api.js` `ERROR_TEXT` 키 | RPC가 `raise exception` 하는 코드 문자열 |

## 인증

Supabase Auth는 이메일 기반이라 아이디를 `아이디@users.yagutime.app` 으로 바꿔 가입(`api.js` `toEmail`). 대시보드에서 Confirm email을 꺼야 함. 가입 시 메타데이터(username, nickname, default_anon)로 `handle_new_user` 트리거가 profiles 행을 만듦.
로그인 실패 문구는 아이디 존재 여부를 드러내지 않도록 항상 같은 문구 사용.

## 코드 스타일

- 함수형 컴포넌트, 기본 export는 화면 컴포넌트. 스타일은 Tailwind 클래스(레이아웃) + 인라인 `style`(팀 테마 색 `t.*`, `MUTED`/`FAINT`/`DANGER`).
- 팀 테마 객체 `t` 를 props로 내려받아 색을 씀. 하드코딩 색 대신 theme.js 토큰 사용.
- UI 문구와 주석은 한국어, 해요체("~해 주세요", "~예요"). 주석은 짧게, 이유가 필요한 곳에만.
- 아이콘은 `lucide-react` (0.383.0 고정).
