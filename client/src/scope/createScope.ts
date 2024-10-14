import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, ScopeId } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to create a new scope.
 * @param logger - The logger instance used for logging.
 * @param name - The name of the scope being created.
 */
const logCreateScopeAttempt = (logger: Logger, name: string): void => {
  logDebug(logger, `Attempting to create new scope with name '${name}'`);
};

/**
 * Executes the RPC call to create a new scope in the database.
 * @param supabase - The Supabase client instance.
 * @param name - The name of the scope.
 * @param description - The description of the scope.
 * @returns A promise that resolves with the ID of the newly created scope.
 * @throws Error if the RPC call fails to create the scope.
 */
const executeCreateScopeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  name: string,
  description: string,
): Promise<ScopeId> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("create_scope", {
      p_name: name,
      p_description: description,
    });

  if (error) {
    throw new Error(`Create Scope RPC failed: ${error.message}`);
  }

  return data;
};

/**
 * Logs the successful creation of a scope.
 * @param logger - The logger instance used for logging.
 * @param scopeId - The ID of the newly created scope.
 */
const logCreateScopeSuccess = (logger: Logger, scopeId: ScopeId): void => {
  logInfo(logger, `Successfully created new scope with ID: ${scopeId}`);
};

/**
 * Handles errors that occur during the create scope process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleCreateScopeError = (
  error: unknown,
  logger: Logger,
  name: string,
): never => {
  logError(
    logger,
    `Failed to create scope with name '${name}'. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to create scope: ${error}`);
};

/**
 * Creates a new scope in the system.
 * @param supabase - The Supabase client.
 * @param name - The name of the scope to create.
 * @param description - The description of the scope.
 * @param logger - The logger instance.
 * @returns The ID of the newly created scope.
 * @throws ApplicationError if the process fails.
 */
export const createScope = async (
  supabase: SupabaseClient<any, "public", any>,
  name: string,
  description: string,
  logger: Logger,
): Promise<ScopeId> => {
  try {
    logCreateScopeAttempt(logger, name);
    const scopeId = await executeCreateScopeRpc(supabase, name, description);
    logCreateScopeSuccess(logger, scopeId);
    return scopeId;
  } catch (error) {
    return handleCreateScopeError(error, logger, name);
  }
};
