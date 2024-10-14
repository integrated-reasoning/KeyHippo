import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, ScopeId, Scope } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to retrieve a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope being retrieved.
 */
const logGetScopeAttempt = (logger: Logger, scopeId: ScopeId): void => {
  logDebug(logger, `Attempting to retrieve scope with ID '${scopeId}'`);
};

/**
 * Executes the RPC call to get a scope from the database.
 * @param supabase - The Supabase client instance.
 * @param scopeId - The ID of the scope being retrieved.
 * @returns A promise that resolves with the Scope object or null if not found.
 * @throws Error if the RPC call fails to retrieve the scope.
 */
const executeGetScopeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
): Promise<Scope | null> => {
  const { data, error } = await supabase.schema("keyhippo").rpc("get_scope", {
    p_scope_id: scopeId,
  });

  if (error) {
    throw new Error(`Get Scope RPC failed: ${error.message}`);
  }

  return data || null;
};

/**
 * Logs the successful retrieval of a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the scope that was retrieved.
 */
const logGetScopeSuccess = (logger: Logger, scopeId: ScopeId): void => {
  logInfo(logger, `Successfully retrieved scope with ID: ${scopeId}`);
};

/**
 * Handles errors that occur during the get scope process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetScopeError = (
  error: unknown,
  logger: Logger,
  scopeId: ScopeId,
): never => {
  logError(
    logger,
    `Failed to retrieve scope with ID '${scopeId}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to retrieve scope: ${error}`);
};

/**
 * Retrieves an existing scope.
 * @param supabase - The Supabase client.
 * @param scopeId - The ID of the scope to retrieve.
 * @param logger - The logger instance.
 * @returns The Scope object if found, or null if not found.
 * @throws ApplicationError if the process fails.
 */
export const getScope = async (
  supabase: SupabaseClient<any, "public", any>,
  scopeId: ScopeId,
  logger: Logger,
): Promise<Scope | null> => {
  try {
    logGetScopeAttempt(logger, scopeId);
    const result = await executeGetScopeRpc(supabase, scopeId);
    if (result) {
      logGetScopeSuccess(logger, scopeId);
    } else {
      logInfo(logger, `Scope with ID '${scopeId}' not found`);
    }
    return result;
  } catch (error) {
    return handleGetScopeError(error, logger, scopeId);
  }
};
