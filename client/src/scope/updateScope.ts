import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, ScopeId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to update a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope being updated.
 */
const logUpdateScopeAttempt = (logger: Logger, scopeId: ScopeId): void => {
  logDebug(logger, `Attempting to update scope with ID '${scopeId}'`);
};

/**
 * Executes the RPC call to update a scope in the database.
 * @param supabase - The Supabase client instance.
 * @param scopeId - The ID of the scope being updated.
 * @param name - The new name for the scope.
 * @param description - The new description for the scope.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to update the scope.
 */
const executeUpdateScopeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
  name: string,
  description: string,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("update_scope", {
      p_scope_id: scopeId,
      p_name: name,
      p_description: description,
    });

  if (error) {
    throw new Error(`Update Scope RPC failed: ${error.message}`);
  }

  return data || false;
};

/**
 * Logs the successful update of a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope that was updated.
 */
const logUpdateScopeSuccess = (logger: Logger, scopeId: ScopeId): void => {
  logInfo(logger, `Successfully updated scope with ID: ${scopeId}`);
};

/**
 * Handles errors that occur during the update scope process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleUpdateScopeError = (
  error: unknown,
  logger: Logger,
  scopeId: ScopeId,
): never => {
  logError(
    logger,
    `Failed to update scope with ID '${scopeId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to update scope: ${error}`);
};

/**
 * Updates an existing scope.
 * @param supabase - The Supabase client.
 * @param scopeId - The ID of the scope to update.
 * @param name - The new name for the scope.
 * @param description - The new description for the scope.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the scope was successfully updated.
 * @throws ApplicationError if the process fails.
 */
export const updateScope = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
  name: string,
  description: string,
  logger: Logger,
): Promise<boolean> => {
  try {
    logUpdateScopeAttempt(logger, scopeId);
    const result = await executeUpdateScopeRpc(
      supabase,
      scopeId,
      name,
      description,
    );
    logUpdateScopeSuccess(logger, scopeId);
    return result;
  } catch (error) {
    return handleUpdateScopeError(error, logger, scopeId);
  }
};
