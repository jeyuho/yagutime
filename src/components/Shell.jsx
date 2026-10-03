import { useCallback, useEffect, useState } from "react";
import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import { teamById, DANGER } from "../constants/theme";
import { api, errorText } from "../lib/api";
import { teamStatus } from "../lib/utils";
import Header from "./Header";
import BottomNav from "./BottomNav";
import HomeView from "./home/HomeView";
import BoardHub from "./board/BoardHub";
import BoardView from "./board/BoardView";
import PostDetail from "./board/PostDetail";
import WriteForm from "./board/WriteForm";
import MyView from "./MyView";

export default function Shell({ profile, setProfile, t, onOpenTeam }) {
  const team = teamById(profile.team_id);
  const { locked } = teamStatus(profile);
  const { pathname } = useLocation();
  const [records, setRecords] = useState([]);
  const [toast, setToast] = useState("");

  const showError = (e) => {
    setToast(errorText(e));
    setTimeout(() => setToast(""), 3000);
  };

  const loadRecords = useCallback(async () => {
    try {
      setRecords(await api.listAttendance(profile.team_id));
    } catch (e) {
      showError(e);
    }
  }, [profile.team_id]);

  useEffect(() => { loadRecords(); }, [loadRecords]);

  async function attend(game, result) {
    const isHome = game.home === team.id;
    const score = game.status === "final"
      ? `${isHome ? game.score.home : game.score.away}:${isHome ? game.score.away : game.score.home}`
      : null;
    try {
      await api.addAttendance({
        team_id: team.id,
        game_id: game.id,
        opponent: isHome ? game.away : game.home,
        stadium: game.stadium,
        result,
        score,
      });
    } catch (e) {
      showError(e);
    }
    await loadRecords();
  }

  async function undo(gameId) {
    try { await api.undoAttendance(team.id, gameId); } catch (e) { showError(e); }
    await loadRecords();
  }

  async function remove(id) {
    try { await api.removeAttendance(id); } catch (e) { showError(e); }
    await loadRecords();
  }

  const hideNav = pathname.endsWith("/write");

  return (
    <>
      <Header team={team} t={t} locked={locked} onTeamClick={onOpenTeam} />
      {toast && (
        <p className="mx-4 mt-3 rounded-xl px-3 py-2 text-sm" role="alert" style={{ background: t.surface, border: `1px solid ${DANGER}`, color: DANGER }}>
          {toast}
        </p>
      )}
      <main className="px-4">
        <Routes>
          <Route path="/" element={<HomeView team={team} t={t} records={records} onAttend={attend} onUndo={undo} />} />
          <Route path="/board" element={<BoardHub team={team} t={t} />} />
          <Route path="/board/:boardKey" element={<BoardView team={team} t={t} />} />
          <Route path="/board/:boardKey/write" element={<WriteForm profile={profile} team={team} t={t} />} />
          <Route path="/board/:boardKey/:postId" element={<PostDetail key={pathname} profile={profile} team={team} t={t} />} />
          <Route
            path="/my"
            element={<MyView profile={profile} setProfile={setProfile} team={team} t={t} records={records} onRemoveRecord={remove} onChangeTeam={onOpenTeam} />}
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
      {!hideNav && <BottomNav t={t} pathname={pathname} />}
    </>
  );
}
