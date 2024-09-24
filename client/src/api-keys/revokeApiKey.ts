import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../types";
import { logInfo, logError, createDatabaseError } from "../utils";

/**
 * Executes the RPC call to revoke an existing API key for a user.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user whose API key is to be revoked.
 * @param secretId - The secret ID of the API key to revoke.
 * @returns A promise that resolves when the API key revocation is successful.
 * @throws Error if the RPC call fails to revoke the API key.
 */
const executeRevokeApiKeyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  secretId: string,
): Promise<void> => {
  const { error } = await supabase.schema("keyhippo").rpc("revoke_api_key", {
    id_of_user: userId,
    secret_id: secretId,
  });

  if (error) {
    throw new Error(`Error revoking API key: ${error.message}`);
  }
};

/**
 * Logs the successful revocation of an API key for a user.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose API key was revoked.
 * @param secretId - The secret ID of the revoked API key.
 */
const logApiKeyRevocation = (
  logger: Logger,
  userId: string,
  secretId: string,
): void => {
  logInfo(
    logger,
    `API key revoked for user: ${userId}, Secret ID: ${secretId}`,
  );
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
 * Revokes an existing API key for a user.
 * @param supabase - The Supabase client used to interact with the database.
 * @param userId - The ID of the user whose API key is to be revoked.
 * @param secretId - The secret ID of the API key to revoke.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves when the API key has been successfully revoked.
 * @throws AppError if the revocation process fails.
 */
export const revokeApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  secretId: string,
  logger: Logger,
): Promise<void> => {
  try {
    await executeRevokeApiKeyRpc(supabase, userId, secretId);
    logApiKeyRevocation(logger, userId, secretId);
  } catch (error) {
    return handleRevokeApiKeyError(error, logger);
  }
};
