import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, RoleId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to delete a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role being deleted.
 */
const logDeleteRoleAttempt = (logger: Logger, roleId: RoleId): void => {
  logDebug(logger, `Attempting to delete role '${roleId}'`);
};

/**
 * Executes the RPC call to delete a role from the database.
 * @param supabase - The Supabase client instance.
 * @param roleId - The ID of the role being deleted.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to delete the role.
 */
const executeDeleteRoleRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("delete_role", {
      p_role_id: roleId,
    });

  if (error) {
    throw new Error(`Delete Role RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful deletion of a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role that was deleted.
 */
const logDeleteRoleSuccess = (logger: Logger, roleId: RoleId): void => {
  logInfo(logger, `Successfully deleted role '${roleId}'`);
};

/**
 * Handles errors that occur during the delete role process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleDeleteRoleError = (
  error: unknown,
  logger: Logger,
  roleId: RoleId,
): never => {
  logError(logger, `Failed to delete role '${roleId}'. Error: ${error}`);
  throw createDatabaseError(`Failed to delete role: ${error}`);
};

/**
 * Deletes an existing role from the RBAC system.
 * @param supabase - The Supabase client.
 * @param roleId - The ID of the role to delete.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the role was successfully deleted.
 * @throws ApplicationError if the process fails.
 */
export const deleteRole = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  logger: Logger,
): Promise<boolean> => {
  try {
    logDeleteRoleAttempt(logger, roleId);
    const result = await executeDeleteRoleRpc(supabase, roleId);
    logDeleteRoleSuccess(logger, roleId);
    return result;
  } catch (error) {
    return handleDeleteRoleError(error, logger, roleId);
  }
};
