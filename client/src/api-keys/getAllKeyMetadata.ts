import { SupabaseClient } from "@supabase/supabase-js";
import { ApiKeyMetadata, Logger } from "../types";
import {
  logDebug,
  logInfo,
  logError,
  logWarn,
  logRpcResult,
  createDatabaseError,
  validateRpcResult,
  parseApiKeyMetadata,
} from "../utils";

/**
 * Executes the RPC call to retrieve all API key metadata for a user.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user whose API key metadata is being retrieved.
 * @returns A promise that resolves with the RPC result containing data or an error.
 * @throws Error if the RPC call fails.
 */
const executeGetApiKeyMetadataRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
): Promise<any> => {
  return await supabase
    .schema("keyhippo")
    .rpc("get_api_key_metadata", { id_of_user: userId });
};

/**
 * Logs the successful retrieval of API key metadata.
 * @param logger - The logger instance used for logging.
 * @param count - The number of API key metadata entries retrieved.
 */
const logApiKeyMetadataRetrieved = (logger: Logger, count: number): void => {
  logInfo(logger, `API key metadata retrieved. Count: ${count}`);
};

/**
 * Handles errors that occur during the retrieval of all API key metadata.
 * @param error - The error encountered during the retrieval process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleGetAllKeyMetadataError = (
  error: unknown,
  logger: Logger,
): never => {
  logError(logger, `Failed to get API key metadata: ${error}`);
  throw createDatabaseError(`Failed to get API key metadata: ${error}`);
};

/**
 * Retrieves all API key metadata for a user.
 * @param supabase - The Supabase client used to interact with the database.
 * @param userId - The ID of the user whose API key metadata is to be retrieved.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with an array of API key metadata.
 * @throws AppError if the retrieval process fails.
 */
export const getAllKeyMetadata = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<ApiKeyMetadata[]> => {
  try {
    logDebug(logger, `Calling get_api_key_metadata RPC for user: ${userId}`);
    const result = await executeGetApiKeyMetadataRpc(supabase, userId);

    logRpcResult(logger, result);
    validateRpcResult(result, "get_api_key_metadata");

    const metadata = parseApiKeyMetadata(result.data);
    logApiKeyMetadataRetrieved(logger, metadata.length);

    return metadata;
  } catch (error) {
    return handleGetAllKeyMetadataError(error, logger);
  }
};
