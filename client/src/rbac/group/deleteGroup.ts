import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, GroupId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to delete a group.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group being deleted.
 */
const logDeleteGroupAttempt = (logger: Logger, groupId: GroupId): void => {
  logDebug(logger, `Attempting to delete group with ID '${groupId}'`);
};

/**
 * Executes the RPC call to delete a group from the database.
 * @param supabase - The Supabase client instance.
 * @param groupId - The ID of the group being deleted.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to delete the group.
 */
const executeDeleteGroupRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("delete_group", {
      p_group_id: groupId,
    });

  if (error) {
    throw new Error(`Delete Group RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful deletion of a group.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group that was deleted.
 */
const logDeleteGroupSuccess = (logger: Logger, groupId: GroupId): void => {
  logInfo(logger, `Successfully deleted group with ID: ${groupId}`);
};

/**
 * Handles errors that occur during the delete group process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleDeleteGroupError = (
  error: unknown,
  logger: Logger,
  groupId: GroupId,
): never => {
  logError(
    logger,
    `Failed to delete group with ID '${groupId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to delete group: ${error}`);
};

/**
 * Deletes an existing group.
 * @param supabase - The Supabase client.
 * @param groupId - The ID of the group to delete.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the group was successfully deleted.
 * @throws ApplicationError if the process fails.
 */
export const deleteGroup = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
  logger: Logger,
): Promise<boolean> => {
  try {
    logDeleteGroupAttempt(logger, groupId);
    const result = await executeDeleteGroupRpc(supabase, groupId);
    logDeleteGroupSuccess(logger, groupId);
    return result;
  } catch (error) {
    return handleDeleteGroupError(error, logger, groupId);
  }
};
