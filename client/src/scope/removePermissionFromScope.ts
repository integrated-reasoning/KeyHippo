import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, ScopeId, PermissionId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to remove a permission from a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope.
 * @param permissionId - The ID of the permission being removed.
 */
const logRemovePermissionFromScopeAttempt = (
  logger: Logger,
  scopeId: ScopeId,
  permissionId: PermissionId,
): void => {
  logDebug(
    logger,
    `Attempting to remove permission '${permissionId}' from scope '${scopeId}'`,
  );
};

/**
 * Executes the RPC call to remove a permission from a scope in the database.
 * @param supabase - The Supabase client instance.
 * @param scopeId - The ID of the scope.
 * @param permissionId - The ID of the permission being removed.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to remove the permission from the scope.
 */
const executeRemovePermissionFromScopeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
  permissionId: PermissionId,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("remove_permission_from_scope", {
      p_scope_id: scopeId,
      p_permission_id: permissionId,
    });

  if (error) {
    throw new Error(
      `Remove Permission from Scope RPC failed: ${error.message}`,
    );
  }

  return data || false;
};

/**
 * Logs the successful removal of a permission from a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope.
 * @param permissionId - The ID of the permission that was removed.
 */
const logRemovePermissionFromScopeSuccess = (
  logger: Logger,
  scopeId: ScopeId,
  permissionId: PermissionId,
): void => {
  logInfo(
    logger,
    `Successfully removed permission '${permissionId}' from scope '${scopeId}'`,
  );
};

/**
 * Handles errors that occur during the remove permission from scope process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleRemovePermissionFromScopeError = (
  error: unknown,
  logger: Logger,
  scopeId: ScopeId,
  permissionId: PermissionId,
): never => {
  logError(
    logger,
    `Failed to remove permission '${permissionId}' from scope '${scopeId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to remove permission from scope: ${error}`);
};

/**
 * Removes a permission from a scope.
 * @param supabase - The Supabase client.
 * @param scopeId - The ID of the scope.
 * @param permissionId - The ID of the permission to remove.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the permission was successfully removed from the scope.
 * @throws ApplicationError if the process fails.
 */
export const removePermissionFromScope = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
  permissionId: PermissionId,
  logger: Logger,
): Promise<boolean> => {
  try {
    logRemovePermissionFromScopeAttempt(logger, scopeId, permissionId);
    const result = await executeRemovePermissionFromScopeRpc(
      supabase,
      scopeId,
      permissionId,
    );
    logRemovePermissionFromScopeSuccess(logger, scopeId, permissionId);
    return result;
  } catch (error) {
    return handleRemovePermissionFromScopeError(
      error,
      logger,
      scopeId,
      permissionId,
    );
  }
};
