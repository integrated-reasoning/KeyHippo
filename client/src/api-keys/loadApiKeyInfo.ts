import { SupabaseClient } from "@supabase/supabase-js";
import { ApiKeyInfo, Logger } from "../types";
import {
  logDebug,
  logWarn,
  logInfo,
  logError,
  createDatabaseError,
  parseApiKeyInfo,
  validateRpcResult
} from "../utils";

/**
 * Executes the RPC call to load API key information for a user.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user whose API key information is being loaded.
 * @returns A promise that resolves with the RPC result containing data or an error.
 * @throws Error if the RPC call fails.
 */
const executeLoadApiKeyInfoRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
): Promise<any> => {
  return await supabase
    .schema("keyhippo")
    .rpc("load_api_key_info", { id_of_user: userId });
};

/**
 * Logs detailed information about the RPC call result.
 * @param logger - The logger instance used for logging.
 * @param result - The result object returned from the RPC call.
 */
const logRpcResult = (logger: Logger, result: any): void => {
  logDebug(logger, `Raw result from RPC: ${JSON.stringify(result)}`);
  logDebug(
    logger,
    `Result status: ${result.status}, statusText: ${result.statusText}`,
  );
  logDebug(logger, `Result error: ${JSON.stringify(result.error)}`);
  logDebug(logger, `Result data: ${JSON.stringify(result.data)}`);
};

/**
 * Logs the successful loading of API key information.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose API key information was loaded.
 * @param count - The number of API key information entries loaded.
 */
const logApiKeyInfoLoaded = (
  logger: Logger,
  userId: string,
  count: number,
): void => {
  logInfo(logger, `API key info loaded for user: ${userId}. Count: ${count}`);
};

/**
 * Handles errors that occur during the loading of API key information.
 * @param error - The error encountered during the loading process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleLoadApiKeyInfoError = (error: unknown, logger: Logger): never => {
  logError(logger, `Failed to load API key info: ${error}`);
  throw createDatabaseError(`Failed to load API key info: ${error}`);
};

/**
 * Loads API key information for a user.
 * @param supabase - The Supabase client used to interact with the database.
 * @param userId - The ID of the user whose API key information is to be loaded.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with an array of API key information.
 * @throws AppError if the loading process fails.
 */
export const loadApiKeyInfo = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<ApiKeyInfo[]> => {
  try {
    const result = await executeLoadApiKeyInfoRpc(supabase, userId);
    logRpcResult(logger, result);
    validateRpcResult(result, "load_api_key_info");

    const apiKeyInfo = parseApiKeyInfo(result.data);
    logApiKeyInfoLoaded(logger, userId, apiKeyInfo.length);

    return apiKeyInfo;
  } catch (error) {
    return handleLoadApiKeyInfoError(error, logger);
  }
};
