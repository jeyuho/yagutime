import { useState } from "react";
import { BrowserRouter } from "react-router-dom";
import { configError } from "./lib/supabase";
import { api } from "./lib/api";
import { useAuth } from "./hooks/useAuth";
import { teamById, NEUTRAL, TEXT, MUTED, FAINT } from "./constants/theme";
import AuthScreen from "./components/AuthScreen";
import TeamModal from "./components/TeamModal";
import Shell from "./components/Shell";
import { Spinner } from "./components/common";

export default function App() {
  if (configError) return <ConfigError />;
  return (
    <BrowserRouter>
      <Root />
    </BrowserRouter>
  );
}

function Root() {
  const { loading, session, profile, setProfile, profileError, refreshProfile } = useAuth();
  const [teamModal, setTeamModal] = useState(false);
  const [previewId, setPreviewId] = useState(null);

  const showModal = !!profile && (!profile.team_id || teamModal);
  // 팀을 고르는 동안에는 고른 팀 테마를 앱 전체에 미리 적용
  const t = showModal ? teamById(previewId ?? profile.team_id) : profile ? teamById(profile.team_id) : NEUTRAL;

  const closeModal = () => {
    setPreviewId(null);
    setTeamModal(false);
  };

  return (
    <div className="min-h-screen w-full" style={{ background: t.bg, color: TEXT, transition: "background 300ms ease" }}>
      <style>{`
        a:focus-visible, button:focus-visible, input:focus-visible, textarea:focus-visible, select:focus-visible {
          outline: 2px solid ${t.accent}; outline-offset: 2px;
        }
        input::placeholder, textarea::placeholder { color: ${FAINT}; }
        button:disabled { cursor: not-allowed; }
      `}</style>

      <div className="max-w-md mx-auto min-h-screen relative pb-24">
        {loading ? (
          <div className="flex justify-center pt-40"><Spinner t={t} size={26} /></div>
        ) : !session ? (
          <AuthScreen t={t} />
        ) : profileError ? (
          <div className="px-5 pt-32 text-center">
            <p className="text-sm" style={{ color: MUTED }}>프로필을 불러오지 못했어요.</p>
            <div className="flex justify-center gap-2 mt-4">
              <button onClick={refreshProfile} className="rounded-lg px-4 py-2 text-sm font-semibold" style={{ border: `1px solid ${t.line}` }}>다시 시도</button>
              <button onClick={() => api.signOut()} className="rounded-lg px-4 py-2 text-sm font-semibold" style={{ color: MUTED }}>로그아웃</button>
            </div>
          </div>
        ) : profile?.team_id ? (
          <Shell profile={profile} setProfile={setProfile} t={t} onOpenTeam={() => setTeamModal(true)} />
        ) : null}
      </div>

      {showModal && (
        <TeamModal
          key={profile.team_id ?? "new"}
          t={t}
          profile={profile}
          selectedId={previewId ?? profile.team_id}
          onSelect={setPreviewId}
          onDone={(updated) => {
            setProfile(updated);
            closeModal();
          }}
          onClose={profile.team_id ? closeModal : null}
          onLogout={!profile.team_id ? () => api.signOut() : null}
        />
      )}
    </div>
  );
}

function ConfigError() {
  return (
    <div className="min-h-screen flex items-center justify-center p-6" style={{ background: NEUTRAL.bg, color: TEXT }}>
      <div className="max-w-sm text-center">
        <p className="text-lg font-bold">Supabase 연결 정보가 없어요</p>
        <p className="text-sm mt-2" style={{ color: MUTED, lineHeight: 1.6 }}>{configError}</p>
      </div>
    </div>
  );
}
