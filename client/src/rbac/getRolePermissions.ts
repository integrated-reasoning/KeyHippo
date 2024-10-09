import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, RoleId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to retrieve role permissions.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role.
 */
const logGetRolePermissionsAttempt = (logger: Logger, roleId: RoleId): void => {
  logDebug(logger, `Attempting to retrieve permissions for Role ID: ${roleId}`);
};

/**
 * Executes the RPC call to retrieve role permissions from the database.
 * @param supabase - The Supabase client instance.
 * @param roleId - The ID of the role.
 * @returns A promise that resolves with an array of permission names.
 * @throws Error if the RPC call fails to retrieve permissions.
 */
const executeGetRolePermissionsRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
): Promise<{ permissions: string[] }> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("get_role_permissions", {
      p_role_id: roleId,
    })
    .single<{ permissions: string[] }>();

  if (error) {
    throw new Error(`Get Role Permissions RPC failed: ${error.message}`);
  }

  if (!data || !data.permissions) {
    throw new Error("Invalid data returned from get_role_permissions RPC");
  }

  return { permissions: data.permissions };
};

/**
 * Logs the successful retrieval of role permissions.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role.
 * @param permissions - The list of permissions retrieved.
 */
const logGetRolePermissionsSuccess = (
  logger: Logger,
  roleId: RoleId,
  permissions: string[],
): void => {
  logInfo(
    logger,
    `Successfully retrieved permissions for Role ID: ${roleId}. Permissions: ${permissions.join(", ")}`,
  );
};

/**
 * Handles errors that occur during the get role permissions process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetRolePermissionsError = (
  error: unknown,
  logger: Logger,
  roleId: RoleId,
): never => {
  logError(
    logger,
    `Failed to retrieve permissions for Role ID: ${roleId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to get role permissions: ${error}`);
};

/**
 * Retrieves the permissions associated with a specific role.
 * @param supabase - The Supabase client.
 * @param roleId - The ID of the role.
 * @param logger - The logger instance.
 * @returns An array of permission names.
 * @throws ApplicationError if the process fails.
 */
export const getRolePermissions = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  logger: Logger,
): Promise<string[]> => {
  try {
    logGetRolePermissionsAttempt(logger, roleId);
    const result = await executeGetRolePermissionsRpc(supabase, roleId);
    logGetRolePermissionsSuccess(logger, roleId, result.permissions);
    return result.permissions;
  } catch (error) {
    return handleGetRolePermissionsError(error, logger, roleId);
  }
};
