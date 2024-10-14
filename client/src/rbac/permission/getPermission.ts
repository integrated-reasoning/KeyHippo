import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, PermissionId, Permission } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to retrieve a permission.
 * @param logger - The logger instance used for logging.
 * @param permissionId - The ID of the permission being retrieved.
 */
const logGetPermissionAttempt = (
  logger: Logger,
  permissionId: PermissionId,
): void => {
  logDebug(
    logger,
    `Attempting to retrieve permission with ID '${permissionId}'`,
  );
};

/**
 * Executes the RPC call to get a permission from the database.
 * @param supabase - The Supabase client instance.
 * @param permissionId - The ID of the permission being retrieved.
 * @returns A promise that resolves with the Permission object or null if not found.
 * @throws Error if the RPC call fails to retrieve the permission.
 */
const executeGetPermissionRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionId: PermissionId,
): Promise<Permission | null> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("get_permission", {
      p_permission_id: permissionId,
    });

  if (error) {
    throw new Error(`Get Permission RPC failed: ${error.message}`);
  }

  return data || null;
};

/**
 * Logs the successful retrieval of a permission.
 * @param logger - The logger instance used for logging.
 * @param permissionId - The ID of the permission that was retrieved.
 */
const logGetPermissionSuccess = (
  logger: Logger,
  permissionId: PermissionId,
): void => {
  logInfo(logger, `Successfully retrieved permission with ID: ${permissionId}`);
};

/**
 * Handles errors that occur during the get permission process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetPermissionError = (
  error: unknown,
  logger: Logger,
  permissionId: PermissionId,
): never => {
  logError(
    logger,
    `Failed to retrieve permission with ID '${permissionId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to retrieve permission: ${error}`);
};

/**
 * Retrieves an existing permission.
 * @param supabase - The Supabase client.
 * @param permissionId - The ID of the permission to retrieve.
 * @param logger - The logger instance.
 * @returns The Permission object if found, or null if not found.
 * @throws ApplicationError if the process fails.
 */
export const getPermission = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionId: PermissionId,
  logger: Logger,
): Promise<Permission | null> => {
  try {
    logGetPermissionAttempt(logger, permissionId);
    const result = await executeGetPermissionRpc(supabase, permissionId);
    if (result) {
      logGetPermissionSuccess(logger, permissionId);
    } else {
      logInfo(logger, `Permission with ID '${permissionId}' not found`);
    }
    return result;
  } catch (error) {
    return handleGetPermissionError(error, logger, permissionId);
  }
};
