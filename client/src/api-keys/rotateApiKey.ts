import { SupabaseClient } from "@supabase/supabase-js";
import { RotateApiKeyResult, Logger } from "../types";
import {
  logInfo,
  logError,
  createDatabaseError,
  validateRpcResult
} from "../utils";

/**
 * Executes the RPC call to rotate an existing API key.
 * @param supabase - The Supabase client instance.
 * @param apiKeyId - The ID of the API key to rotate.
 * @returns A promise that resolves with the RPC result containing data or an error.
 * @throws Error if the RPC call fails to rotate the API key.
 */
const executeRotateApiKeyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  apiKeyId: string,
): Promise<any> => {
  return await supabase.schema("keyhippo").rpc("rotate_api_key", {
    old_api_key_id: apiKeyId,
  });
};

/**
 * Logs the successful rotation of an API key.
 * @param logger - The logger instance used for logging.
 * @param newKeyId - The ID of the newly rotated API key.
 */
const logApiKeyRotation = (
  logger: Logger,
  newKeyId: string,
): void => {
  logInfo(
    logger,
    `API key rotated successfully. New Key ID: ${newKeyId}`,
  );
};

/**
 * Handles errors that occur during the API key rotation process.
 * @param error - The error encountered during the rotation process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleRotateApiKeyError = (error: unknown, logger: Logger): never => {
  logError(logger, `Failed to rotate API key: ${error}`);
  throw createDatabaseError(`Failed to rotate API key: ${error}`);
};

/**
 * Rotates an existing API key.
 * @param supabase - The Supabase client used to interact with the database.
 * @param apiKeyId - The ID of the API key to rotate.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with the information of the rotated API key.
 * @throws AppError if the rotation process fails.
 */
export const rotateApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  apiKeyId: string,
  logger: Logger,
): Promise<RotateApiKeyResult> => {
  try {
    const result = await executeRotateApiKeyRpc(supabase, apiKeyId);
    validateRpcResult(result, "rotate_api_key");

    const rotatedKeyInfo: RotateApiKeyResult = {
      apiKey: result.data.new_api_key,
      id: result.data.new_api_key_id,
      status: "success"
    };

    logApiKeyRotation(logger, rotatedKeyInfo.id);
    return rotatedKeyInfo;
  } catch (error) {
    return handleRotateApiKeyError(error, logger);
  }
};
