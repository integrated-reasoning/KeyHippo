import { SupabaseClient, createClient } from "@supabase/supabase-js";
import { AppError, AuthResult, Logger } from "./types";
import {
  createUnauthorizedError,
  createAuthenticationError,
} from "./errorUtils";

export const authenticate = async (
  headers: Headers,
  supabase: SupabaseClient,
  logger: Logger,
): Promise<AuthResult> => {
  try {
    const authHeader = headers.get("Authorization");
    if (authHeader && authHeader.startsWith("Bearer ")) {
      const apiKey = authHeader.split(" ")[1];
      // Reinitialize Supabase client with the API key
      const authenticatedSupabase = createClient(
        (supabase as any).supabaseUrl, // Cast away protected
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

      // Call the RPC function to get the user ID
      const { data: userId, error: apiKeyError } = await authenticatedSupabase
        .schema("keyhippo")
        .rpc("get_uid_for_key", { user_api_key: apiKey });

      if (apiKeyError) {
        throw createUnauthorizedError("Invalid API key.");
      }

      if (!userId) {
        throw createUnauthorizedError(
          "API key does not correspond to any user.",
        );
      }

      logger.info(`User authenticated: ${userId}`);
      return { userId, supabase: authenticatedSupabase };
    } else {
      const {
        data: { user },
        error,
      } = await supabase.auth.getUser();

      if (error) {
        throw createAuthenticationError(
          "Failed to retrieve authenticated user.",
        );
      }

      if (!user) {
        throw createUnauthorizedError("User not authenticated.");
      }

      logger.info(`User authenticated: ${user.id}`);
      return { userId: user.id, supabase };
    }
  } catch (error) {
    // Type assertion with runtime check
    if (
      error &&
      typeof error === "object" &&
      "_tag" in error &&
      typeof (error as AppError)._tag === "string" &&
      "message" in error &&
      typeof (error as AppError).message === "string"
    ) {
      // If the error is already an AppError, rethrow it
      throw error;
    } else if (error instanceof Error) {
      // Handle standard Error objects
      logger.error(`Authentication failed: ${error.message}`);
      throw createAuthenticationError(
        "Authentication failed due to an unexpected error.",
      );
    } else {
      // Handle non-Error, non-AppError objects
      logger.error(`Authentication failed: ${String(error)}`);
      throw createAuthenticationError(
        "Authentication failed due to an unknown error.",
      );
    }
  }
};
