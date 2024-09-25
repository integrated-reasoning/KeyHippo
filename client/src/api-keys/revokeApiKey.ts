import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../types";
import { logInfo, logError, createDatabaseError } from "../utils";

/**
 * Executes the RPC call to revoke an existing API key for a user.
 * @param supabase - The Supabase client instance.
 * @param apiKeyId - The UUID of the API key to revoke.
 * @returns A promise that resolves to a boolean indicating success of the revocation.
 * @throws Error if the RPC call fails to revoke the API key.
 */
const executeRevokeApiKeyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  apiKeyId: string,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("revoke_api_key", {
      api_key_id: apiKeyId,
    });

  if (error) {
    throw new Error(`Error revoking API key: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful revocation of an API key.
 * @param logger - The logger instance used for logging.
 * @param apiKeyId - The UUID of the revoked API key.
 */
const logApiKeyRevocation = (logger: Logger, apiKeyId: string): void => {
  logInfo(logger, `API key revoked: ${apiKeyId}`);
};

/**
 * Handles errors that occur during the API key revocation process.
 * @param error - The error encountered during the revocation process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleRevokeApiKeyError = (error: unknown, logger: Logger): never => {
  logError(logger, `Failed to revoke API key: ${error}`);
  throw createDatabaseError(`Failed to revoke API key: ${error}`);
};

/**
 * Revokes an existing API key.
 * @param supabase - The Supabase client used to interact with the database.
 * @param apiKeyId - The UUID of the API key to revoke.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves to a boolean indicating success of the revocation.
 * @throws AppError if the revocation process fails.
 */
export const revokeApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  apiKeyId: string,
  logger: Logger,
): Promise<boolean> => {
  try {
    const success = await executeRevokeApiKeyRpc(supabase, apiKeyId);
    if (success) {
      logApiKeyRevocation(logger, apiKeyId);
    }
    return success;
  } catch (error) {
    return handleRevokeApiKeyError(error, logger);
  }
};
