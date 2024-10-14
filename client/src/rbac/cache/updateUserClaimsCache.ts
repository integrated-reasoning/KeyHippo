import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to update the claims cache for a user.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose claims cache is being updated.
 */
const logUpdateUserClaimsCacheAttempt = (
  logger: Logger,
  userId: string,
): void => {
  logDebug(logger, `Updating claims cache for user ${userId}`);
};

/**
 * Executes the RPC call to update the user claims cache in the database.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user whose claims cache is to be updated.
 * @returns A promise that resolves when the claims cache update is successful.
 * @throws Error if the RPC call fails to update the claims cache.
 */
const executeUpdateUserClaimsCacheRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
): Promise<void> => {
  const { error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("update_user_claims_cache", {
      p_user_id: userId,
    });

  if (error) {
    throw new Error(`Failed to update claims cache: ${error.message}`);
  }
};

/**
 * Logs the successful update of the claims cache for a user.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose claims cache was updated.
 */
const logUpdateUserClaimsCacheSuccess = (
  logger: Logger,
  userId: string,
): void => {
  logInfo(logger, `Successfully updated claims cache for user ${userId}`);
};

/**
 * Handles errors that occur during the process of updating the user claims cache.
 * @param error - The error encountered during the update process.
 * @param logger - The logger instance used for logging errors.
 * @param userId - The ID of the user whose claims cache update failed.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleUpdateUserClaimsCacheError = (
  error: unknown,
  logger: Logger,
  userId: string,
): never => {
  logError(
    logger,
    `Failed to update claims cache for user ${userId}: ${error}`,
  );
  throw createDatabaseError(`Failed to update claims cache: ${error}`);
};

/**
 * Updates the user claims cache.
 * @param supabase - The Supabase client used to interact with the database.
 * @param userId - The ID of the user whose claims cache is to be updated.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves when the claims cache has been successfully updated.
 * @throws AppError if the update process fails.
 */
export const updateUserClaimsCache = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<void> => {
  try {
    logUpdateUserClaimsCacheAttempt(logger, userId);
    await executeUpdateUserClaimsCacheRpc(supabase, userId);
    logUpdateUserClaimsCacheSuccess(logger, userId);
  } catch (error) {
    return handleUpdateUserClaimsCacheError(error, logger, userId);
  }
};
