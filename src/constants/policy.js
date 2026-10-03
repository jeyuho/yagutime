// 화면 표시용 값. 실제 판정은 서버(supabase/schema.sql 의 policy_team_lock, policy_team_grace)가 합니다.
// 서버 값을 바꾸면 여기도 같이 바꿔 주세요.
export const TEAM_LOCK_MONTHS = 3;
export const GRACE_HOURS = 24;
