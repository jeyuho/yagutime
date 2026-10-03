const DAYS = ["일", "월", "화", "수", "목", "금", "토"];
const DAY = 86400000;

export const RESULT_LABEL = { W: "승", D: "무", L: "패" };

// 로컬 기준 YYYY-MM-DD
export function todayISO(d = new Date()) {
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${m}-${day}`;
}

export function todayLabel(d = new Date()) {
  return `${d.getMonth() + 1}월 ${d.getDate()}일 (${DAYS[d.getDay()]})`;
}

// 'YYYY-MM-DD' → 'M/D'
export const shortDateFromISO = (iso) => `${Number(iso.slice(5, 7))}/${Number(iso.slice(8, 10))}`;

export function fullDate(ts) {
  const d = new Date(ts);
  return `${d.getFullYear()}년 ${d.getMonth() + 1}월 ${d.getDate()}일`;
}

export const daysLeft = (ts) => Math.max(0, Math.ceil((ts - Date.now()) / DAY));
export const hoursLeft = (ts) => Math.max(1, Math.ceil((ts - Date.now()) / 3600000));

export function addMonths(ts, n) {
  const d = new Date(ts);
  d.setMonth(d.getMonth() + n);
  return d.getTime();
}

export function timeAgo(value) {
  const ts = typeof value === "string" ? Date.parse(value) : value;
  const min = Math.floor((Date.now() - ts) / 60000);
  if (min < 1) return "방금";
  if (min < 60) return `${min}분 전`;
  if (min < 1440) return `${Math.floor(min / 60)}시간 전`;
  const d = new Date(ts);
  return `${d.getMonth() + 1}/${d.getDate()}`;
}

// 야구식 승률 (.667). 무승부는 제외 (KBO 방식)
export function formatRate(w, l) {
  if (w + l === 0) return "-.---";
  const r = w / (w + l);
  return r === 1 ? "1.000" : r.toFixed(3).slice(1);
}

// 프로필 → 응원팀 잠금 상태 (표시용. 판정은 서버가 함)
export function teamStatus(profile) {
  const now = Date.now();
  const lockedUntil = profile?.team_locked_until ? Date.parse(profile.team_locked_until) : 0;
  const graceUntil = profile?.team_grace_until ? Date.parse(profile.team_grace_until) : 0;
  const inGrace = !!profile?.team_id && !profile.grace_used && graceUntil > now;
  const locked = !!profile?.team_id && lockedUntil > now && !inGrace;
  return { inGrace, locked, lockedUntil, graceUntil };
}

// 클라이언트 입력 검증 (서버도 같은 규칙을 다시 검사함)
export const ID_RE = /^[a-z0-9_]{4,16}$/;
export const NICK_RE = /^[가-힣a-zA-Z0-9_]{2,10}$/;
const RESERVED = ["익명", "운영자", "관리자", "야구타임"];

// 비밀번호 규칙은 여기서만 관리합니다. 회원가입 화면의 실시간 안내와 제출 검증이 모두 이 목록을 씁니다.
// 서버 기준은 Supabase Auth 비밀번호 설정이라, 규칙을 바꾸면 README의 대시보드 설정도 같이 맞춰 주세요.
export const PASSWORD_RULES = [
  { key: "length", label: "8자 이상", test: (pw) => pw.length >= 8 },
  { key: "upper", label: "대문자", test: (pw) => /[A-Z]/.test(pw) },
  { key: "lower", label: "소문자", test: (pw) => /[a-z]/.test(pw) },
  { key: "digit", label: "숫자", test: (pw) => /\d/.test(pw) },
];

export const checkPassword = (pw) => PASSWORD_RULES.map((r) => ({ ...r, ok: r.test(pw) }));

export function validateSignup({ username, password, confirm, nickname }) {
  const e = {};
  if (!ID_RE.test(username)) e.username = "영문 소문자, 숫자, _ 조합 4~16자로 입력해 주세요.";
  if (!PASSWORD_RULES.every((r) => r.test(password))) e.password = "비밀번호 조건을 모두 채워 주세요.";
  if (confirm !== password) e.confirm = "비밀번호가 서로 달라요.";
  if (!NICK_RE.test(nickname)) e.nickname = "한글, 영문, 숫자 2~10자로 입력해 주세요.";
  else if (RESERVED.some((w) => nickname.toLowerCase().includes(w))) e.nickname = "사용할 수 없는 단어가 들어 있어요.";
  return e;
}

// 게시판 정렬. list_posts는 최신순만 주므로 인기순은 받아 온 글 안에서 다시 정렬함
export const SORTS = [
  { value: "new", label: "최신순" },
  { value: "hot", label: "인기순" },
];

export function sortPosts(posts, sort) {
  if (sort !== "hot") return posts;
  return [...posts].sort(
    (a, b) => Number(b.like_count) - Number(a.like_count) || Date.parse(b.created_at) - Date.parse(a.created_at)
  );
}
