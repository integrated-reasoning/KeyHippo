import { SupabaseClient, createClient } from "@supabase/supabase-js";
import { AppError, AuthResult, Logger } from "./types";

export const authenticate = async (
  headers: Headers,
  supabase: SupabaseClient,
  logger: Logger,
): Promise<AuthResult> => {
  try {
    const authHeader = headers.get("Authorization");
    if (authHeader && authHeader.startsWith("Bearer ")) {
      const apiKey = authHeader.split(" ")[1];
      supabase = createClient(
        (supabase as any).supabaseUrl, // cast away protected
        (supabase as any).supabaseKey,
        {
          global: { headers: { Authorization: apiKey } },
          auth: {
            persistSession: false,
            detectSessionInUrl: false,
            autoRefreshToken: false,
          },
        },
      );

      const { data: userId, error: apiKeyError } = await supabase
        .schema("keyhippo")
        .rpc("get_uid_for_key", { user_api_key: apiKey });

      if (apiKeyError) throw apiKeyError;
      if (!userId) {
        throw new Error(`Invalid API key: ${apiKey}`);
      }

      logger.info(`User authenticated: ${userId}`);
      return { userId, supabase };
    } else {
      const {
        data: { user },
        error,
      } = await supabase.auth.getUser();

      if (error) throw error;
      if (!user) throw new Error("User not authenticated");

      logger.info(`User authenticated: ${user.id}`);
      return { userId: user.id, supabase };
    }
  } catch (error) {
    logger.warn(
      `Authentication failed: ${error instanceof Error ? error.message : String(error)}`,
    );
    throw {
      _tag: "UnauthorizedError",
      message: `Authentication failed: ${error instanceof Error ? error.message : String(error)}`,
    } as AppError;
  }
};
