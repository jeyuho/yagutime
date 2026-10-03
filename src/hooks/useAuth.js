import { useCallback, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { api } from "../lib/api";

// session: undefined = 확인 중, null = 로그아웃, object = 로그인
export function useAuth() {
  const [session, setSession] = useState(undefined);
  const [profile, setProfile] = useState(null);
  const [profileState, setProfileState] = useState("idle"); // idle | loading | ready | error

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    // 콜백 안에서는 상태만 바꾸고 Supabase 호출은 하지 않음 (교착 방지)
    const { data } = supabase.auth.onAuthStateChange((_event, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);

  const uid = session?.user?.id ?? null;

  const refreshProfile = useCallback(async () => {
    if (!uid) {
      setProfile(null);
      setProfileState("idle");
      return;
    }
    setProfileState((s) => (s === "ready" ? s : "loading"));
    try {
      const p = await api.getProfile(uid);
      setProfile(p);
      setProfileState(p ? "ready" : "error");
    } catch {
      setProfileState("error");
    }
  }, [uid]);

  useEffect(() => {
    refreshProfile();
  }, [refreshProfile]);

  const loading = session === undefined || (!!uid && (profileState === "idle" || profileState === "loading"));

  return { loading, session, profile, setProfile, profileError: profileState === "error", refreshProfile };
}
