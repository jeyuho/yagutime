import { Heart, MessageCircle, Users } from "lucide-react";
import { FAINT } from "../../constants/theme";
import { timeAgo } from "../../lib/utils";

export function PostStats({ post, t }) {
  const likes = Number(post.like_count);
  return (
    <div className="flex items-center gap-3 mt-1.5 text-xs" style={{ color: FAINT }}>
      <span>{timeAgo(post.created_at)}</span>
      <span>{post.author_name}</span>
      <span className="flex items-center gap-1" style={{ color: likes ? t.accent : FAINT }}>
        <Heart size={12} fill={post.liked_by_me ? t.accent : "none"} />{likes}
      </span>
      <span className="flex items-center gap-1"><MessageCircle size={12} />{Number(post.comment_count)}</span>
    </div>
  );
}

export function MetaLine({ meta, board, t }) {
  if (!meta) return null;
  if (board === "party")
    return (
      <p className="flex items-center gap-1.5 text-xs font-semibold mb-1" style={{ color: t.accent }}>
        <Users size={12} />{meta.date} {meta.stadium} / {meta.people}명 모집
      </p>
    );
  if (board === "trade")
    return <p className="text-xs font-semibold mb-1" style={{ color: t.accent }}>[{meta.kind}] {Number(meta.price).toLocaleString("ko-KR")}원</p>;
  return null;
}
