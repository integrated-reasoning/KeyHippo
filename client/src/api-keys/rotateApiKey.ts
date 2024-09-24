import { SupabaseClient } from "@supabase/supabase-js";
import { CompleteApiKeyInfo, RotateApiKeyResult, Logger } from "../types";
import {
  logInfo,
  logError,
  createDatabaseError,
  parseRotatedApiKeyInfo,
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
    p_api_key_id: apiKeyId,
  });
};

/**
 * Logs the successful rotation of an API key for a user.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose API key was rotated.
 * @param newKeyId - The ID of the newly rotated API key.
 */
const logApiKeyRotation = (
  logger: Logger,
  userId: string,
  newKeyId: string,
): void => {
  logInfo(
    logger,
    `API key rotated for user: ${userId}, New Key ID: ${newKeyId}`,
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
 * Rotates an existing API key for a user.
 * @param supabase - The Supabase client used to interact with the database.
 * @param userId - The ID of the user whose API key is to be rotated.
 * @param apiKeyId - The ID of the API key to rotate.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with the complete information of the rotated API key.
 * @throws AppError if the rotation process fails.
 */
export const rotateApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  apiKeyId: string,
  logger: Logger,
): Promise<CompleteApiKeyInfo> => {
  try {
    const result = await executeRotateApiKeyRpc(supabase, apiKeyId);
    validateRpcResult(result, "rotate_api_key");

    const rotatedKeyInfo = parseRotatedApiKeyInfo(result.data);
    logApiKeyRotation(logger, userId, rotatedKeyInfo.id);

    return rotatedKeyInfo;
  } catch (error) {
    return handleRotateApiKeyError(error, logger);
  }
};
