import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, ScopeId, PermissionId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to add a permission to a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope.
 * @param permissionId - The ID of the permission being added.
 */
const logAddPermissionToScopeAttempt = (
  logger: Logger,
  scopeId: ScopeId,
  permissionId: PermissionId,
): void => {
  logDebug(
    logger,
    `Attempting to add permission '${permissionId}' to scope '${scopeId}'`,
  );
};

/**
 * Executes the RPC call to add a permission to a scope in the database.
 * @param supabase - The Supabase client instance.
 * @param scopeId - The ID of the scope.
 * @param permissionId - The ID of the permission being added.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to add the permission to the scope.
 */
const executeAddPermissionToScopeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
  permissionId: PermissionId,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("add_permission_to_scope", {
      p_scope_id: scopeId,
      p_permission_id: permissionId,
    });

  if (error) {
    throw new Error(`Add Permission to Scope RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful addition of a permission to a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope.
 * @param permissionId - The ID of the permission that was added.
 */
const logAddPermissionToScopeSuccess = (
  logger: Logger,
  scopeId: ScopeId,
  permissionId: PermissionId,
): void => {
  logInfo(
    logger,
    `Successfully added permission '${permissionId}' to scope '${scopeId}'`,
  );
};

/**
 * Handles errors that occur during the add permission to scope process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleAddPermissionToScopeError = (
  error: unknown,
  logger: Logger,
  scopeId: ScopeId,
  permissionId: PermissionId,
): never => {
  logError(
    logger,
    `Failed to add permission '${permissionId}' to scope '${scopeId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to add permission to scope: ${error}`);
};

/**
 * Adds a permission to a scope.
 * @param supabase - The Supabase client.
 * @param scopeId - The ID of the scope.
 * @param permissionId - The ID of the permission to add.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the permission was successfully added to the scope.
 * @throws ApplicationError if the process fails.
 */
export const addPermissionToScope = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
  permissionId: PermissionId,
  logger: Logger,
): Promise<boolean> => {
  try {
    logAddPermissionToScopeAttempt(logger, scopeId, permissionId);
    const result = await executeAddPermissionToScopeRpc(
      supabase,
      scopeId,
      permissionId,
    );
    logAddPermissionToScopeSuccess(logger, scopeId, permissionId);
    return result;
  } catch (error) {
    return handleAddPermissionToScopeError(
      error,
      logger,
      scopeId,
      permissionId,
    );
  }
};
