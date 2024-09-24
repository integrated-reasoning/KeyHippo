import { SupabaseClient, createClient } from "@supabase/supabase-js";
import { AppError, AuthResult, Logger } from "./types";
import { createUnauthorizedError, createAuthenticationError } from "./utils";

/**
 * Extracts the API key from the Authorization header.
 * @param headers - The request headers.
 * @returns The API key if present, otherwise null.
 */
const extractApiKey = (headers: Headers): string | null => {
  const authHeader = headers.get("Authorization");
  if (authHeader && authHeader.startsWith("Bearer ")) {
    return authHeader.split(" ")[1];
  }
  return null;
};

/**
 * Reinitializes the Supabase client with the provided API key.
 * @param supabase - The original Supabase client.
 * @param apiKey - The API key for authentication.
 * @returns A new Supabase client instance with the API key.
 */
const createAuthenticatedSupabaseClient = (
  supabase: SupabaseClient,
  apiKey: string,
): SupabaseClient => {
  return createClient(
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
};

/**
 * Retrieves the user ID associated with the provided API key.
 * @param authenticatedSupabase - The authenticated Supabase client.
 * @param apiKey - The API key.
 * @returns The user ID.
 * @throws UnauthorizedError if the API key is invalid or does not correspond to any user.
 */
const getUserIdForApiKey = async (
  authenticatedSupabase: SupabaseClient,
  apiKey: string,
): Promise<string> => {
  const { data: userId, error: apiKeyError } = await authenticatedSupabase
    .schema("keyhippo")
    .rpc("get_uid_for_key", { user_api_key: apiKey });

  if (apiKeyError) {
    throw createUnauthorizedError("Invalid API key.");
  }

  if (!userId) {
    throw createUnauthorizedError("API key does not correspond to any user.");
  }

  return userId;
};

/**
 * Retrieves the authenticated user's ID using the Supabase client.
 * @param supabase - The Supabase client.
 * @returns The authenticated user's ID.
 * @throws AuthenticationError if retrieving the user fails or the user is not authenticated.
 */
const getAuthenticatedUserId = async (
  supabase: SupabaseClient,
): Promise<string> => {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error) {
    throw createAuthenticationError("Failed to retrieve authenticated user.");
  }

  if (!user) {
    throw createUnauthorizedError("User not authenticated.");
  }

  return user.id;
};

/**
 * Logs the authentication event.
 * @param logger - The logger instance.
 * @param userId - The authenticated user's ID.
 */
const logAuthentication = (logger: Logger, userId: string): void => {
  logger.info(`User authenticated: ${userId}`);
};

/**
 * Handles errors that occur during the authentication process.
 * @param error - The error encountered.
 * @param logger - The logger instance.
 * @throws AppError based on the error type.
 */
const handleAuthenticationError = (error: unknown, logger: Logger): never => {
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
};

/**
 * Authenticates a user based on the provided headers and Supabase client.
 * @param headers - The request headers.
 * @param supabase - The Supabase client.
 * @param logger - The logger instance.
 * @returns An AuthResult containing the user ID and authenticated Supabase client.
 * @throws AppError if authentication fails.
 */
export const authenticate = async (
  headers: Headers,
  supabase: SupabaseClient,
  logger: Logger,
): Promise<AuthResult> => {
  try {
    const apiKey = extractApiKey(headers);
    if (apiKey) {
      const authenticatedSupabase = createAuthenticatedSupabaseClient(
        supabase,
        apiKey,
      );
      const userId = await getUserIdForApiKey(authenticatedSupabase, apiKey);
      logAuthentication(logger, userId);
      return { userId, supabase: authenticatedSupabase };
    } else {
      const userId = await getAuthenticatedUserId(supabase);
      logAuthentication(logger, userId);
      return { userId, supabase };
    }
  } catch (error) {
    // Use 'return' to help TypeScript understand that this path never returns
    return handleAuthenticationError(error, logger);
  }
};
