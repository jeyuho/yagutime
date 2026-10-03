import { useCallback, useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ChevronLeft, Heart, EyeOff, User, Send } from "lucide-react";
import { boardByKey, TEXT, MUTED, FAINT, DANGER } from "../../constants/theme";
import { api, errorText } from "../../lib/api";
import { timeAgo } from "../../lib/utils";
import { LoadingBlock, ErrorBlock } from "../common";

export default function PostDetail({ profile, team, t }) {
  const { boardKey, postId } = useParams();
  const navigate = useNavigate();
  const board = boardByKey(boardKey);
  const boardLabel = board ? board.label(team) : "게시판";

  const [post, setPost] = useState(undefined); // undefined 로딩, null 없음
  const [comments, setComments] = useState([]);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [busy, setBusy] = useState(false);
  const [text, setText] = useState("");
  const [anon, setAnon] = useState(profile.default_anon);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const load = useCallback(async () => {
    setLoadError("");
    try {
      const p = await api.getPost(postId);
      setPost(p);
      if (p) setComments(await api.listComments(postId));
    } catch (e) {
      setLoadError(errorText(e));
    }
  }, [postId]);

  useEffect(() => { load(); }, [load]);

  async function act(fn) {
    setBusy(true);
    setActionError("");
    try { await fn(); } catch (e) { setActionError(errorText(e)); } finally { setBusy(false); }
  }

  const back = (
    <Link to={`/board/${boardKey}`} className="flex items-center gap-1 text-sm font-semibold py-2" style={{ color: MUTED }}>
      <ChevronLeft size={18} />{boardLabel}
    </Link>
  );

  if (loadError) return <div className="pt-2">{back}<ErrorBlock t={t} message={loadError} onRetry={load} /></div>;
  if (post === undefined) return <div className="pt-2">{back}<LoadingBlock t={t} /></div>;
  if (post === null) return <div className="pt-2">{back}<ErrorBlock t={t} message="글을 찾을 수 없어요. 삭제됐거나 볼 수 없는 글이에요." /></div>;

  // 익명으로 쓴 내 글에 닉네임 댓글을 달면 글쓴이가 드러나므로 익명 고정 (서버도 강제함)
  const forceAnon = post.is_mine && post.is_anon;
  const commentAnon = forceAnon || anon;

  const submitComment = () => {
    if (!text.trim()) return;
    act(async () => {
      await api.createComment(post.id, { body: text.trim(), anon: commentAnon });
      setText("");
      setComments(await api.listComments(post.id));
      setPost(await api.getPost(post.id));
    });
  };

  return (
    <div className="pt-2">
      {back}

      <article className="rounded-2xl p-4 mt-1" style={{ background: t.surface, border: `1px solid ${t.line}` }}>
        <div className="flex items-center justify-between">
          <p className="text-xs" style={{ color: FAINT }}>
            <span className="font-semibold" style={{ color: MUTED }}>{post.author_name}</span> {timeAgo(post.created_at)}
          </p>
          {post.is_mine && (confirmDelete ? (
            <span className="flex items-center gap-2 text-xs font-semibold">
              <button disabled={busy} style={{ color: DANGER }}
                onClick={() => act(async () => { await api.deletePost(post.id); navigate(`/board/${boardKey}`, { replace: true }); })}>
                삭제하기
              </button>
              <button onClick={() => setConfirmDelete(false)} style={{ color: MUTED }}>취소</button>
            </span>
          ) : (
            <button onClick={() => setConfirmDelete(true)} className="text-xs font-semibold" style={{ color: FAINT }}>삭제</button>
          ))}
        </div>
        <h2 className="text-lg font-bold mt-1">{post.title}</h2>

        {post.meta && boardKey === "party" && (
          <dl className="grid grid-cols-3 gap-2 mt-3 text-xs">
            {[["경기", post.meta.date], ["구장", post.meta.stadium], ["모집", `${post.meta.people}명`]].map(([k, v]) => (
              <div key={k} className="rounded-lg px-2.5 py-2" style={{ background: t.bg }}>
                <dt style={{ color: FAINT }}>{k}</dt>
                <dd className="font-semibold mt-0.5">{v}</dd>
              </div>
            ))}
          </dl>
        )}

        <p className="text-sm mt-3 whitespace-pre-wrap" style={{ lineHeight: 1.7 }}>{post.body}</p>

        <button
          onClick={() => act(async () => { await api.toggleLike(post.id); setPost(await api.getPost(post.id)); })}
          disabled={busy}
          aria-pressed={post.liked_by_me}
          className="flex items-center gap-1.5 mt-4 rounded-lg px-3 py-1.5 text-sm font-semibold"
          style={{ border: `1px solid ${post.liked_by_me ? t.accent : t.line}`, color: post.liked_by_me ? t.accent : MUTED }}
        >
          <Heart size={14} fill={post.liked_by_me ? t.accent : "none"} />공감 {Number(post.like_count)}
        </button>
      </article>

      {actionError && <p className="text-sm mt-3" style={{ color: DANGER }} role="alert">{actionError}</p>}

      <h3 className="text-sm font-bold mt-5 mb-2">댓글 {comments.length}</h3>
      <div className="flex flex-col gap-2">
        {comments.length === 0 && <p className="text-sm py-4" style={{ color: MUTED }}>첫 댓글을 남겨 보세요.</p>}
        {comments.map((c) => (
          <div key={c.id} className="rounded-xl px-3.5 py-2.5" style={{ background: t.surface }}>
            <p className="text-xs font-semibold" style={{ color: c.is_writer ? t.accent : MUTED }}>
              {c.author_name} <span style={{ color: FAINT, fontWeight: 400 }}>{timeAgo(c.created_at)}</span>
            </p>
            <p className="text-sm mt-0.5 whitespace-pre-wrap">{c.body}</p>
          </div>
        ))}
      </div>

      <div className="flex gap-2 mt-3">
        <button
          onClick={() => !forceAnon && setAnon((a) => !a)}
          disabled={forceAnon}
          aria-pressed={commentAnon}
          className="shrink-0 flex items-center gap-1 rounded-xl px-3 text-xs font-semibold"
          style={{ background: commentAnon ? t.raised : t.surface, border: `1px solid ${commentAnon ? t.accent : t.line}`, color: commentAnon ? TEXT : MUTED }}
          title={forceAnon ? "익명 글의 글쓴이는 익명으로만 댓글을 달 수 있어요" : "익명 전환"}
        >
          {commentAnon ? <EyeOff size={13} /> : <User size={13} />}
          {commentAnon ? "익명" : profile.nickname}
        </button>
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && !e.nativeEvent.isComposing && submitComment()}
          maxLength={1000}
          placeholder="댓글을 입력하세요"
          className="flex-1 min-w-0 rounded-xl px-3.5 py-2.5 text-sm"
          style={{ background: t.surface, border: `1px solid ${t.line}`, color: TEXT }}
          aria-label="댓글 입력"
        />
        <button onClick={submitComment} disabled={busy} className="rounded-xl px-3.5" style={{ background: t.accent, color: t.onAccent }} aria-label="댓글 등록">
          <Send size={16} />
        </button>
      </div>
    </div>
  );
}
