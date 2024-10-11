import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, UserId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to set a user attribute.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user.
 * @param attribute - The name of the attribute being set.
 * @param value - The value of the attribute.
 */
const logSetUserAttributeAttempt = (
  logger: Logger,
  userId: UserId,
  attribute: string,
  value: any,
): void => {
  logDebug(
    logger,
    `Attempting to set attribute '${attribute}' for User ID: ${userId} with value: ${value}`,
  );
};

/**
 * Executes the RPC call to set the user attribute in the database.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user.
 * @param attribute - The name of the attribute being set.
 * @param value - The value of the attribute.
 * @returns A promise that resolves when the attribute is set successfully.
 * @throws Error if the RPC call fails to set the attribute.
 */
const executeSetUserAttributeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: UserId,
  attribute: string,
  value: any,
): Promise<void> => {
  const { error } = await supabase
    .schema("keyhippo_abac")
    .rpc("set_user_attribute", {
      p_user_id: userId,
      p_attribute: attribute,
      p_value: value,
    });

  if (error) {
    throw new Error(`Set User Attribute RPC failed: ${error.message}`);
  }
};

/**
 * Logs the successful setting of a user attribute.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user.
 * @param attribute - The name of the attribute set.
 */
const logSetUserAttributeSuccess = (
  logger: Logger,
  userId: UserId,
  attribute: string,
): void => {
  logInfo(
    logger,
    `Successfully set attribute '${attribute}' for User ID: ${userId}`,
  );
};

/**
 * Handles errors that occur during the set user attribute process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleSetUserAttributeError = (
  error: unknown,
  logger: Logger,
  userId: UserId,
  attribute: string,
): never => {
  logError(
    logger,
    `Failed to set attribute '${attribute}' for User ID: ${userId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to set user attribute: ${error}`);
};

/**
 * Sets an attribute for a specified user in the ABAC system.
 * @param supabase - The Supabase client.
 * @param userId - The ID of the user.
 * @param attribute - The name of the attribute being set.
 * @param value - The value of the attribute.
 * @param logger - The logger instance.
 * @returns A promise that resolves when the attribute is set successfully.
 * @throws ApplicationError if the process fails.
 */
export const setUserAttribute = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: UserId,
  attribute: string,
  value: any,
  logger: Logger,
): Promise<void> => {
  try {
    logSetUserAttributeAttempt(logger, userId, attribute, value);
    await executeSetUserAttributeRpc(supabase, userId, attribute, value);
    logSetUserAttributeSuccess(logger, userId, attribute);
  } catch (error) {
    return handleSetUserAttributeError(error, logger, userId, attribute);
  }
};
