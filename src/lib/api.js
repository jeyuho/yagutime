import { supabase } from "./supabase";

// Supabase Auth는 이메일 기반이라, 아이디를 내부용 이메일로 바꿔서 씁니다.
// 실제로 메일이 가는 주소가 아니므로 대시보드에서 이메일 확인(Confirm email)을 꺼야 합니다.
const EMAIL_DOMAIN = "users.yagutime.app";
export const toEmail = (username) => `${username.trim().toLowerCase()}@${EMAIL_DOMAIN}`;

const ERROR_TEXT = {
  not_authenticated: "다시 로그인해 주세요.",
  team_locked: "아직 응원팀을 바꿀 수 없어요.",
  same_team: "지금 응원팀이에요.",
  invalid_team: "알 수 없는 팀이에요.",
  team_required: "응원팀을 먼저 골라 주세요.",
  invalid_board: "알 수 없는 게시판이에요.",
  invalid_meta: "입력값을 다시 확인해 주세요.",
  too_fast: "너무 빨라요. 잠시 후 다시 시도해 주세요.",
  terms_required: "필수 약관에 모두 동의해 주세요.",
  banned_word: "사용할 수 없는 표현이 들어 있어요. 고쳐서 다시 올려 주세요.",
  not_found: "글을 찾을 수 없어요.",
  nickname_reserved: "사용할 수 없는 닉네임이에요.",
  weak_password: "비밀번호 조건을 모두 채워 주세요.",
  "duplicate key": "이미 기록했어요.",
  "User already registered": "이미 사용 중인 아이디예요.",
  "Failed to fetch": "서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.",
};

export function errorText(err) {
  const msg = `${err?.message ?? ""} ${err?.code ?? ""}`;
  if (err?.code === "23505") return ERROR_TEXT["duplicate key"];
  const key = Object.keys(ERROR_TEXT).find((k) => msg.includes(k));
  return key ? ERROR_TEXT[key] : "문제가 생겼어요. 잠시 후 다시 시도해 주세요.";
}

async function rpc(name, args) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  return data;
}

async function q(promise) {
  const { data, error } = await promise;
  if (error) throw error;
  return data;
}

export const api = {
  /* ---------- 인증 ---------- */
  async checkSignup(username, nickname) {
    const rows = await rpc("check_signup_available", { p_username: username, p_nickname: nickname });
    return rows?.[0] ?? { username_taken: false, nickname_taken: false, nickname_reserved: false };
  },
  // termsAgreed: 이용약관, 개인정보처리방침, 만 14세 이상 모두 동의. 서버(handle_new_user)가 없으면 가입을 거부함
  async signUp({ username, password, nickname, defaultAnon, termsAgreed }) {
    const { data, error } = await supabase.auth.signUp({
      email: toEmail(username),
      password,
      options: { data: { username: username.toLowerCase(), nickname, default_anon: defaultAnon, terms_agreed: termsAgreed === true } },
    });
    if (error) throw error;
    // 이메일 확인이 켜져 있으면 세션이 없음 → 설정 안내
    if (!data.session) throw new Error("email_confirm_on");
  },
  async signIn(username, password) {
    const { error } = await supabase.auth.signInWithPassword({ email: toEmail(username), password });
    if (error) throw error;
  },
  signOut: () => supabase.auth.signOut(),

  /* ---------- 프로필 / 응원팀 ---------- */
  getProfile: (uid) => q(supabase.from("profiles").select("*").eq("id", uid).maybeSingle()),
  changeTeam: (teamId) => rpc("change_team", { p_team: teamId }),
  setDefaultAnon: (value) => rpc("set_default_anon", { p_value: value }),

  /* ---------- 게시판 ---------- */
  listPosts: (board, limit = 50) => rpc("list_posts", { p_board: board, p_limit: limit }),
  async getPost(id) {
    const rows = await rpc("get_post", { p_id: id });
    return rows?.[0] ?? null;
  },
  createPost: (board, { title, body, anon, meta }) =>
    rpc("create_post", { p_board: board, p_title: title, p_body: body, p_is_anon: anon, p_meta: meta }),
  deletePost: (id) => rpc("delete_post", { p_id: id }),
  toggleLike: (postId) => rpc("toggle_like", { p_post: postId }),
  listComments: (postId) => rpc("list_comments", { p_post: postId }),
  createComment: (postId, { body, anon }) =>
    rpc("create_comment", { p_post: postId, p_body: body, p_is_anon: anon }),

  /* ---------- 직관 기록 (RLS로 본인 것만) ---------- */
  listAttendance: (teamId) =>
    q(supabase.from("attendance").select("*").eq("team_id", teamId).order("game_date", { ascending: false }).order("created_at", { ascending: false })),
  addAttendance: (row) => q(supabase.from("attendance").insert(row)),
  removeAttendance: (id) => q(supabase.from("attendance").delete().eq("id", id)),
  undoAttendance: (teamId, gameId) =>
    q(supabase.from("attendance").delete().eq("team_id", teamId).eq("game_id", gameId)),
};
