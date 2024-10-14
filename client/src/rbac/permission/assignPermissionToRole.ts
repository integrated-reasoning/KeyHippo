import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, RoleId, PermissionName } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to assign a permission to a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role to which the permission is being assigned.
 * @param permissionName - The name of the permission being assigned.
 */
const logAssignPermissionToRoleAttempt = (
  logger: Logger,
  roleId: RoleId,
  permissionName: PermissionName,
): void => {
  logDebug(
    logger,
    `Attempting to assign permission '${permissionName}' to role '${roleId}'`,
  );
};

/**
 * Executes the RPC call to assign a permission to a role in the database.
 * @param supabase - The Supabase client instance.
 * @param roleId - The ID of the role to which the permission is being assigned.
 * @param permissionName - The name of the permission being assigned.
 * @returns A promise that resolves when the assignment is successful.
 * @throws Error if the RPC call fails to assign the permission.
 */
const executeAssignPermissionToRoleRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  permissionName: PermissionName,
): Promise<void> => {
  const { error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("assign_permission_to_role", {
      p_role_id: roleId,
      p_permission_name: permissionName,
    });

  if (error) {
    throw new Error(`Assign Permission to Role RPC failed: ${error.message}`);
  }
};

/**
 * Logs the successful assignment of a permission to a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role to which the permission was assigned.
 * @param permissionName - The name of the permission that was assigned.
 */
const logAssignPermissionToRoleSuccess = (
  logger: Logger,
  roleId: RoleId,
  permissionName: PermissionName,
): void => {
  logInfo(
    logger,
    `Successfully assigned permission '${permissionName}' to role '${roleId}'`,
  );
};

/**
 * Handles errors that occur during the assign permission to role process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @param roleId - The ID of the role involved in the failed operation.
 * @param permissionName - The name of the permission involved in the failed operation.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleAssignPermissionToRoleError = (
  error: unknown,
  logger: Logger,
  roleId: RoleId,
  permissionName: PermissionName,
): never => {
  logError(
    logger,
    `Failed to assign permission '${permissionName}' to role '${roleId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to assign permission to role: ${error}`);
};

/**
 * Assigns a permission to a role.
 * @param supabase - The Supabase client.
 * @param roleId - The ID of the role to which the permission is being assigned.
 * @param permissionName - The name of the permission to assign.
 * @param logger - The logger instance.
 * @throws ApplicationError if the process fails.
 */
export const assignPermissionToRole = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  permissionName: PermissionName,
  logger: Logger,
): Promise<void> => {
  try {
    logAssignPermissionToRoleAttempt(logger, roleId, permissionName);
    await executeAssignPermissionToRoleRpc(supabase, roleId, permissionName);
    logAssignPermissionToRoleSuccess(logger, roleId, permissionName);
  } catch (error) {
    handleAssignPermissionToRoleError(error, logger, roleId, permissionName);
  }
};
