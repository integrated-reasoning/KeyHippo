import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Executes the RPC call to check if a user has a specific permission.
 * @param supabase - The Supabase client instance.
 * @param permissionName - The name of the permission to check.
 * @returns A promise that resolves with a boolean indicating whether the user has the permission.
 * @throws Error if the RPC call fails to check the user's permission.
 */
const executeUserHasPermissionRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionName: string,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("user_has_permission", { permission_name: permissionName })
    .single<boolean>();

  if (error) {
    throw new Error(`Failed to check user permission: ${error.message}`);
  }

  return !!data;
};

/**
 * Logs the attempt to check a user's permission.
 * @param logger - The logger instance used for logging.
 * @param permissionName - The name of the permission being checked.
 */
const logUserHasPermissionAttempt = (
  logger: Logger,
  permissionName: string,
): void => {
  logDebug(logger, `Checking if user has permission: ${permissionName}`);
};

/**
 * Logs the result of the permission check.
 * @param logger - The logger instance used for logging.
 * @param permissionName - The name of the permission that was checked.
 * @param hasPermission - Whether the user has the permission.
 */
const logUserHasPermissionResult = (
  logger: Logger,
  permissionName: string,
  hasPermission: boolean,
): void => {
  logInfo(
    logger,
    `User ${hasPermission ? "has" : "does not have"} permission: ${permissionName}`,
  );
};

/**
 * Handles errors that occur during the process of checking a user's permission.
 * @param error - The error encountered during the check process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleUserHasPermissionError = (
  error: unknown,
  logger: Logger,
): never => {
  logError(logger, `Failed to check user permission: ${error}`);
  throw createDatabaseError(`Failed to check user permission: ${error}`);
};

/**
 * Checks if the current user has a specific permission.
 * @param supabase - The Supabase client used to interact with the database.
 * @param permissionName - The name of the permission to check.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with a boolean indicating whether the user has the permission.
 * @throws AppError if the check process fails.
 */
export const userHasPermission = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionName: string,
  logger: Logger,
): Promise<boolean> => {
  try {
    logUserHasPermissionAttempt(logger, permissionName);
    const hasPermission = await executeUserHasPermissionRpc(
      supabase,
      permissionName,
    );
    logUserHasPermissionResult(logger, permissionName, hasPermission);
    return hasPermission;
  } catch (error) {
    return handleUserHasPermissionError(error, logger);
  }
};
