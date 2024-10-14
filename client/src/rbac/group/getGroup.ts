import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, GroupId, Group } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to retrieve a group.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group being retrieved.
 */
const logGetGroupAttempt = (logger: Logger, groupId: GroupId): void => {
  logDebug(logger, `Attempting to retrieve group with ID '${groupId}'`);
};

/**
 * Executes the RPC call to get a group from the database.
 * @param supabase - The Supabase client instance.
 * @param groupId - The ID of the group being retrieved.
 * @returns A promise that resolves with the Group object or null if not found.
 * @throws Error if the RPC call fails to retrieve the group.
 */
const executeGetGroupRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
): Promise<Group | null> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("get_group", {
      p_group_id: groupId,
    });

  if (error) {
    throw new Error(`Get Group RPC failed: ${error.message}`);
  }

  return data || null;
};

/**
 * Logs the successful retrieval of a group.
 * @param logger - The logger instance used for logging.
 * @param groupId - The ID of the group that was retrieved.
 */
const logGetGroupSuccess = (logger: Logger, groupId: GroupId): void => {
  logInfo(logger, `Successfully retrieved group with ID: ${groupId}`);
};

/**
 * Handles errors that occur during the get group process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetGroupError = (
  error: unknown,
  logger: Logger,
  groupId: GroupId,
): never => {
  logError(
    logger,
    `Failed to retrieve group with ID '${groupId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to retrieve group: ${error}`);
};

/**
 * Retrieves an existing group.
 * @param supabase - The Supabase client.
 * @param groupId - The ID of the group to retrieve.
 * @param logger - The logger instance.
 * @returns The Group object if found, or null if not found.
 * @throws ApplicationError if the process fails.
 */
export const getGroup = async (
  supabase: SupabaseClient<any, "public", any>,
  groupId: GroupId,
  logger: Logger,
): Promise<Group | null> => {
  try {
    logGetGroupAttempt(logger, groupId);
    const result = await executeGetGroupRpc(supabase, groupId);
    if (result) {
      logGetGroupSuccess(logger, groupId);
    }
    return result;
  } catch (error) {
    return handleGetGroupError(error, logger, groupId);
  }
};
