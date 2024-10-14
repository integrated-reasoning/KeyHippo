import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, PermissionId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to delete a permission.
 * @param logger - The logger instance used for logging.
 * @param permissionId - The ID of the permission being deleted.
 */
const logDeletePermissionAttempt = (
  logger: Logger,
  permissionId: PermissionId,
): void => {
  logDebug(logger, `Attempting to delete permission with ID '${permissionId}'`);
};

/**
 * Executes the RPC call to delete a permission from the database.
 * @param supabase - The Supabase client instance.
 * @param permissionId - The ID of the permission being deleted.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to delete the permission.
 */
const executeDeletePermissionRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionId: PermissionId,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("delete_permission", {
      p_permission_id: permissionId,
    });

  if (error) {
    throw new Error(`Delete Permission RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful deletion of a permission.
 * @param logger - The logger instance used for logging.
 * @param permissionId - The ID of the permission that was deleted.
 */
const logDeletePermissionSuccess = (
  logger: Logger,
  permissionId: PermissionId,
): void => {
  logInfo(logger, `Successfully deleted permission with ID: ${permissionId}`);
};

/**
 * Handles errors that occur during the delete permission process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleDeletePermissionError = (
  error: unknown,
  logger: Logger,
  permissionId: PermissionId,
): never => {
  logError(
    logger,
    `Failed to delete permission with ID '${permissionId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to delete permission: ${error}`);
};

/**
 * Deletes an existing permission.
 * @param supabase - The Supabase client.
 * @param permissionId - The ID of the permission to delete.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the permission was successfully deleted.
 * @throws ApplicationError if the process fails.
 */
export const deletePermission = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionId: PermissionId,
  logger: Logger,
): Promise<boolean> => {
  try {
    logDeletePermissionAttempt(logger, permissionId);
    const result = await executeDeletePermissionRpc(supabase, permissionId);
    logDeletePermissionSuccess(logger, permissionId);
    return result;
  } catch (error) {
    return handleDeletePermissionError(error, logger, permissionId);
  }
};
