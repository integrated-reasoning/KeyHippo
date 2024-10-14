import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, RoleId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to update a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role being updated.
 * @param name - The new name for the role.
 * @param description - The new description for the role.
 */
const logUpdateRoleAttempt = (
  logger: Logger,
  roleId: RoleId,
  name: string,
  description: string,
): void => {
  logDebug(
    logger,
    `Attempting to update role '${roleId}' with name '${name}' and description '${description}'`,
  );
};

/**
 * Executes the RPC call to update a role in the database.
 * @param supabase - The Supabase client instance.
 * @param roleId - The ID of the role being updated.
 * @param name - The new name for the role.
 * @param description - The new description for the role.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to update the role.
 */
const executeUpdateRoleRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  name: string,
  description: string,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("update_role", {
      p_role_id: roleId,
      p_name: name,
      p_description: description,
    });

  if (error) {
    throw new Error(`Update Role RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful update of a role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role that was updated.
 * @param name - The new name of the role.
 * @param description - The new description of the role.
 */
const logUpdateRoleSuccess = (
  logger: Logger,
  roleId: RoleId,
  name: string,
  description: string,
): void => {
  logInfo(
    logger,
    `Successfully updated role '${roleId}' with name '${name}' and description '${description}'`,
  );
};

/**
 * Handles errors that occur during the update role process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleUpdateRoleError = (
  error: unknown,
  logger: Logger,
  roleId: RoleId,
): never => {
  logError(logger, `Failed to update role '${roleId}'. Error: ${error}`);
  throw createDatabaseError(`Failed to update role: ${error}`);
};

/**
 * Updates an existing role in the RBAC system.
 * @param supabase - The Supabase client.
 * @param roleId - The ID of the role to update.
 * @param name - The new name for the role.
 * @param description - The new description for the role.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the role was successfully updated.
 * @throws ApplicationError if the process fails.
 */
export const updateRole = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  name: string,
  description: string,
  logger: Logger,
): Promise<boolean> => {
  try {
    logUpdateRoleAttempt(logger, roleId, name, description);
    const result = await executeUpdateRoleRpc(
      supabase,
      roleId,
      name,
      description,
    );
    logUpdateRoleSuccess(logger, roleId, name, description);
    return result;
  } catch (error) {
    return handleUpdateRoleError(error, logger, roleId);
  }
};
