import { todayISO } from "../lib/utils";

// 2단계(실데이터 연동) 전까지 쓰는 샘플 일정.
// game_id에 날짜를 넣어 날마다 다른 경기로 취급되게 함.
const D = todayISO();

export const GAMES = [
  { id: `${D}-g1`, away: "doosan", home: "nc", stadium: "창원NC파크", time: "17:00", status: "final", score: { away: 4, home: 6 } },
  { id: `${D}-g2`, away: "kia", home: "lg", stadium: "잠실야구장", time: "17:00", status: "live", inning: "7회말", score: { away: 3, home: 2 } },
  { id: `${D}-g3`, away: "hanwha", home: "samsung", stadium: "대구삼성라이온즈파크", time: "17:00", status: "live", inning: "5회초", score: { away: 1, home: 1 } },
  { id: `${D}-g4`, away: "lotte", home: "ssg", stadium: "인천SSG랜더스필드", time: "14:00", status: "final", score: { away: 8, home: 5 } },
  { id: `${D}-g5`, away: "kiwoom", home: "kt", stadium: "수원KT위즈파크", time: "18:00", status: "scheduled" },
];
