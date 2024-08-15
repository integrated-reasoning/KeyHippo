import { Effect, pipe } from "effect";
import { SupabaseClient, createClient } from "@supabase/supabase-js";
import { AppError, AuthResult } from "./types";

export const authenticate = (
  request: Request,
): Effect.Effect<AuthResult, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        const authHeader = request.headers.get("Authorization");
        if (authHeader && authHeader.startsWith("Bearer ")) {
          const apiKey = authHeader.split(" ")[1];
          const supabase = createClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
            {
              global: {
                headers: {
                  Authorization: apiKey,
                },
              },
              auth: {
                persistSession: false,
                detectSessionInUrl: false,
                autoRefreshToken: false,
              },
            },
          );
          const { data: userId, error: apiKeyError } = await supabase.rpc(
            "get_uid_for_key",
            { user_api_key: apiKey },
          );

          if (apiKeyError) throw apiKeyError;
          if (!userId) {
            throw new Error(`Invalid API key: ${apiKey}`);
          }
          return { userId, supabase };
        } else {
          const supabase = createClient(
            process.env.SUPABASE_URL!,
            process.env.SUPABASE_ANON_KEY!,
            {
              auth: {
                persistSession: false,
                detectSessionInUrl: false,
                autoRefreshToken: false,
              },
            },
          );
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
    Effect.tap(({ userId }) => Effect.logInfo(`User authenticated: ${userId}`)),
    Effect.tapError((error) =>
      Effect.logWarning(`Authentication failed: ${error.message}`),
    ),
  );

export const sessionEffect = (
  request: Request,
  operation: (
    supabase: SupabaseClient<any, "public", any>,
    userId: string,
    ...args: any[]
  ) => Effect.Effect<any, AppError>,
  ...additionalArgs: any[]
): Effect.Effect<any, AppError> =>
  pipe(
    Effect.succeed(request),
    Effect.tap(() => Effect.logInfo(`${request.method} /api/session - Start`)),
    Effect.flatMap((req) => authenticate(req)),
    Effect.flatMap(({ userId, supabase }) =>
      operation(supabase, userId, ...additionalArgs),
    ),
    Effect.tap((result: any) =>
      Effect.logInfo(`${request.method} /api/session - Success`),
    ),
    Effect.tapError((error: AppError) =>
      Effect.logError(
        `${request.method} /api/session - Failed: ${error.message}`,
      ),
    ),
  );
