import { useState } from "react";
import { X, Check, Lock } from "lucide-react";
import { TEAMS, teamById, MUTED, FAINT, DANGER } from "../constants/theme";
import { TEAM_LOCK_MONTHS, GRACE_HOURS } from "../constants/policy";
import { addMonths, daysLeft, fullDate, hoursLeft, teamStatus } from "../lib/utils";
import { api, errorText } from "../lib/api";

export default function TeamModal({ t, profile, selectedId, onSelect, onDone, onClose, onLogout }) {
  const [step, setStep] = useState("pick"); // pick | confirm
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const { inGrace, locked, lockedUntil, graceUntil } = teamStatus(profile);
  const isChange = !!profile.team_id;
  const selected = selectedId ? teamById(selectedId) : null;
  const sameAsCurrent = isChange && selectedId === profile.team_id;
  const unlockAt = addMonths(Date.now(), TEAM_LOCK_MONTHS);

  async function confirm() {
    setBusy(true);
    setError("");
    try {
      const updated = await api.changeTeam(selectedId);
      onDone(updated);
    } catch (e) {
      setError(errorText(e));
      setStep("pick");
    } finally {
      setBusy(false);
    }
  }

  const title = locked
    ? "응원팀"
    : step === "confirm" ? `${selected.name}로 확정할까요?`
    : isChange ? "응원팀 변경" : "응원하는 팀을 골라 주세요";

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center sm:p-4"
      style={{ background: "rgba(0,0,0,0.6)" }}
      role="dialog" aria-modal="true" aria-labelledby="team-modal-title"
    >
      <div className="w-full max-w-md rounded-t-3xl sm:rounded-3xl p-5"
        style={{ background: t.surface, border: `1px solid ${t.line}`, transition: "background 300ms ease" }}>
        <div className="flex items-start justify-between gap-3">
          <h2 id="team-modal-title" className="text-xl font-extrabold" style={{ letterSpacing: "-0.02em" }}>{title}</h2>
          {onClose && (
            <button onClick={onClose} className="p-1 rounded-full shrink-0" aria-label="닫기" style={{ color: MUTED }}>
              <X size={20} />
            </button>
          )}
        </div>

        {locked ? (
          <>
            <div className="flex items-center gap-3 rounded-2xl p-4 mt-4" style={{ background: t.bg, border: `1px solid ${t.line}` }}>
              <span className="inline-flex w-10 h-10 rounded-xl items-center justify-center" style={{ background: t.raised, border: `2px solid ${t.accent}` }}>
                <Lock size={16} style={{ color: t.accent }} />
              </span>
              <div>
                <p className="font-bold">{teamById(profile.team_id).name}</p>
                <p className="text-xs mt-0.5" style={{ color: MUTED }}>
                  {fullDate(lockedUntil)}부터 바꿀 수 있어요 (D-{daysLeft(lockedUntil)})
                </p>
              </div>
            </div>
            <p className="text-sm mt-4" style={{ color: MUTED, lineHeight: 1.6 }}>
              팀 게시판을 건강하게 지키기 위해 응원팀은 처음 고른 뒤 {GRACE_HOURS}시간 안에 한 번만 바꿀 수 있고, 그 뒤로는 {TEAM_LOCK_MONTHS}개월 동안 바꿀 수 없어요.
            </p>
            <button onClick={onClose} className="w-full mt-4 rounded-xl py-3.5 font-bold" style={{ background: t.raised, border: `1px solid ${t.line}` }}>
              확인
            </button>
          </>
        ) : step === "confirm" ? (
          <>
            <div className="rounded-2xl p-4 mt-4" style={{ background: t.bg, border: `1px solid ${t.accent}` }}>
              <p className="flex items-center gap-2 font-bold">
                <Lock size={16} style={{ color: t.accent }} />
                {isChange
                  ? (inGrace ? "마지막 무료 변경이에요" : `${TEAM_LOCK_MONTHS}개월 동안 바꿀 수 없어요`)
                  : `${GRACE_HOURS}시간이 지나면 ${TEAM_LOCK_MONTHS}개월 동안 바꿀 수 없어요`}
              </p>
              <p className="text-sm mt-1.5" style={{ color: MUTED, lineHeight: 1.6 }}>
                {isChange
                  ? `${inGrace ? "무료 변경 1회를 사용해요. " : ""}이번에 바꾸면 ${fullDate(unlockAt)}까지 다시 바꿀 수 없어요. 이전 팀의 직관 기록은 그대로 보관돼요.`
                  : `실수로 골랐다면 ${GRACE_HOURS}시간 안에 한 번 바꿀 수 있어요. 그 뒤로는 ${fullDate(unlockAt)}까지 바꿀 수 없어요.`}
              </p>
            </div>
            <div className="grid grid-cols-2 gap-2 mt-4">
              <button onClick={() => setStep("pick")} disabled={busy} className="rounded-xl py-3.5 font-bold"
                style={{ background: t.raised, border: `1px solid ${t.line}` }}>
                다시 고르기
              </button>
              <button onClick={confirm} disabled={busy} className="rounded-xl py-3.5 font-bold"
                style={{ background: t.accent, color: t.onAccent, opacity: busy ? 0.6 : 1 }}>
                {busy ? "저장 중" : "확정하기"}
              </button>
            </div>
          </>
        ) : (
          <>
            <p className="text-sm mt-1" style={{ color: MUTED }}>
              {inGrace
                ? `가입 직후라 한 번 무료로 바꿀 수 있어요. ${hoursLeft(graceUntil)}시간 안에 정해 주세요.`
                : `고른 팀 컬러로 앱 테마가 바뀌어요. 확정 후 ${GRACE_HOURS}시간 안에 한 번 바꿀 수 있고, 그 뒤로는 ${TEAM_LOCK_MONTHS}개월 동안 바꿀 수 없어요.`}
            </p>
            <div className="grid grid-cols-2 gap-2 mt-5">
              {TEAMS.map((tm) => {
                const active = selectedId === tm.id;
                return (
                  <button key={tm.id} onClick={() => onSelect(tm.id)} aria-pressed={active}
                    className="flex items-center gap-3 rounded-xl px-3 py-3 text-left text-sm font-semibold"
                    style={{ background: active ? t.raised : t.bg, border: `1.5px solid ${active ? t.accent : t.line}` }}>
                    <span className="inline-flex shrink-0 w-7 h-7 rounded-lg items-center justify-center"
                      style={{ background: tm.surface, border: `2px solid ${tm.accent}` }}>
                      {active && <Check size={14} style={{ color: tm.accent }} strokeWidth={3} />}
                    </span>
                    {tm.name}
                  </button>
                );
              })}
            </div>
            {error && <p className="text-sm mt-3" style={{ color: DANGER }} role="alert">{error}</p>}
            <button
              disabled={!selected || sameAsCurrent}
              onClick={() => setStep("confirm")}
              className="w-full mt-4 rounded-xl py-3.5 text-base font-bold"
              style={{
                background: selected && !sameAsCurrent ? t.accent : t.line,
                color: selected && !sameAsCurrent ? t.onAccent : FAINT,
              }}
            >
              {!selected ? "팀을 선택해 주세요" : sameAsCurrent ? "지금 응원팀이에요" : `${selected.name}로 시작하기`}
            </button>
            {onLogout && (
              <button onClick={onLogout} className="w-full mt-2 py-2 text-xs" style={{ color: FAINT }}>
                다른 계정으로 로그인
              </button>
            )}
          </>
        )}
      </div>
    </div>
  );
}
