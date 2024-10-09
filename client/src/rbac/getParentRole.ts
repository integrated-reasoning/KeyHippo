import { SupabaseClient } from "@supabase/supabase-js";
import {
  Logger,
  RoleId,
  ParentRoleId,
} from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to get a parent role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role whose parent is being retrieved.
 */
const logGetParentRoleAttempt = (logger: Logger, roleId: RoleId): void => {
  logDebug(logger, `Attempting to get parent role for Role ID: ${roleId}`);
};

/**
 * Executes the RPC call to get the parent role from the database.
 * @param supabase - The Supabase client instance.
 * @param roleId - The ID of the role whose parent is being retrieved.
 * @returns A promise that resolves with the parent_role_id or null if none exists.
 * @throws Error if the RPC call fails to retrieve the parent role.
 */
const executeGetParentRoleRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
): Promise<{ parent_role_id: ParentRoleId }> => {
  const { data, error } = await supabase
    .from("keyhippo_rbac.roles")
    .select("parent_role_id")
    .eq("id", roleId)
    .single<{ parent_role_id: ParentRoleId }>();

  if (error) {
    throw new Error(`Get Parent Role RPC failed: ${error.message}`);
  }

  if (!data) {
    throw new Error("Role not found");
  }

  return { parent_role_id: data.parent_role_id };
};

/**
 * Logs the successful retrieval of a parent role.
 * @param logger - The logger instance used for logging.
 * @param roleId - The ID of the role.
 * @param parentRoleId - The ID of the parent role or null if none exists.
 */
const logGetParentRoleSuccess = (
  logger: Logger,
  roleId: RoleId,
  parentRoleId: ParentRoleId,
): void => {
  if (parentRoleId) {
    logInfo(
      logger,
      `Successfully retrieved parent role for Role ID: ${roleId}. Parent Role ID: ${parentRoleId}`,
    );
  } else {
    logInfo(
      logger,
      `No parent role found for Role ID: ${roleId}`,
    );
  }
};

/**
 * Handles errors that occur during the get parent role process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetParentRoleError = (
  error: unknown,
  logger: Logger,
  roleId: RoleId,
): never => {
  logError(
    logger,
    `Failed to get parent role for Role ID: ${roleId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to get parent role: ${error}`);
};

/**
 * Retrieves the parent role of a specified role.
 * @param supabase - The Supabase client.
 * @param roleId - The ID of the role whose parent is being retrieved.
 * @param logger - The logger instance.
 * @returns The parent_role_id or null if none exists.
 * @throws ApplicationError if the process fails.
 */
export const getParentRole = async (
  supabase: SupabaseClient<any, "public", any>,
  roleId: RoleId,
  logger: Logger,
): Promise<ParentRoleId> => {
  try {
    logGetParentRoleAttempt(logger, roleId);
    const result = await executeGetParentRoleRpc(supabase, roleId);
    logGetParentRoleSuccess(logger, roleId, result.parent_role_id);
    return result.parent_role_id;
  } catch (error) {
    return handleGetParentRoleError(error, logger, roleId);
  }
};
