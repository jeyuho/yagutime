import { useState } from "react";
import { Navigate, useNavigate, useParams } from "react-router-dom";
import { User, EyeOff } from "lucide-react";
import { boardByKey, STADIUMS, TEXT, MUTED, DANGER } from "../../constants/theme";
import { api, errorText } from "../../lib/api";
import { Segmented, fieldStyle } from "../common";

export default function WriteForm({ profile, team, t }) {
  const { boardKey } = useParams();
  const navigate = useNavigate();
  const board = boardByKey(boardKey);

  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [anon, setAnon] = useState(profile.default_anon);
  const [date, setDate] = useState("");
  const [stadium, setStadium] = useState(team.home);
  const [people, setPeople] = useState(2);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  if (!board) return <Navigate to="/board" replace />;
  const field = fieldStyle(t);

  async function submit() {
    if (!title.trim()) return setError("제목을 입력해 주세요.");
    if (!body.trim()) return setError("내용을 입력해 주세요.");
    if (boardKey === "party" && !date.trim()) return setError("경기 날짜와 시간을 입력해 주세요.");
    if (boardKey === "party" && !(Number(people) >= 1 && Number(people) <= 20)) return setError("모집 인원은 1~20명이에요.");

    let meta = null;
    if (boardKey === "party") meta = { date: date.trim(), stadium, people: Number(people) };

    setBusy(true);
    setError("");
    try {
      const id = await api.createPost(boardKey, { title: title.trim(), body: body.trim(), anon, meta });
      navigate(`/board/${boardKey}/${id}`, { replace: true });
    } catch (e) {
      setError(errorText(e));
      setBusy(false);
    }
  }

  return (
    <div className="pt-2">
      <div className="flex items-center justify-between py-2">
        <button onClick={() => navigate(-1)} className="text-sm font-semibold" style={{ color: MUTED }}>취소</button>
        <p className="text-sm font-bold">{board.label(team)} 글쓰기</p>
        <button onClick={submit} disabled={busy} className="rounded-full px-4 py-1.5 text-sm font-bold"
          style={{ background: t.accent, color: t.onAccent, opacity: busy ? 0.6 : 1 }}>
          {busy ? "등록 중" : "등록"}
        </button>
      </div>

      <div className="flex flex-col gap-3 mt-2">
        <Segmented t={t} value={anon} onChange={setAnon}
          options={[{ value: false, label: profile.nickname, icon: <User size={14} /> }, { value: true, label: "익명", icon: <EyeOff size={14} /> }]} />


        <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={100} placeholder="제목" style={field} aria-label="제목" />

        {boardKey === "party" && (
          <>
            <input value={date} onChange={(e) => setDate(e.target.value)} maxLength={30}
              placeholder="경기 날짜와 시간 (예: 10/10 18:30)" style={field} aria-label="경기 날짜와 시간" />
            <div className="grid gap-2" style={{ gridTemplateColumns: "1fr 110px" }}>
              <select value={stadium} onChange={(e) => setStadium(e.target.value)} style={field} aria-label="구장">
                {STADIUMS.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
              <label className="flex items-center gap-1.5" style={{ ...field, padding: "0 12px" }}>
                <input type="number" min={1} max={20} value={people} onChange={(e) => setPeople(e.target.value)}
                  className="w-full bg-transparent" style={{ color: TEXT, outline: "none" }} aria-label="모집 인원" />
                <span className="text-sm shrink-0" style={{ color: MUTED }}>명</span>
              </label>
            </div>
          </>
        )}

        <textarea
          value={body}
          onChange={(e) => setBody(e.target.value)}
          rows={8}
          maxLength={5000}
          placeholder={boardKey === "party" ? "좌석, 만나는 장소, 응원 스타일을 적어 주세요."
            : "야구 이야기를 자유롭게 나눠 보세요."}
          style={{ ...field, resize: "vertical", lineHeight: 1.6 }}
          aria-label="내용"
        />

        {error && <p className="text-sm font-semibold" style={{ color: DANGER }} role="alert">{error}</p>}
      </div>
    </div>
  );
}
