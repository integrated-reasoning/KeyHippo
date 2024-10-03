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
 * Retrieves the current user context from the Supabase backend.
 * @param supabase - The Supabase client to use for the RPC call.
 * @returns A Promise resolving to the user context (AuthResult["auth"]).
 * @throws {ApplicationError} If the user context cannot be retrieved or the user is not authenticated.
 */
const getCurrentUserContext = async (
  supabase: SupabaseClient,
): Promise<AuthResult["auth"]> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("current_user_context")
    .single();
  if (error) {
    throw {
      type: "AuthenticationError",
      message: "Failed to retrieve user context.",
    } as ApplicationError;
  }
  if (!data) {
    throw {
      type: "UnauthorizedError",
      message: "User not authenticated.",
    } as ApplicationError;
  }
  return data as AuthResult["auth"];
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
 * @returns An AuthResult containing the auth context and authenticated Supabase client.
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
      const authResult = await getCurrentUserContext(authenticatedSupabase);
      logAuthentication(logger, authResult.user_id);
      return { auth: authResult, supabase: authenticatedSupabase };
    } else {
      const authResult = await getCurrentUserContext(supabase);
      logAuthentication(logger, authResult.user_id);
      return { auth: authResult, supabase };
    }
  } catch (error) {
    return handleAuthenticationError(error, logger);
  }
};
