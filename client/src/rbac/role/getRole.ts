import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, RoleId, Role } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to retrieve a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role being retrieved.
 */
const logGetRoleAttempt = (logger: Logger, roleId: RoleId): void => {
  logDebug(logger, `Attempting to retrieve role '${roleId}'`);
};

/**
 * Executes the RPC call to get a role from the database.
 * @param supabase - The Supabase client instance.
 * @param roleId - The ID of the role being retrieved.
 * @returns A promise that resolves with the Role object or null if not found.
 * @throws Error if the RPC call fails to retrieve the role.
 */
const executeGetRoleRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
): Promise<Role | null> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("get_role", {
      p_role_id: roleId,
    });

  if (error) {
    throw new Error(`Get Role RPC failed: ${error.message}`);
  }

  return data || null;
};

/**
 * Logs the successful retrieval of a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role that was retrieved.
 * @param role - The retrieved Role object.
 */
const logGetRoleSuccess = (
  logger: Logger,
  roleId: RoleId,
  role: Role | null,
): void => {
  if (role) {
    logInfo(logger, `Successfully retrieved role '${roleId}'`);
  } else {
    logInfo(logger, `Role '${roleId}' not found`);
  }
};

/**
 * Handles errors that occur during the get role process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetRoleError = (
  error: unknown,
  logger: Logger,
  roleId: RoleId,
): never => {
  logError(logger, `Failed to retrieve role '${roleId}'. Error: ${error}`);
  throw createDatabaseError(`Failed to retrieve role: ${error}`);
};

/**
 * Retrieves an existing role from the RBAC system.
 * @param supabase - The Supabase client.
 * @param roleId - The ID of the role to retrieve.
 * @param logger - The logger instance.
 * @returns The Role object if found, or null if not found.
 * @throws ApplicationError if the process fails.
 */
export const getRole = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  logger: Logger,
): Promise<Role | null> => {
  try {
    logGetRoleAttempt(logger, roleId);
    const role = await executeGetRoleRpc(supabase, roleId);
    logGetRoleSuccess(logger, roleId, role);
    return role;
  } catch (error) {
    return handleGetRoleError(error, logger, roleId);
  }
};
