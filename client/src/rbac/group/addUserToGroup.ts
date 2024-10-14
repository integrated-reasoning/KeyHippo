import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Executes the RPC call to add a user to a group with a specific role.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user to be added to the group.
 * @param groupId - The ID of the group to which the user will be added.
 * @param roleName - The name of the role to assign to the user within the group.
 * @returns A promise that resolves when the user has been successfully added to the group.
 * @throws Error if the RPC call fails to add the user to the group.
 */
const executeAddUserToGroupRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  groupId: string,
  roleName: string,
): Promise<void> => {
  const { error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("add_user_to_group", {
      p_user_id: userId,
      p_group_id: groupId,
      p_role_name: roleName,
    });

  if (error) {
    throw new Error(`Failed to add user to group: ${error.message}`);
  }
};

/**
 * Logs the attempt to add a user to a group with a specific role.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user being added to the group.
 * @param groupId - The ID of the group to which the user is being added.
 * @param roleName - The name of the role assigned to the user within the group.
 */
const logAddUserToGroupAttempt = (
  logger: Logger,
  userId: string,
  groupId: string,
  roleName: string,
): void => {
  logDebug(
    logger,
    `Adding user ${userId} to group ${groupId} with role ${roleName}`,
  );
};

/**
 * Logs the successful addition of a user to a group.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user who was added to the group.
 * @param groupId - The ID of the group to which the user was added.
 */
const logAddUserToGroupSuccess = (
  logger: Logger,
  userId: string,
  groupId: string,
): void => {
  logInfo(logger, `Successfully added user ${userId} to group ${groupId}`);
};

/**
 * Handles errors that occur during the process of adding a user to a group.
 * @param error - The error encountered during the addition process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleAddUserToGroupError = (error: unknown, logger: Logger): never => {
  logError(logger, `Failed to add user to group: ${error}`);
  throw createDatabaseError(`Failed to add user to group: ${error}`);
};

/**
 * Adds a user to a group with a specific role.
 * @param supabase - The Supabase client used to interact with the database.
 * @param userId - The ID of the user to be added to the group.
 * @param groupId - The ID of the group to which the user will be added.
 * @param roleName - The name of the role to assign to the user within the group.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves when the user has been successfully added to the group.
 * @throws AppError if the addition process fails.
 */
export const addUserToGroup = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  groupId: string,
  roleName: string,
  logger: Logger,
): Promise<void> => {
  try {
    logAddUserToGroupAttempt(logger, userId, groupId, roleName);
    await executeAddUserToGroupRpc(supabase, userId, groupId, roleName);
    logAddUserToGroupSuccess(logger, userId, groupId);
  } catch (error) {
    return handleAddUserToGroupError(error, logger);
  }
};
