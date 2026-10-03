import { useState } from "react";
import { Lock, LogOut, User, EyeOff, X } from "lucide-react";
import { teamById, MUTED, FAINT, DANGER } from "../constants/theme";
import { api, errorText } from "../lib/api";
import { daysLeft, fullDate, hoursLeft, shortDateFromISO, teamStatus } from "../lib/utils";
import { Segmented, SectionTitle, ResultChip } from "./common";
import Scoreboard from "./Scoreboard";

export default function MyView({ profile, setProfile, team, t, records, onRemoveRecord, onChangeTeam }) {
  const { inGrace, locked, lockedUntil, graceUntil } = teamStatus(profile);
  const [error, setError] = useState("");

  async function setDefaultAnon(v) {
    setError("");
    try {
      setProfile(await api.setDefaultAnon(v));
    } catch (e) {
      setError(errorText(e));
    }
  }

  return (
    <>
      <section className="rounded-2xl p-4 mt-5" style={{ background: t.surface, border: `1px solid ${t.line}` }}>
        <div className="flex items-center justify-between">
          <div>
            <p className="text-lg font-bold">{profile.nickname}</p>
            <p className="text-xs mt-0.5" style={{ color: FAINT }}>@{profile.username}</p>
          </div>
          <button onClick={() => api.signOut()} className="flex items-center gap-1 text-xs font-semibold px-2 py-1" style={{ color: MUTED }}>
            <LogOut size={14} />로그아웃
          </button>
        </div>

        <div className="flex items-center justify-between mt-4 pt-4" style={{ borderTop: `1px solid ${t.line}` }}>
          <div>
            <p className="text-xs" style={{ color: FAINT }}>응원팀</p>
            <p className="text-sm font-bold mt-0.5">{team.name}</p>
            <p className="text-xs mt-0.5" style={{ color: MUTED }}>
              {inGrace
                ? `무료 변경 1회 남음 (${hoursLeft(graceUntil)}시간 안에)`
                : locked
                ? `${fullDate(lockedUntil)}부터 변경 가능 (D-${daysLeft(lockedUntil)})`
                : "지금 변경할 수 있어요"}
            </p>
          </div>
          <button onClick={onChangeTeam} className="flex items-center gap-1 rounded-lg px-3 py-1.5 text-xs font-bold"
            style={{ border: `1px solid ${t.line}`, color: locked ? FAINT : undefined }}>
            {locked && <Lock size={12} />}팀 변경
          </button>
        </div>

        <div className="mt-4 pt-4" style={{ borderTop: `1px solid ${t.line}` }}>
          <p className="text-xs mb-2" style={{ color: FAINT }}>기본 활동 방식</p>
          <Segmented t={t} value={profile.default_anon} onChange={setDefaultAnon}
            options={[{ value: false, label: "닉네임으로", icon: <User size={14} /> }, { value: true, label: "익명으로", icon: <EyeOff size={14} /> }]} />
          {error && <p className="text-xs mt-2" style={{ color: DANGER }}>{error}</p>}
        </div>
      </section>

      <SectionTitle sub="무승부는 승률 계산에서 빠져요.">{team.short} 직관 성적</SectionTitle>
      <Scoreboard records={records} t={t} large />

      <SectionTitle sub={`총 ${records.length}경기`}>직관 일지</SectionTitle>
      {records.length === 0 ? (
        <p className="text-sm rounded-2xl px-4 py-8 text-center" style={{ background: t.surface, border: `1px solid ${t.line}`, color: MUTED }}>
          아직 기록이 없어요. 홈에서 오늘 경기 직관 완료를 눌러 첫 기록을 남겨 보세요.
        </p>
      ) : (
        <ul className="rounded-2xl overflow-hidden" style={{ background: t.surface, border: `1px solid ${t.line}` }}>
          {records.map((r, i) => (
            <li key={r.id} className="flex items-center gap-3 px-4 py-3" style={{ borderTop: i ? `1px solid ${t.line}` : "none" }}>
              <ResultChip result={r.result} t={t} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold">
                  vs {teamById(r.opponent).name}
                  {r.score && <span className="ml-2" style={{ color: MUTED, fontVariantNumeric: "tabular-nums" }}>{r.score}</span>}
                </p>
                <p className="text-xs mt-0.5 truncate" style={{ color: FAINT }}>{shortDateFromISO(r.game_date)} {r.stadium}</p>
              </div>
              <button onClick={() => onRemoveRecord(r.id)} aria-label="기록 삭제" className="p-1" style={{ color: FAINT }}><X size={16} /></button>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
