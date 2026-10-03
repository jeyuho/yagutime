import { useState } from "react";
import { MapPin, Check, X, Ticket } from "lucide-react";
import { teamById, TEXT, MUTED, FAINT } from "../../constants/theme";
import { RESULT_LABEL } from "../../lib/utils";
import { ResultChip } from "../common";

function StatusPill({ game, t }) {
  if (game.status === "live")
    return (
      <span className="flex items-center gap-1.5 font-bold" style={{ color: t.accent }}>
        <span className="inline-block w-1.5 h-1.5 rounded-full" style={{ background: t.accent, animation: "ytPulse 1.4s ease-in-out infinite" }} />
        {game.inning} 진행 중
      </span>
    );
  return <span className="font-semibold" style={{ color: MUTED }}>{game.status === "final" ? "경기 종료" : `${game.time} 시작`}</span>;
}

export default function GameCard({ game, team, t, record, onAttend, onUndo }) {
  const [picking, setPicking] = useState(false);
  const [busy, setBusy] = useState(false);
  const away = teamById(game.away);
  const home = teamById(game.home);
  const mine = game.away === team.id || game.home === team.id;
  const hasScore = game.status !== "scheduled";
  const isFinal = game.status === "final";
  const winnerScore = hasScore ? Math.max(game.score.away, game.score.home) : null;

  function finalResult() {
    const my = game.home === team.id ? game.score.home : game.score.away;
    const opp = game.home === team.id ? game.score.away : game.score.home;
    return my > opp ? "W" : my < opp ? "L" : "D";
  }

  async function run(fn) {
    setBusy(true);
    try { await fn(); } finally { setBusy(false); }
  }

  return (
    <article
      className="rounded-2xl p-4"
      style={{ background: t.surface, border: `1px solid ${mine ? t.accent : t.line}`, boxShadow: mine ? `inset 4px 0 0 ${t.accent}` : "none" }}
    >
      <div className="flex items-center justify-between mb-3 text-xs">
        <span className="flex items-center gap-1" style={{ color: MUTED }}><MapPin size={12} />{game.stadium}</span>
        <StatusPill game={game} t={t} />
      </div>

      <div className="flex flex-col gap-1.5">
        {[{ tm: away, score: game.score?.away, tag: "원정" }, { tm: home, score: game.score?.home, tag: "홈" }].map(({ tm, score, tag }) => {
          const dim = isFinal && score < winnerScore;
          return (
            <div key={tm.id} className="flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <span className="inline-block w-3 h-3 rounded-sm" style={{ background: tm.accent }} />
                <span className="text-base font-bold" style={{ color: dim ? MUTED : TEXT }}>{tm.name}</span>
                <span className="text-xs" style={{ color: FAINT }}>{tag}</span>
              </div>
              <span className="text-2xl font-extrabold" style={{ fontVariantNumeric: "tabular-nums", color: dim ? MUTED : TEXT, minWidth: 28, textAlign: "right" }}>
                {hasScore ? score : "–"}
              </span>
            </div>
          );
        })}
      </div>

      {mine && (
        <div className="mt-4 pt-3" style={{ borderTop: `1px dashed ${t.line}` }}>
          {record ? (
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-2 text-sm font-semibold">
                <Check size={16} style={{ color: t.accent }} strokeWidth={3} />직관 기록 완료<ResultChip result={record.result} t={t} />
              </span>
              <button onClick={() => run(() => onUndo(game.id))} disabled={busy} className="text-xs font-semibold px-2 py-1" style={{ color: MUTED }}>
                기록 취소
              </button>
            </div>
          ) : picking ? (
            <div>
              <div className="flex items-center justify-between">
                <p className="text-sm font-semibold">오늘 결과를 골라 주세요</p>
                <button onClick={() => setPicking(false)} aria-label="결과 선택 닫기" style={{ color: MUTED }}><X size={16} /></button>
              </div>
              <p className="text-xs mt-0.5" style={{ color: MUTED }}>아직 경기가 끝나지 않아 직접 선택해요.</p>
              <div className="grid grid-cols-3 gap-2 mt-2.5">
                {["W", "D", "L"].map((r) => (
                  <button
                    key={r}
                    disabled={busy}
                    onClick={() => run(async () => { await onAttend(game, r); setPicking(false); })}
                    className="rounded-lg py-2 text-sm font-bold"
                    style={{ background: r === "W" ? t.accent : t.raised, color: r === "W" ? t.onAccent : TEXT, border: `1px solid ${r === "W" ? t.accent : t.line}` }}
                  >
                    {RESULT_LABEL[r]}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <button
              disabled={busy}
              onClick={() => (isFinal ? run(() => onAttend(game, finalResult())) : setPicking(true))}
              className="w-full flex items-center justify-center gap-2 rounded-xl py-2.5 text-sm font-bold"
              style={{ background: t.accent, color: t.onAccent, opacity: busy ? 0.6 : 1 }}
            >
              <Ticket size={16} />오늘 경기 직관 완료
            </button>
          )}
        </div>
      )}
    </article>
  );
}
