import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, GroupId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to update a group.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group being updated.
 */
const logUpdateGroupAttempt = (logger: Logger, groupId: GroupId): void => {
  logDebug(logger, `Attempting to update group with ID '${groupId}'`);
};

/**
 * Executes the RPC call to update a group in the database.
 * @param supabase - The Supabase client instance.
 * @param groupId - The ID of the group being updated.
 * @param groupName - The new name for the group.
 * @param description - The new description for the group.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to update the group.
 */
const executeUpdateGroupRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
  groupName: string,
  description: string,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("update_group", {
      p_group_id: groupId,
      p_name: groupName,
      p_description: description,
    });

  if (error) {
    throw new Error(`Update Group RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful update of a group.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group that was updated.
 */
const logUpdateGroupSuccess = (logger: Logger, groupId: GroupId): void => {
  logInfo(logger, `Successfully updated group with ID: ${groupId}`);
};

/**
 * Handles errors that occur during the update group process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleUpdateGroupError = (
  error: unknown,
  logger: Logger,
  groupId: GroupId,
): never => {
  logError(
    logger,
    `Failed to update group with ID '${groupId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to update group: ${error}`);
};

/**
 * Updates an existing group.
 * @param supabase - The Supabase client.
 * @param groupId - The ID of the group to update.
 * @param groupName - The new name for the group.
 * @param description - The new description for the group.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the group was successfully updated.
 * @throws ApplicationError if the process fails.
 */
export const updateGroup = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
  groupName: string,
  description: string,
  logger: Logger,
): Promise<boolean> => {
  try {
    logUpdateGroupAttempt(logger, groupId);
    const result = await executeUpdateGroupRpc(
      supabase,
      groupId,
      groupName,
      description,
    );
    logUpdateGroupSuccess(logger, groupId);
    return result;
  } catch (error) {
    return handleUpdateGroupError(error, logger, groupId);
  }
};
