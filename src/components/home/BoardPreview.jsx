import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { ChevronRight, Heart } from "lucide-react";
import { MUTED, FAINT } from "../../constants/theme";
import { api } from "../../lib/api";
import { SORTS, sortPosts } from "../../lib/utils";
import { useBoardSort } from "../../hooks/useBoardSort";
import { SortToggle } from "../common";

// 미리보기는 최근 글 몇 개만 받아서, 그 안에서 정렬해 위 3개를 보여 줌
const FETCH_LIMIT = 20;
const SHOW = 3;

export default function BoardPreview({ board, team, t }) {
  const [posts, setPosts] = useState(null);
  const [failed, setFailed] = useState(false);
  const [sort, setSort] = useBoardSort(board.key);

  useEffect(() => {
    let alive = true;
    setPosts(null);
    setFailed(false);
    api.listPosts(board.key, FETCH_LIMIT)
      .then((rows) => alive && setPosts(rows))
      .catch(() => alive && setFailed(true));
    return () => { alive = false; };
  }, [board.key, team.id]);

  const top = posts ? sortPosts(posts, sort).slice(0, SHOW) : [];

  return (
    <section className="rounded-2xl overflow-hidden" style={{ background: t.surface, border: `1px solid ${t.line}` }}>
      <div className="flex items-center justify-between gap-2 px-4 pt-3 pb-2">
        <Link to={`/board/${board.key}`} className="flex items-center gap-0.5 text-sm font-bold min-w-0">
          <span className="truncate">{board.label(team)}</span>
          <ChevronRight size={16} style={{ color: FAINT }} className="shrink-0" />
        </Link>
        <SortToggle t={t} value={sort} onChange={setSort} options={SORTS} />
      </div>

      {failed ? (
        <p className="text-xs px-4 pb-3" style={{ color: MUTED }}>글을 불러오지 못했어요.</p>
      ) : posts === null ? (
        <p className="text-xs px-4 pb-3" style={{ color: FAINT }}>불러오는 중</p>
      ) : top.length === 0 ? (
        <p className="text-xs px-4 pb-3" style={{ color: FAINT }}>아직 글이 없어요.</p>
      ) : (
        <ul>
          {top.map((p) => (
            <li key={p.id} style={{ borderTop: `1px solid ${t.line}` }}>
              <Link to={`/board/${board.key}/${p.id}`} className="flex items-center justify-between gap-3 px-4 py-2.5">
                <span className="text-sm truncate">{p.title}</span>
                {Number(p.like_count) > 0 && (
                  <span className="flex items-center gap-1 text-xs shrink-0" style={{ color: t.accent }}>
                    <Heart size={12} />{Number(p.like_count)}
                  </span>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
