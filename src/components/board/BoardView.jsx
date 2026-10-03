import { useCallback, useEffect, useState } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import { ChevronLeft, Pencil } from "lucide-react";
import { boardByKey, MUTED, FAINT } from "../../constants/theme";
import { api, errorText } from "../../lib/api";
import { SORTS, sortPosts } from "../../lib/utils";
import { useBoardSort } from "../../hooks/useBoardSort";
import { LoadingBlock, ErrorBlock, EmptyBlock, SortToggle } from "../common";
import { PostStats, MetaLine } from "./PostStats";

// list_posts 최대치. 인기순은 이 범위 안에서 정렬됨
const LIST_LIMIT = 100;

export default function BoardView({ team, t }) {
  const { boardKey } = useParams();
  const board = boardByKey(boardKey);
  const [posts, setPosts] = useState(null);
  const [error, setError] = useState("");
  const [sort, setSort] = useBoardSort(boardKey);

  const load = useCallback(async () => {
    if (!board) return;
    setPosts(null);
    setError("");
    try {
      setPosts(await api.listPosts(boardKey, LIST_LIMIT));
    } catch (e) {
      setError(errorText(e));
    }
  }, [boardKey, board, team.id]);

  useEffect(() => { load(); }, [load]);

  if (!board) return <Navigate to="/board" replace />;

  return (
    <>
      <Link to="/board" className="flex items-center gap-1 text-sm font-semibold pt-3 pb-1" style={{ color: MUTED }}>
        <ChevronLeft size={18} />게시판
      </Link>
      <h1 className="text-lg font-bold">{board.label(team)}</h1>
      <p className="text-xs mt-0.5" style={{ color: MUTED }}>{board.desc(team)}</p>

      <div className="flex items-center justify-between mt-3 mb-3">
        <SortToggle t={t} value={sort} onChange={setSort} options={SORTS} />
        {sort === "hot" && <span className="text-xs" style={{ color: FAINT }}>최근 {LIST_LIMIT}개 글 기준</span>}
      </div>

      {error ? (
        <ErrorBlock t={t} message={error} onRetry={load} />
      ) : posts === null ? (
        <LoadingBlock t={t} />
      ) : posts.length === 0 ? (
        <EmptyBlock>아직 글이 없어요. 첫 글을 남겨 보세요.</EmptyBlock>
      ) : (
        <div className="rounded-2xl overflow-hidden" style={{ background: t.surface, border: `1px solid ${t.line}` }}>
          {sortPosts(posts, sort).map((p, i) => (
            <Link key={p.id} to={`/board/${boardKey}/${p.id}`} className="block px-4 py-3.5" style={{ borderTop: i ? `1px solid ${t.line}` : "none" }}>
              <MetaLine meta={p.meta} board={boardKey} t={t} />
              <p className="text-sm font-bold truncate">
                {p.title}
                {p.is_mine && <span className="ml-1.5 text-xs font-semibold" style={{ color: t.accent }}>내 글</span>}
              </p>
              <p className="text-sm mt-0.5 truncate" style={{ color: MUTED }}>{p.body}</p>
              <PostStats post={p} t={t} />
            </Link>
          ))}
        </div>
      )}

      <Link
        to={`/board/${boardKey}/write`}
        className="fixed z-30 flex items-center gap-1.5 rounded-full px-4 py-3 text-sm font-bold shadow-lg"
        style={{ background: t.accent, color: t.onAccent, bottom: 84, right: "max(16px, calc(50vw - 224px + 16px))" }}
      >
        <Pencil size={16} />글쓰기
      </Link>
    </>
  );
}
