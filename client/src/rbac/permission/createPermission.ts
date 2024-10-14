import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, PermissionId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to create a new permission.
 * @param logger - The logger instance used for logging.
 * @param permissionName - The name of the permission being created.
 */
const logCreatePermissionAttempt = (
  logger: Logger,
  permissionName: string,
): void => {
  logDebug(
    logger,
    `Attempting to create permission '${permissionName}'`,
  );
};

/**
 * Executes the RPC call to create a new permission in the database.
 * @param supabase - The Supabase client instance.
 * @param permissionName - The name of the permission being created.
 * @param description - A description of the permission.
 * @returns A promise that resolves with the new permission's ID.
 * @throws Error if the RPC call fails to create the permission.
 */
const executeCreatePermissionRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionName: string,
  description: string,
): Promise<{ permission_id: PermissionId }> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("create_permission", {
      p_name: permissionName,
      p_description: description,
    })
    .single<{ permission_id: PermissionId }>();

  if (error) {
    throw new Error(`Create Permission RPC failed: ${error.message}`);
  }

  if (!data || !data.permission_id) {
    throw new Error("Invalid data returned from create_permission RPC");
  }

  return { permission_id: data.permission_id };
};

/**
 * Logs the successful creation of a new permission.
 * @param logger - The logger instance used for logging.
 * @param permissionName - The name of the permission that was created.
 * @param permissionId - The ID of the newly created permission.
 */
const logCreatePermissionSuccess = (
  logger: Logger,
  permissionName: string,
  permissionId: PermissionId,
): void => {
  logInfo(
    logger,
    `Successfully created permission '${permissionName}' with Permission ID: ${permissionId}`,
  );
};

/**
 * Handles errors that occur during the create permission process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleCreatePermissionError = (
  error: unknown,
  logger: Logger,
  permissionName: string,
): never => {
  logError(
    logger,
    `Failed to create permission '${permissionName}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to create permission: ${error}`);
};

/**
 * Creates a new permission.
 * @param supabase - The Supabase client.
 * @param permissionName - The name of the permission to create.
 * @param description - A description of the permission.
 * @param logger - The logger instance.
 * @returns The ID of the newly created permission.
 * @throws ApplicationError if the process fails.
 */
export const createPermission = async (
  supabase: SupabaseClient<any, "public", any>,
  permissionName: string,
  description: string = "",
  logger: Logger,
): Promise<PermissionId> => {
  try {
    logCreatePermissionAttempt(logger, permissionName);
    const result = await executeCreatePermissionRpc(
      supabase,
      permissionName,
      description,
    );
    logCreatePermissionSuccess(logger, permissionName, result.permission_id);
    return result.permission_id;
  } catch (error) {
    return handleCreatePermissionError(error, logger, permissionName);
  }
};
