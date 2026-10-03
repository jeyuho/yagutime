import { TEXT, MUTED, FAINT, DANGER } from "../constants/theme";
import { RESULT_LABEL } from "../lib/utils";

export function fieldStyle(t, invalid) {
  return {
    background: t.surface,
    border: `1px solid ${invalid ? DANGER : t.line}`,
    color: TEXT,
    borderRadius: 12,
    padding: "11px 12px",
    width: "100%",
    fontSize: 14,
  };
}

export function Segmented({ t, value, onChange, options, disabled }) {
  return (
    <div
      className="grid gap-1 rounded-xl p-1"
      style={{ gridTemplateColumns: `repeat(${options.length}, 1fr)`, background: t.bg, border: `1px solid ${t.line}` }}
    >
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={String(o.value)}
            type="button"
            disabled={disabled}
            onClick={() => onChange(o.value)}
            aria-pressed={active}
            className="flex items-center justify-center gap-1.5 rounded-lg py-2 text-sm font-semibold"
            style={{
              background: active ? t.raised : "transparent",
              color: active ? TEXT : MUTED,
              boxShadow: active ? `inset 0 0 0 1px ${t.accent}` : "none",
            }}
          >
            {o.icon}
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

export function SectionTitle({ children, sub, action }) {
  return (
    <div className="flex items-end justify-between mt-6 mb-3">
      <div>
        <h2 className="text-base font-bold">{children}</h2>
        {sub && <p className="text-xs mt-0.5" style={{ color: MUTED }}>{sub}</p>}
      </div>
      {action}
    </div>
  );
}

export function ResultChip({ result, t }) {
  const style =
    result === "W" ? { background: t.accent, color: t.onAccent }
    : result === "L" ? { background: t.raised, color: MUTED }
    : { color: MUTED, border: `1px solid ${t.line}` };
  return (
    <span className="inline-flex items-center justify-center w-6 h-6 rounded-md text-xs font-bold" style={style}>
      {RESULT_LABEL[result]}
    </span>
  );
}

export function Spinner({ t, size = 18 }) {
  return (
    <span
      role="status"
      aria-label="불러오는 중"
      className="inline-block rounded-full"
      style={{
        width: size, height: size,
        border: `2px solid ${t.line}`, borderTopColor: t.accent,
        animation: "ytSpin 0.8s linear infinite",
      }}
    />
  );
}

export function LoadingBlock({ t }) {
  return (
    <div className="flex justify-center py-12">
      <Spinner t={t} size={22} />
    </div>
  );
}

export function ErrorBlock({ t, message, onRetry }) {
  return (
    <div className="text-center py-10">
      <p className="text-sm" style={{ color: MUTED }}>{message}</p>
      {onRetry && (
        <button onClick={onRetry} className="mt-3 rounded-lg px-4 py-2 text-sm font-semibold" style={{ border: `1px solid ${t.line}` }}>
          다시 시도
        </button>
      )}
    </div>
  );
}

export function EmptyBlock({ children }) {
  return <p className="text-sm text-center py-12" style={{ color: MUTED }}>{children}</p>;
}

export const quietText = { color: FAINT };

// 작은 정렬 토글 (최신순 / 인기순)
export function SortToggle({ t, value, onChange, options }) {
  return (
    <div className="inline-flex gap-0.5 rounded-lg p-0.5" style={{ background: t.bg, border: `1px solid ${t.line}` }}>
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={o.value}
            type="button"
            onClick={() => onChange(o.value)}
            aria-pressed={active}
            className="rounded-md px-2 py-0.5 text-xs font-semibold"
            style={{
              background: active ? t.raised : "transparent",
              color: active ? TEXT : MUTED,
              boxShadow: active ? `inset 0 0 0 1px ${t.accent}` : "none",
            }}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
