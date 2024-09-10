import { KeyHippo } from "../src/index";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

export interface TestSetup {
  keyHippo: KeyHippo;
  userId: string;
  supabase: SupabaseClient;
}

export async function setupTest(): Promise<TestSetup> {
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
  );
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error) throw new Error("Error signing in anonymously");

  const keyHippo = new KeyHippo(supabase, console);
  const userId = data.user!.id;

  return { keyHippo, userId, supabase };
}
