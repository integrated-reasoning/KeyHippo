import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, RoleId, PermissionName } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to remove a permission from a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role from which the permission is being removed.
 * @param permissionName - The name of the permission being removed.
 */
const logRemovePermissionAttempt = (
  logger: Logger,
  roleId: RoleId,
  permissionName: PermissionName,
): void => {
  logDebug(
    logger,
    `Attempting to remove permission '${permissionName}' from role '${roleId}'`,
  );
};

/**
 * Executes the RPC call to remove a permission from a role in the database.
 * @param supabase - The Supabase client instance.
 * @param roleId - The ID of the role from which the permission is being removed.
 * @param permissionName - The name of the permission being removed.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to remove the permission.
 */
const executeRemovePermissionRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  permissionName: PermissionName,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("remove_permission_from_role", {
      p_role_id: roleId,
      p_permission_name: permissionName,
    });

  if (error) {
    throw new Error(`Remove Permission RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful removal of a permission from a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role from which the permission was removed.
 * @param permissionName - The name of the permission that was removed.
 */
const logRemovePermissionSuccess = (
  logger: Logger,
  roleId: RoleId,
  permissionName: PermissionName,
): void => {
  logInfo(
    logger,
    `Successfully removed permission '${permissionName}' from role '${roleId}'`,
  );
};

/**
 * Handles errors that occur during the remove permission process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleRemovePermissionError = (
  error: unknown,
  logger: Logger,
  roleId: RoleId,
  permissionName: PermissionName,
): never => {
  logError(
    logger,
    `Failed to remove permission '${permissionName}' from role '${roleId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to remove permission from role: ${error}`);
};

/**
 * Removes a permission from a role.
 * @param supabase - The Supabase client.
 * @param roleId - The ID of the role from which the permission is being removed.
 * @param permissionName - The name of the permission to remove.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the permission was successfully removed.
 * @throws ApplicationError if the process fails.
 */
export const removePermissionFromRole = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  permissionName: PermissionName,
  logger: Logger,
): Promise<boolean> => {
  try {
    logRemovePermissionAttempt(logger, roleId, permissionName);
    const result = await executeRemovePermissionRpc(
      supabase,
      roleId,
      permissionName,
    );
    logRemovePermissionSuccess(logger, roleId, permissionName);
    return result;
  } catch (error) {
    return handleRemovePermissionError(error, logger, roleId, permissionName);
  }
};
