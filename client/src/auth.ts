import { Effect, pipe } from "effect";
import { SupabaseClient } from "@supabase/supabase-js";
import { AppError, AuthResult, Logger } from "./types";

export const authenticate = (
  headers: Headers,
  supabase: SupabaseClient,
  logger: Logger,
): Effect.Effect<AuthResult, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        const authHeader = headers.get("Authorization");
        if (authHeader && authHeader.startsWith("Bearer ")) {
          const apiKey = authHeader.split(" ")[1];
          const { data: userId, error: apiKeyError } = await supabase
            .schema("keyhippo")
            .rpc("get_uid_for_key", { user_api_key: apiKey });

          if (apiKeyError) throw apiKeyError;
          if (!userId) {
            throw new Error(`Invalid API key: ${apiKey}`);
          }
          return { userId, supabase };
        } else {
          const {
            data: { user },
            error,
          } = await supabase.auth.getUser();
          if (error) throw error;
          if (!user) throw new Error("User not authenticated");
          return { userId: user.id, supabase };
        }
      },
      catch: (error): AppError => ({
        _tag: "UnauthorizedError",
        message: `Authentication failed: ${JSON.stringify(error)}`,
      }),
    }),
    Effect.tap(({ userId }) =>
      Effect.sync(() => logger.info(`User authenticated: ${userId}`)),
    ),
    Effect.tapError((error) =>
      Effect.sync(() => logger.warn(`Authentication failed: ${error.message}`)),
    ),
  );
