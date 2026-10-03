import { useState } from "react";

// 게시판별로 고른 정렬을 이 기기에 기억. 홈 미리보기와 글 목록이 같은 값을 씀
const storageKey = (boardKey) => `yagutime.sort.${boardKey}`;

function readSort(boardKey) {
  try {
    return localStorage.getItem(storageKey(boardKey)) === "hot" ? "hot" : "new";
  } catch {
    return "new";
  }
}

export function useBoardSort(boardKey) {
  const [chosen, setChosen] = useState({});
  const sort = chosen[boardKey] ?? readSort(boardKey);

  const setSort = (value) => {
    try { localStorage.setItem(storageKey(boardKey), value); } catch { /* 저장 못 해도 이번 화면에서는 적용 */ }
    setChosen((c) => ({ ...c, [boardKey]: value }));
  };

  return [sort, setSort];
}
