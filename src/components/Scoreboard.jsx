import { TEXT, MUTED, FAINT } from "../constants/theme";
import { formatRate } from "../lib/utils";

export default function Scoreboard({ records, t, large }) {
  const w = records.filter((r) => r.result === "W").length;
  const d = records.filter((r) => r.result === "D").length;
  const l = records.filter((r) => r.result === "L").length;
  const decided = w + l;
  const r = decided ? w / decided : 0;
  const verdict =
    decided < 3 ? "직관을 3경기 이상 기록하면 승리요정 판정이 나와요."
    : r >= 0.6 ? "승리요정 인증. 다음 직관도 꼭 가 주세요."
    : r <= 0.4 ? "패배요정 주의보. 이번엔 집관으로 기운을 바꿔 볼까요?"
    : "반반 요정. 오늘 직관이 운명을 가릅니다.";

  return (
    <div className="rounded-2xl overflow-hidden" style={{ background: "rgba(0,0,0,0.38)", border: `1px solid ${t.line}` }}>
      <div className="grid" style={{ gridTemplateColumns: "1fr 1fr 1fr 1.6fr" }}>
        {[["승", w], ["무", d], ["패", l]].map(([label, v]) => (
          <div key={label} className="text-center py-3" style={{ borderRight: `1px solid ${t.line}` }}>
            <p className="text-xs font-semibold" style={{ color: FAINT }}>{label}</p>
            <p className={`${large ? "text-4xl" : "text-3xl"} font-extrabold mt-1`} style={{ fontVariantNumeric: "tabular-nums", color: TEXT }}>
              {v}
            </p>
          </div>
        ))}
        <div className="text-center py-3" style={{ background: "rgba(255,255,255,0.03)" }}>
          <p className="text-xs font-semibold" style={{ color: FAINT }}>직관 승률</p>
          <p
            className={`${large ? "text-5xl" : "text-4xl"} font-black mt-1`}
            style={{ fontVariantNumeric: "tabular-nums", color: t.accent, textShadow: `0 0 18px ${t.accent}55`, letterSpacing: "-0.02em" }}
          >
            {formatRate(w, l)}
          </p>
        </div>
      </div>
      <p className="text-xs px-4 py-2.5" style={{ color: MUTED, borderTop: `1px solid ${t.line}` }}>{verdict}</p>
    </div>
  );
}
