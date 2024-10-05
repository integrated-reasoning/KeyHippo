import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, GroupId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to get a group attribute.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group.
 * @param attribute - The name of the attribute being retrieved.
 */
const logGetGroupAttributeAttempt = (
  logger: Logger,
  groupId: GroupId,
  attribute: string,
): void => {
  logDebug(
    logger,
    `Attempting to retrieve attribute '${attribute}' for Group ID: ${groupId}`,
  );
};

/**
 * Executes the RPC call to retrieve the group attribute from the database.
 * @param supabase - The Supabase client instance.
 * @param groupId - The ID of the group.
 * @param attribute - The name of the attribute being retrieved.
 * @returns A promise that resolves with the attribute value or null if not set.
 * @throws Error if the RPC call fails to retrieve the attribute.
 */
const executeGetGroupAttributeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
  attribute: string,
): Promise<{ value: any }> => {
  const { data, error } = await supabase
    .schema("keyhippo_abac")
    .rpc("get_group_attribute", {
      p_group_id: groupId,
      p_attribute: attribute,
    })
    .single<{ value: any }>();

  if (error) {
    throw new Error(`Get Group Attribute RPC failed: ${error.message}`);
  }

  if (!data) {
    throw new Error("Invalid data returned from get_group_attribute RPC");
  }

  return { value: data.value };
};

/**
 * Logs the successful retrieval of a group attribute.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group.
 * @param attribute - The name of the attribute retrieved.
 * @param value - The value of the attribute.
 */
const logGetGroupAttributeSuccess = (
  logger: Logger,
  groupId: GroupId,
  attribute: string,
  value: any,
): void => {
  logInfo(
    logger,
    `Successfully retrieved attribute '${attribute}' for Group ID: ${groupId}. Value: ${value}`,
  );
};

/**
 * Handles errors that occur during the get group attribute process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetGroupAttributeError = (
  error: unknown,
  logger: Logger,
  groupId: GroupId,
  attribute: string,
): never => {
  logError(
    logger,
    `Failed to retrieve attribute '${attribute}' for Group ID: ${groupId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to get group attribute: ${error}`);
};

/**
 * Retrieves an attribute for a specified group in the ABAC system.
 * @param supabase - The Supabase client.
 * @param groupId - The ID of the group.
 * @param attribute - The name of the attribute being retrieved.
 * @param logger - The logger instance.
 * @returns The value of the attribute or null if not set.
 * @throws ApplicationError if the process fails.
 */
export const getGroupAttribute = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
  attribute: string,
  logger: Logger,
): Promise<any> => {
  try {
    logGetGroupAttributeAttempt(logger, groupId, attribute);
    const result = await executeGetGroupAttributeRpc(
      supabase,
      groupId,
      attribute,
    );
    logGetGroupAttributeSuccess(logger, groupId, attribute, result.value);
    return result.value;
  } catch (error) {
    return handleGetGroupAttributeError(error, logger, groupId, attribute);
  }
};
