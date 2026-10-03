import { Link } from "react-router-dom";
import { ChevronRight } from "lucide-react";
import { BOARDS, MUTED, FAINT } from "../../constants/theme";

// 게시판 탭 시작 화면: 게시판 4개 목록
export default function BoardHub({ team, t }) {
  return (
    <>
      <h1 className="text-lg font-bold mt-5 mb-3">게시판</h1>
      <ul className="rounded-2xl overflow-hidden" style={{ background: t.surface, border: `1px solid ${t.line}` }}>
        {BOARDS.map((b, i) => (
          <li key={b.key} style={{ borderTop: i ? `1px solid ${t.line}` : "none" }}>
            <Link to={`/board/${b.key}`} className="flex items-center justify-between gap-3 px-4 py-4">
              <div className="min-w-0">
                <p className="text-sm font-bold">{b.label(team)}</p>
                <p className="text-xs mt-0.5 truncate" style={{ color: MUTED }}>{b.desc(team)}</p>
              </div>
              <ChevronRight size={18} style={{ color: FAINT }} className="shrink-0" />
            </Link>
          </li>
        ))}
      </ul>
    </>
  );
}
