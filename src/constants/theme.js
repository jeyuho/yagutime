export const TEXT = "#EEE8DC";
export const MUTED = "rgba(238,232,220,0.62)";
export const FAINT = "rgba(238,232,220,0.38)";
export const DANGER = "#E8706B";

export const NEUTRAL = {
  id: null, name: "", short: "", home: "",
  bg: "#111418", surface: "#1A1E24", raised: "#232830", line: "#2C323B",
  accent: "#C9CED6", onAccent: "#111418",
};

export const TEAMS = [
  { id: "nc", name: "NC 다이노스", short: "NC", home: "창원NC파크",
    bg: "#0E1A2E", surface: "#1B2F50", raised: "#243A60", line: "#2F4772", accent: "#C6A266", onAccent: "#13223B" },
  { id: "kia", name: "KIA 타이거즈", short: "KIA", home: "광주-기아 챔피언스 필드",
    bg: "#161011", surface: "#241A1C", raised: "#302326", line: "#3E2D31", accent: "#F0384A", onAccent: "#FFFFFF" },
  { id: "samsung", name: "삼성 라이온즈", short: "삼성", home: "대구삼성라이온즈파크",
    bg: "#0D1422", surface: "#172238", raised: "#1F2D47", line: "#2A3A58", accent: "#4C8DF0", onAccent: "#FFFFFF" },
  { id: "lg", name: "LG 트윈스", short: "LG", home: "잠실야구장",
    bg: "#150F13", surface: "#241A20", raised: "#2F2229", line: "#3C2C35", accent: "#E5376F", onAccent: "#FFFFFF" },
  { id: "doosan", name: "두산 베어스", short: "두산", home: "잠실야구장",
    bg: "#0F0F1C", surface: "#1C1C33", raised: "#252541", line: "#31314F", accent: "#ED4A52", onAccent: "#FFFFFF" },
  { id: "kt", name: "KT 위즈", short: "KT", home: "수원KT위즈파크",
    bg: "#121212", surface: "#1E1E1E", raised: "#282828", line: "#343434", accent: "#EB2F36", onAccent: "#FFFFFF" },
  { id: "ssg", name: "SSG 랜더스", short: "SSG", home: "인천SSG랜더스필드",
    bg: "#151012", surface: "#24191C", raised: "#2F2125", line: "#3D2B30", accent: "#EAB308", onAccent: "#1A1408" },
  { id: "lotte", name: "롯데 자이언츠", short: "롯데", home: "사직야구장",
    bg: "#0B1426", surface: "#15233D", raised: "#1D2D4B", line: "#283B5E", accent: "#6CB4EE", onAccent: "#0B1426" },
  { id: "hanwha", name: "한화 이글스", short: "한화", home: "대전 한화생명 볼파크",
    bg: "#17120E", surface: "#271E17", raised: "#33271E", line: "#413227", accent: "#FF6A13", onAccent: "#1A1208" },
  { id: "kiwoom", name: "키움 히어로즈", short: "키움", home: "고척스카이돔",
    bg: "#170D10", surface: "#29171C", raised: "#341E24", line: "#43282F", accent: "#D45A73", onAccent: "#FFFFFF" },
];

export const teamById = (id) => TEAMS.find((t) => t.id === id) ?? NEUTRAL;
export const STADIUMS = [...new Set(TEAMS.map((t) => t.home))];

export const BOARDS = [
  { key: "team", label: (team) => `${team.short} 자유게시판`, desc: (team) => `${team.name} 팬끼리 나누는 이야기` },
  { key: "all", label: () => "전체 게시판", desc: () => "모든 구단 팬이 함께 쓰는 게시판" },
  { key: "party", label: () => "직관 게시판", desc: () => "직관, 원정 같이 갈 사람 모집" },
  { key: "trade", label: () => "거래 게시판", desc: () => "굿즈와 티켓 거래. 정가보다 비싼 티켓 거래 글은 삭제돼요." },
];
export const boardByKey = (key) => BOARDS.find((b) => b.key === key);
