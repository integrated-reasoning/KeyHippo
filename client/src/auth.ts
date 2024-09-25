import { SupabaseClient, createClient } from "@supabase/supabase-js";
import {
  ApiKeyText,
  AuthResult,
  Logger,
  ApplicationError,
  UserId,
} from "./types";

/**
 * Extracts the API key from the Authorization header.
 * @param headers - The request headers.
 * @returns The API key if present, otherwise null.
 */
const extractApiKey = (headers: Headers): ApiKeyText | null => {
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
  apiKey: ApiKeyText,
): SupabaseClient => {
  return createClient(
    (supabase as any).supabaseUrl,
    (supabase as any).supabaseKey,
    {
      global: { headers: { "x-api-key": apiKey } },
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
 * @throws ApplicationError if the API key is invalid or does not correspond to any user.
 */
const getUserIdForApiKey = async (
  authenticatedSupabase: SupabaseClient,
  apiKey: ApiKeyText,
): Promise<UserId> => {
  const { data: userId, error: apiKeyError } = await authenticatedSupabase
    .schema("keyhippo")
    .rpc("verify_api_key", { api_key: apiKey });

  if (apiKeyError) {
    throw {
      type: "UnauthorizedError",
      message: "Invalid API key.",
    } as ApplicationError;
  }

  if (!userId) {
    throw {
      type: "UnauthorizedError",
      message: "API key does not correspond to any user.",
    } as ApplicationError;
  }

  return userId;
};

/**
 * Retrieves the authenticated user's ID using the Supabase client.
 * @param supabase - The Supabase client.
 * @returns The authenticated user's ID.
 * @throws ApplicationError if retrieving the user fails or the user is not authenticated.
 */
const getAuthenticatedUserId = async (
  supabase: SupabaseClient,
): Promise<UserId> => {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error) {
    throw {
      type: "AuthenticationError",
      message: "Failed to retrieve authenticated user.",
    } as ApplicationError;
  }

  if (!user) {
    throw {
      type: "UnauthorizedError",
      message: "User not authenticated.",
    } as ApplicationError;
  }

  return user.id;
};

/**
 * Logs the authentication event.
 * @param logger - The logger instance.
 * @param userId - The authenticated user's ID.
 */
const logAuthentication = (logger: Logger, userId: UserId): void => {
  logger.info(`User authenticated: ${userId}`);
};

/**
 * Handles errors that occur during the authentication process.
 * @param error - The error encountered.
 * @param logger - The logger instance.
 * @throws ApplicationError based on the error type.
 */
const handleAuthenticationError = (error: unknown, logger: Logger): never => {
  if (
    error &&
    typeof error === "object" &&
    "type" in error &&
    "message" in error
  ) {
    const appError = error as ApplicationError;
    logger.error(`Authentication failed: ${appError.message}`);
    throw appError;
  } else if (error instanceof Error) {
    logger.error(`Authentication failed: ${error.message}`);
    throw {
      type: "AuthenticationError",
      message: "Authentication failed due to an unexpected error.",
    } as ApplicationError;
  } else {
    logger.error(`Authentication failed: ${String(error)}`);
    throw {
      type: "AuthenticationError",
      message: "Authentication failed due to an unknown error.",
    } as ApplicationError;
  }
};

/**
 * Authenticates a user based on the provided headers and Supabase client.
 * @param headers - The request headers.
 * @param supabase - The Supabase client.
 * @param logger - The logger instance.
 * @returns An AuthResult containing the user ID and authenticated Supabase client.
 * @throws ApplicationError if authentication fails.
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
    return handleAuthenticationError(error, logger);
  }
};
