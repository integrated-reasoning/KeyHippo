import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, ScopeId, Permission } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to retrieve permissions for a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope.
 */
const logGetScopePermissionsAttempt = (
  logger: Logger,
  scopeId: ScopeId,
): void => {
  logDebug(logger, `Attempting to retrieve permissions for scope '${scopeId}'`);
};

/**
 * Executes the RPC call to get permissions for a scope from the database.
 * @param supabase - The Supabase client instance.
 * @param scopeId - The ID of the scope.
 * @returns A promise that resolves with an array of Permission objects.
 * @throws Error if the RPC call fails to retrieve the permissions.
 */
const executeGetScopePermissionsRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
): Promise<Permission[]> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("get_scope_permissions", {
      p_scope_id: scopeId,
    });

  if (error) {
    throw new Error(`Get Scope Permissions RPC failed: ${error.message}`);
  }

  return data || [];
};

/**
 * Logs the successful retrieval of permissions for a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope.
 * @param permissions - The array of retrieved permissions.
 */
const logGetScopePermissionsSuccess = (
  logger: Logger,
  scopeId: ScopeId,
  permissions: Permission[],
): void => {
  logInfo(
    logger,
    `Successfully retrieved ${permissions.length} permissions for scope '${scopeId}'`,
  );
};

/**
 * Handles errors that occur during the get scope permissions process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetScopePermissionsError = (
  error: unknown,
  logger: Logger,
  scopeId: ScopeId,
): never => {
  logError(
    logger,
    `Failed to retrieve permissions for scope '${scopeId}'. Error: ${error}`,
  );
  throw createDatabaseError(
    `Failed to retrieve permissions for scope: ${error}`,
  );
};

/**
 * Retrieves all permissions associated with a specific scope.
 * @param supabase - The Supabase client.
 * @param scopeId - The ID of the scope.
 * @param logger - The logger instance.
 * @returns An array of Permission objects associated with the scope.
 * @throws ApplicationError if the process fails.
 */
export const getScopePermissions = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
  logger: Logger,
): Promise<Permission[]> => {
  try {
    logGetScopePermissionsAttempt(logger, scopeId);
    const permissions = await executeGetScopePermissionsRpc(supabase, scopeId);
    logGetScopePermissionsSuccess(logger, scopeId, permissions);
    return permissions;
  } catch (error) {
    return handleGetScopePermissionsError(error, logger, scopeId);
  }
};
