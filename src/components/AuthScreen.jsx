import { useState } from "react";
import { User, EyeOff, Check, Circle } from "lucide-react";
import { MUTED, FAINT, DANGER } from "../constants/theme";
import { api, errorText } from "../lib/api";
import { validateSignup, checkPassword } from "../lib/utils";
import { LEGAL_DOCS } from "../constants/legal";
import { Segmented, fieldStyle } from "./common";

const SIGNUP_FIELDS = [
  { k: "username", label: "아이디", placeholder: "아이디", ac: "username",
    hint: "영문 소문자, 숫자, 밑줄(_)로 4~16자. 로그인할 때 쓰고 다른 사람에게는 보이지 않아요." },
  { k: "password", label: "비밀번호", placeholder: "아래 조건을 모두 채워 주세요", type: "password", ac: "new-password" },
  { k: "confirm", label: "비밀번호 확인", placeholder: "한 번 더 입력", type: "password", ac: "new-password" },
  { k: "nickname", label: "닉네임", placeholder: "예: 창원직관러", ac: "nickname",
    hint: "게시판에 보이는 이름이에요. 한글, 영문, 숫자로 2~10자." },
];

export default function AuthScreen({ t }) {
  const [mode, setMode] = useState("login");
  const [busy, setBusy] = useState(false);

  const [loginId, setLoginId] = useState("");
  const [loginPw, setLoginPw] = useState("");
  const [loginError, setLoginError] = useState("");

  const [form, setForm] = useState({ username: "", password: "", confirm: "", nickname: "", defaultAnon: true });
  const [errors, setErrors] = useState({});
  const [formError, setFormError] = useState("");
  // 필수 동의: 이용약관, 개인정보 수집·이용, 만 14세 이상 (앱 signup.jsx 와 같은 항목)
  const [agreed, setAgreed] = useState({ terms: false, privacy: false, age: false });
  const allAgreed = agreed.terms && agreed.privacy && agreed.age;
  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));

  async function submitLogin() {
    if (!loginId.trim() || !loginPw) return setLoginError("아이디와 비밀번호를 입력해 주세요.");
    setBusy(true);
    setLoginError("");
    try {
      await api.signIn(loginId, loginPw);
      // 성공하면 useAuth가 세션 변화를 감지해 화면이 바뀜
    } catch (e) {
      // 아이디 존재 여부를 드러내지 않도록 같은 문구 사용
      setLoginError(e?.message?.includes("fetch") ? errorText(e) : "아이디 또는 비밀번호가 맞지 않아요.");
    } finally {
      setBusy(false);
    }
  }

  async function submitSignup() {
    const values = { ...form, username: form.username.trim().toLowerCase(), nickname: form.nickname.trim() };
    const errs = validateSignup(values);
    setErrors(errs);
    setFormError("");
    if (Object.keys(errs).length) return;
    if (!allAgreed) return setFormError("필수 약관에 모두 동의해 주세요.");

    setBusy(true);
    try {
      const check = await api.checkSignup(values.username, values.nickname);
      const dup = {};
      if (check.username_taken) dup.username = "이미 사용 중인 아이디예요.";
      if (check.nickname_taken) dup.nickname = "이미 사용 중인 닉네임이에요.";
      if (check.nickname_reserved) dup.nickname = "사용할 수 없는 단어가 들어 있어요.";
      if (Object.keys(dup).length) {
        setErrors(dup);
        return;
      }
      await api.signUp({ ...values, termsAgreed: allAgreed });
    } catch (e) {
      setFormError(
        e?.message === "email_confirm_on"
          ? "Supabase에서 이메일 확인(Confirm email)이 켜져 있어요. README의 설정 방법을 확인해 주세요."
          : errorText(e)
      );
    } finally {
      setBusy(false);
    }
  }

  const onEnter = (fn) => (e) => e.key === "Enter" && !e.nativeEvent.isComposing && fn();

  return (
    <div className="px-5 pt-16 pb-10">
      <h1 className="text-4xl font-black" style={{ letterSpacing: "-0.04em" }}>야구타임</h1>
      <p className="text-sm mt-2" style={{ color: MUTED }}>KBO 팬들이 모이는 우리 팀 커뮤니티</p>

      <div className="mt-8">
        <Segmented
          t={t}
          value={mode}
          onChange={(m) => { setMode(m); setLoginError(""); setErrors({}); setFormError(""); }}
          options={[{ value: "login", label: "로그인" }, { value: "signup", label: "회원가입" }]}
        />
      </div>

      {mode === "login" ? (
        <div className="flex flex-col gap-3 mt-5">
          <input value={loginId} onChange={(e) => setLoginId(e.target.value)} onKeyDown={onEnter(submitLogin)}
            placeholder="아이디" autoComplete="username" autoCapitalize="none" style={fieldStyle(t)} aria-label="아이디" />
          <input value={loginPw} onChange={(e) => setLoginPw(e.target.value)} onKeyDown={onEnter(submitLogin)}
            type="password" placeholder="비밀번호" autoComplete="current-password" style={fieldStyle(t)} aria-label="비밀번호" />
          {loginError && <p className="text-sm" style={{ color: DANGER }} role="alert">{loginError}</p>}
          <button onClick={submitLogin} disabled={busy} className="rounded-xl py-3.5 font-bold mt-1"
            style={{ background: t.accent, color: t.onAccent, opacity: busy ? 0.6 : 1 }}>
            {busy ? "로그인 중" : "로그인"}
          </button>
        </div>
      ) : (
        <div className="flex flex-col gap-4 mt-5">
          {SIGNUP_FIELDS.map((f) => (
            <div key={f.k} className="flex flex-col gap-1.5">
              <label htmlFor={`signup-${f.k}`} className="text-sm font-semibold">{f.label}</label>
              <input
                id={`signup-${f.k}`}
                value={form[f.k]} onChange={set(f.k)} type={f.type ?? "text"} placeholder={f.placeholder}
                autoComplete={f.ac} autoCapitalize="none" style={fieldStyle(t, !!errors[f.k])} aria-invalid={!!errors[f.k]}
                aria-describedby={f.k === "password" ? "signup-password-rules" : f.hint ? `signup-${f.k}-hint` : undefined}
              />
              {f.k === "password" && (
                <PasswordRules id="signup-password-rules" t={t} password={form.password} showMissing={!!errors.password} />
              )}
              {errors[f.k] ? (
                <span className="text-xs" style={{ color: DANGER }}>{errors[f.k]}</span>
              ) : (
                f.hint && <span id={`signup-${f.k}-hint`} className="text-xs" style={{ color: FAINT, lineHeight: 1.5 }}>{f.hint}</span>
              )}
            </div>
          ))}

          <div className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold">기본 활동 방식</span>
            <Segmented
              t={t}
              value={form.defaultAnon}
              onChange={(v) => setForm((f) => ({ ...f, defaultAnon: v }))}
              options={[
                { value: false, label: "닉네임으로", icon: <User size={14} /> },
                { value: true, label: "익명으로", icon: <EyeOff size={14} /> },
              ]}
            />
            <span className="text-xs" style={{ color: FAINT }}>글이나 댓글을 쓸 때마다 바꿀 수 있어요.</span>
          </div>

          <div className="flex flex-col gap-2 rounded-xl p-3" style={{ border: `1px solid ${t.line}` }}>
            <label className="flex items-center gap-2 text-sm font-bold">
              <input type="checkbox" checked={allAgreed} style={{ accentColor: t.accent }}
                onChange={() => setAgreed({ terms: !allAgreed, privacy: !allAgreed, age: !allAgreed })} />
              필수 항목 모두 동의
            </label>
            {[["terms", "(필수) 이용약관 동의", "terms"], ["privacy", "(필수) 개인정보 수집·이용 동의", "privacy"], ["age", "(필수) 만 14세 이상이에요", null]].map(([k, label, doc]) => (
              <div key={k} className="text-sm">
                <label className="flex items-center gap-2">
                  <input type="checkbox" checked={agreed[k]} style={{ accentColor: t.accent }}
                    onChange={() => setAgreed((a) => ({ ...a, [k]: !a[k] }))} />
                  {label}
                </label>
                {doc && (
                  <details className="ml-6 mt-1">
                    <summary className="text-xs cursor-pointer" style={{ color: MUTED }}>전문 보기</summary>
                    <div className="mt-2 max-h-48 overflow-y-auto text-xs whitespace-pre-wrap" style={{ color: MUTED, lineHeight: 1.6 }}>
                      {LEGAL_DOCS[doc].sections.map(([h, body]) => `${h}\n${body}`).join("\n\n")}
                    </div>
                  </details>
                )}
              </div>
            ))}
          </div>

          {formError && <p className="text-sm" style={{ color: DANGER }} role="alert">{formError}</p>}

          <button onClick={submitSignup} disabled={busy} className="rounded-xl py-3.5 font-bold"
            style={{ background: t.accent, color: t.onAccent, opacity: busy ? 0.6 : 1 }}>
            {busy ? "가입하는 중" : "가입하고 응원팀 고르기"}
          </button>
        </div>
      )}
    </div>
  );
}

// 비밀번호 조건 실시간 안내. 규칙 목록은 utils.js의 PASSWORD_RULES 에서 옴
function PasswordRules({ id, t, password, showMissing }) {
  return (
    <ul id={id} className="flex flex-wrap gap-x-3 gap-y-1">
      {checkPassword(password).map((r) => {
        const Icon = r.ok ? Check : Circle;
        const color = r.ok ? t.accent : showMissing ? DANGER : FAINT;
        return (
          <li key={r.key} className="flex items-center gap-1 text-xs" style={{ color, transition: "color 150ms ease" }}>
            <Icon size={12} strokeWidth={r.ok ? 3 : 2} aria-hidden="true" />
            {r.label}
            <span className="sr-only">{r.ok ? " 충족" : " 미충족"}</span>
          </li>
        );
      })}
    </ul>
  );
}
