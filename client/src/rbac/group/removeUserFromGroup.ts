import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, UserId, GroupId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to remove a user from a group.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user being removed from the group.
 * @param groupId - The ID of the group from which the user is being removed.
 */
const logRemoveUserFromGroupAttempt = (
  logger: Logger,
  userId: UserId,
  groupId: GroupId,
): void => {
  logDebug(
    logger,
    `Attempting to remove user '${userId}' from group '${groupId}'`,
  );
};

/**
 * Executes the RPC call to remove a user from a group in the database.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user being removed from the group.
 * @param groupId - The ID of the group from which the user is being removed.
 * @throws Error if the RPC call fails to remove the user from the group.
 */
const executeRemoveUserFromGroupRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: UserId,
  groupId: GroupId,
): Promise<void> => {
  const { error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("remove_user_from_group", {
      p_user_id: userId,
      p_group_id: groupId,
    });

  if (error) {
    throw new Error(`Remove User from Group RPC failed: ${error.message}`);
  }
};

/**
 * Logs the successful removal of a user from a group.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user removed from the group.
 * @param groupId - The ID of the group from which the user was removed.
 */
const logRemoveUserFromGroupSuccess = (
  logger: Logger,
  userId: UserId,
  groupId: GroupId,
): void => {
  logInfo(
    logger,
    `Successfully removed user '${userId}' from group '${groupId}'`,
  );
};

/**
 * Handles errors that occur during the remove user from group process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @param userId - The ID of the user involved in the failed operation.
 * @param groupId - The ID of the group involved in the failed operation.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleRemoveUserFromGroupError = (
  error: unknown,
  logger: Logger,
  userId: UserId,
  groupId: GroupId,
): never => {
  logError(
    logger,
    `Failed to remove user '${userId}' from group '${groupId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to remove user from group: ${error}`);
};

/**
 * Removes a user from a group.
 * @param supabase - The Supabase client.
 * @param userId - The ID of the user to be removed from the group.
 * @param groupId - The ID of the group from which the user is being removed.
 * @param logger - The logger instance.
 * @throws ApplicationError if the process fails.
 */
export const removeUserFromGroup = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: UserId,
  groupId: GroupId,
  logger: Logger,
): Promise<void> => {
  try {
    logRemoveUserFromGroupAttempt(logger, userId, groupId);
    await executeRemoveUserFromGroupRpc(supabase, userId, groupId);
    logRemoveUserFromGroupSuccess(logger, userId, groupId);
  } catch (error) {
    handleRemoveUserFromGroupError(error, logger, userId, groupId);
  }
};
