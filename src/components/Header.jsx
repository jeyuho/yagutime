import { Link } from "react-router-dom";
import { ChevronDown, Lock } from "lucide-react";
import { MUTED } from "../constants/theme";

export default function Header({ team, t, locked, onTeamClick }) {
  return (
    <header
      className="sticky top-0 z-20 flex items-center justify-between px-4 py-3"
      style={{ background: t.bg, borderBottom: `1px solid ${t.line}` }}
    >
      <Link to="/" className="text-lg font-extrabold" style={{ letterSpacing: "-0.02em" }}>
        덕아웃
      </Link>
      <button
        onClick={onTeamClick}
        className="flex items-center gap-2 text-sm font-semibold rounded-full px-3 py-1.5"
        style={{ background: t.surface, border: `1px solid ${t.line}` }}
        aria-label="응원팀 보기"
      >
        <span className="inline-block w-2.5 h-2.5 rounded-full" style={{ background: t.accent }} />
        {team.name}
        {locked ? <Lock size={12} style={{ color: MUTED }} /> : <ChevronDown size={14} style={{ color: MUTED }} />}
      </button>
    </header>
  );
}
