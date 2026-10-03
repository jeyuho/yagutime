import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const configError =
  !url || !key ? ".env.local 파일에 VITE_SUPABASE_URL과 VITE_SUPABASE_ANON_KEY를 넣고 개발 서버를 다시 켜 주세요." : null;

export const supabase = configError ? null : createClient(url, key);
