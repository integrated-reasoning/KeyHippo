import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../types";
import { logDebug, logInfo } from "../utils/logging";
import { handleError } from "../utils";

/**
 * Logs an attempt to set a specific user attribute.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose attribute is being set.
 * @param attribute - The name of the attribute being set.
 */
const logSetUserAttributeAttempt = (
  logger: Logger,
  userId: string,
  attribute: string,
): void => {
  logDebug(logger, `Setting attribute ${attribute} for user ${userId}`);
};

/**
 * Executes the RPC call to set a user attribute in the database.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user whose attribute is being set.
 * @param attribute - The name of the attribute to set.
 * @param value - The value to assign to the attribute.
 * @returns A promise that resolves when the operation is complete.
 * @throws Error if the RPC call fails to set the user attribute.
 */
const executeSetUserAttributeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
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
    throw new Error(`Failed to set user attribute: ${error.message}`);
  }
};

/**
 * Logs the successful setting of a user attribute.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose attribute was set.
 * @param attribute - The name of the attribute that was set.
 */
const logSetUserAttributeSuccess = (
  logger: Logger,
  userId: string,
  attribute: string,
): void => {
  logInfo(logger, `Successfully set attribute ${attribute} for user ${userId}`);
};

/**
 * Sets a specific attribute for a user in the database.
 * @param supabase - The Supabase client instance used to interact with the database.
 * @param userId - The ID of the user whose attribute is to be set.
 * @param attribute - The name of the attribute to set.
 * @param value - The value to assign to the attribute.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves when the attribute has been set successfully.
 * @throws AppError if the setting process fails.
 */
export const setUserAttribute = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  attribute: string,
  value: any,
  logger: Logger,
): Promise<void> => {
  try {
    logSetUserAttributeAttempt(logger, userId, attribute);
    await executeSetUserAttributeRpc(supabase, userId, attribute, value);
    logSetUserAttributeSuccess(logger, userId, attribute);
  } catch (error) {
    return handleError(error, logger, "Failed to set user attribute");
  }
};
