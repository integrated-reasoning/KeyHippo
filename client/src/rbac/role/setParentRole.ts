import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, RoleId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to set a parent role.
 * @param logger - The logger instance used for logging.
 * @param childRoleId - The ID of the child role.
 * @param parentRoleId - The ID of the parent role or null to remove the parent.
 */
const logSetParentRoleAttempt = (
  logger: Logger,
  childRoleId: RoleId,
  parentRoleId: RoleId | null,
): void => {
  logDebug(
    logger,
    `Attempting to set parent role. Child Role ID: ${childRoleId}, Parent Role ID: ${parentRoleId}`,
  );
};

/**
 * Executes the RPC call to set the parent role in the database.
 * @param supabase - The Supabase client instance.
 * @param childRoleId - The ID of the child role.
 * @param parentRoleId - The ID of the parent role or null to remove the parent.
 * @returns A promise that resolves with the new parent_role_id or null if removed.
 * @throws Error if the RPC call fails to set the parent role.
 */
const executeSetParentRoleRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: RoleId,
  parentRoleId: RoleId | null,
): Promise<{ parent_role_id: RoleId | null }> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("set_parent_role", {
      p_child_role_id: childRoleId,
      p_new_parent_role_id: parentRoleId,
    });

  if (error) throw new Error(`Failed to set parent role: ${error.message}`);
  if (!data) throw new Error("Invalid data returned from set_parent_role RPC");

  // Return the parentRoleId if it was set, or null if it was removed
  return { parent_role_id: parentRoleId };
};

/**
 * Logs the successful setting of a parent role.
 * @param logger - The logger instance used for logging.
 * @param childRoleId - The ID of the child role.
 * @param parentRoleId - The ID of the parent role or null if removed.
 */
const logSetParentRoleSuccess = (
  logger: Logger,
  childRoleId: RoleId,
  parentRoleId: RoleId | null,
): void => {
  if (parentRoleId) {
    logInfo(
      logger,
      `Successfully set parent role. Child Role ID: ${childRoleId}, Parent Role ID: ${parentRoleId}`,
    );
  } else {
    logInfo(
      logger,
      `Successfully removed parent role. Child Role ID: ${childRoleId}`,
    );
  }
};

/**
 * Handles errors that occur during the set parent role process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleSetParentRoleError = (
  error: unknown,
  logger: Logger,
  childRoleId: RoleId,
  parentRoleId: RoleId | null,
): never => {
  logError(
    logger,
    `Failed to set parent role for Child Role ID: ${childRoleId}, Parent Role ID: ${parentRoleId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to set parent role: ${error}`);
};

/**
 * Sets a parent role for a specified child role.
 * @param supabase - The Supabase client.
 * @param childRoleId - The ID of the child role.
 * @param parentRoleId - The ID of the parent role or null to remove the parent.
 * @param logger - The logger instance.
 * @returns An object containing the new parent_role_id or null if removed.
 * @throws ApplicationError if the process fails.
 */
export const setParentRole = async (
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: RoleId,
  parentRoleId: RoleId | null,
  logger: Logger,
): Promise<{ parent_role_id: RoleId | null }> => {
  try {
    logSetParentRoleAttempt(logger, childRoleId, parentRoleId);
    const result = await executeSetParentRoleRpc(
      supabase,
      childRoleId,
      parentRoleId,
    );
    logSetParentRoleSuccess(logger, childRoleId, result.parent_role_id);
    return result;
  } catch (error) {
    return handleSetParentRoleError(error, logger, childRoleId, parentRoleId);
  }
};
