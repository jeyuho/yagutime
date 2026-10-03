import { BOARDS, MUTED } from "../../constants/theme";
import { GAMES } from "../../data/games";
import { todayLabel } from "../../lib/utils";
import { SectionTitle } from "../common";
import GameCard from "./GameCard";
import GameMini from "./GameMini";
import BoardPreview from "./BoardPreview";

export default function HomeView({ team, t, records, onAttend, onUndo }) {
  const isMine = (g) => g.away === team.id || g.home === team.id;
  const myGame = GAMES.find(isMine);
  const others = GAMES.filter((g) => !isMine(g));

  return (
    <>
      <SectionTitle sub={`${todayLabel()} 샘플 일정`}>오늘 {team.short} 경기</SectionTitle>
      {myGame ? (
        <GameCard game={myGame} team={team} t={t} record={records.find((r) => r.game_id === myGame.id)} onAttend={onAttend} onUndo={onUndo} />
      ) : (
        <p className="text-sm rounded-2xl px-4 py-8 text-center" style={{ background: t.surface, border: `1px solid ${t.line}`, color: MUTED }}>
          오늘은 {team.short} 경기가 없어요.
        </p>
      )}

      {others.length > 0 && (
        <>
          <SectionTitle>다른 경기</SectionTitle>
          <div className="flex gap-2 overflow-x-auto -mx-4 px-4 pb-1">
            {others.map((g) => <GameMini key={g.id} game={g} t={t} />)}
          </div>
        </>
      )}

      <SectionTitle>게시판</SectionTitle>
      <div className="flex flex-col gap-3">
        {BOARDS.map((b) => <BoardPreview key={b.key} board={b} team={team} t={t} />)}
      </div>
    </>
  );
}
