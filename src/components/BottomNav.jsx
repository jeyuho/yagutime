import { NavLink } from "react-router-dom";
import { Home, List, User } from "lucide-react";
import { FAINT } from "../constants/theme";

const ITEMS = [
  { to: "/", label: "홈", Icon: Home, end: true },
  { to: "/board", label: "게시판", Icon: List },
  { to: "/my", label: "MY", Icon: User },
];

export default function BottomNav({ t, pathname }) {
  return (
    <nav className="fixed bottom-0 left-0 right-0 z-20" style={{ background: t.bg, borderTop: `1px solid ${t.line}` }}>
      <div className="max-w-md mx-auto grid grid-cols-3">
        {ITEMS.map(({ to, match, label, Icon, end }) => {
          const active = end ? pathname === to : pathname.startsWith(match ?? to);
          return (
            <NavLink
              key={to}
              to={to}
              end={end}
              className="flex flex-col items-center gap-1 py-2.5 text-xs font-semibold"
              style={{ color: active ? t.accent : FAINT }}
              aria-current={active ? "page" : undefined}
            >
              <Icon size={20} strokeWidth={active ? 2.4 : 1.8} />
              {label}
            </NavLink>
          );
        })}
      </div>
    </nav>
  );
}
