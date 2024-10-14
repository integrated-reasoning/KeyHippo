import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, PermissionId, PermissionName, Description } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to update a permission.
 * @param logger - The logger instance used for logging.
 * @param permissionId - The ID of the permission being updated.
 */
const logUpdatePermissionAttempt = (
  logger: Logger,
  permissionId: PermissionId,
): void => {
  logDebug(logger, `Attempting to update permission with ID '${permissionId}'`);
};

/**
 * Executes the RPC call to update a permission in the database.
 * @param supabase - The Supabase client instance.
 * @param permissionId - The ID of the permission being updated.
 * @param name - The new name for the permission.
 * @param description - The new description for the permission.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to update the permission.
 */
const executeUpdatePermissionRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionId: PermissionId,
  name: PermissionName,
  description: Description,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("update_permission", {
      p_permission_id: permissionId,
      p_name: name,
      p_description: description,
    });

  if (error) {
    throw new Error(`Update Permission RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful update of a permission.
 * @param logger - The logger instance used for logging.
 * @param permissionId - The ID of the permission that was updated.
 */
const logUpdatePermissionSuccess = (
  logger: Logger,
  permissionId: PermissionId,
): void => {
  logInfo(logger, `Successfully updated permission with ID: ${permissionId}`);
};

/**
 * Handles errors that occur during the update permission process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleUpdatePermissionError = (
  error: unknown,
  logger: Logger,
  permissionId: PermissionId,
): never => {
  logError(
    logger,
    `Failed to update permission with ID '${permissionId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to update permission: ${error}`);
};

/**
 * Updates an existing permission.
 * @param supabase - The Supabase client.
 * @param permissionId - The ID of the permission to update.
 * @param name - The new name for the permission.
 * @param description - The new description for the permission.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the permission was successfully updated.
 * @throws ApplicationError if the process fails.
 */
export const updatePermission = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionId: PermissionId,
  name: PermissionName,
  description: Description,
  logger: Logger,
): Promise<boolean> => {
  try {
    logUpdatePermissionAttempt(logger, permissionId);
    const result = await executeUpdatePermissionRpc(
      supabase,
      permissionId,
      name,
      description,
    );
    logUpdatePermissionSuccess(logger, permissionId);
    return result;
  } catch (error) {
    return handleUpdatePermissionError(error, logger, permissionId);
  }
};
