import { teamById, TEXT, MUTED, FAINT } from "../../constants/theme";

// 홈 가로 스크롤용 작은 경기 카드
export default function GameMini({ game, t }) {
  const hasScore = game.status !== "scheduled";
  const isFinal = game.status === "final";
  const winnerScore = hasScore ? Math.max(game.score.away, game.score.home) : null;

  return (
    <article className="shrink-0 w-32 rounded-xl p-3" style={{ background: t.surface, border: `1px solid ${t.line}` }}>
      {[{ tm: teamById(game.away), score: game.score?.away }, { tm: teamById(game.home), score: game.score?.home }].map(({ tm, score }) => {
        const dim = isFinal && score < winnerScore;
        return (
          <div key={tm.id} className="flex items-center justify-between">
            <span className="flex items-center gap-1.5 text-sm font-bold" style={{ color: dim ? MUTED : TEXT }}>
              <span className="inline-block w-2 h-2 rounded-sm" style={{ background: tm.accent }} />
              {tm.short}
            </span>
            <span className="text-base font-extrabold" style={{ fontVariantNumeric: "tabular-nums", color: dim ? MUTED : TEXT }}>
              {hasScore ? score : "–"}
            </span>
          </div>
        );
      })}
      <p className="text-xs font-semibold mt-1.5" style={{ color: game.status === "live" ? t.accent : FAINT }}>
        {game.status === "live" ? game.inning : isFinal ? "경기 종료" : `${game.time} 시작`}
      </p>
    </article>
  );
}
