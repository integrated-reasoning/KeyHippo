import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, GroupId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to set a group attribute.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group.
 * @param attribute - The name of the attribute being set.
 * @param value - The value of the attribute.
 */
const logSetGroupAttributeAttempt = (
  logger: Logger,
  groupId: GroupId,
  attribute: string,
  value: any,
): void => {
  logDebug(
    logger,
    `Attempting to set attribute '${attribute}' for Group ID: ${groupId} with value: ${value}`,
  );
};

/**
 * Executes the RPC call to set the group attribute in the database.
 * @param supabase - The Supabase client instance.
 * @param groupId - The ID of the group.
 * @param attribute - The name of the attribute being set.
 * @param value - The value of the attribute.
 * @returns A promise that resolves when the attribute is set successfully.
 * @throws Error if the RPC call fails to set the attribute.
 */
const executeSetGroupAttributeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
  attribute: string,
  value: any,
): Promise<void> => {
  const { error } = await supabase
    .schema("keyhippo_abac")
    .rpc("set_group_attribute", {
      p_group_id: groupId,
      p_attribute: attribute,
      p_value: value,
    });

  if (error) {
    throw new Error(`Set Group Attribute RPC failed: ${error.message}`);
  }
};

/**
 * Logs the successful setting of a group attribute.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group.
 * @param attribute - The name of the attribute set.
 */
const logSetGroupAttributeSuccess = (
  logger: Logger,
  groupId: GroupId,
  attribute: string,
): void => {
  logInfo(
    logger,
    `Successfully set attribute '${attribute}' for Group ID: ${groupId}`,
  );
};

/**
 * Handles errors that occur during the set group attribute process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleSetGroupAttributeError = (
  error: unknown,
  logger: Logger,
  groupId: GroupId,
  attribute: string,
): never => {
  logError(
    logger,
    `Failed to set attribute '${attribute}' for Group ID: ${groupId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to set group attribute: ${error}`);
};

/**
 * Sets an attribute for a specified group in the ABAC system.
 * @param supabase - The Supabase client.
 * @param groupId - The ID of the group.
 * @param attribute - The name of the attribute being set.
 * @param value - The value of the attribute.
 * @param logger - The logger instance.
 * @returns A promise that resolves when the attribute is set successfully.
 * @throws ApplicationError if the process fails.
 */
export const setGroupAttribute = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
  attribute: string,
  value: any,
  logger: Logger,
): Promise<void> => {
  try {
    logSetGroupAttributeAttempt(logger, groupId, attribute, value);
    await executeSetGroupAttributeRpc(supabase, groupId, attribute, value);
    logSetGroupAttributeSuccess(logger, groupId, attribute);
  } catch (error) {
    return handleSetGroupAttributeError(error, logger, groupId, attribute);
  }
};
