import { SupabaseClient } from "@supabase/supabase-js";
import {
  ApiKeyEntity,
  RotateApiKeyResult,
  Logger,
  ApiKeyId,
  UserId,
  Timestamp,
} from "../types";
import {
  logInfo,
  logError,
  createDatabaseError,
  validateRpcResult,
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
  apiKeyId: ApiKeyId,
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
const logApiKeyRotation = (logger: Logger, newKeyId: ApiKeyId): void => {
  logInfo(logger, `API key rotated successfully. New Key ID: ${newKeyId}`);
};

/**
 * Rotates an existing API key.
 * @param supabase - The Supabase client used to interact with the database.
 * @param apiKeyId - The ID of the API key to rotate.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with the information of the rotated API key.
 * @throws Error if the rotation process fails.
 */
export const rotateApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  apiKeyId: ApiKeyId,
  logger: Logger,
): Promise<RotateApiKeyResult> => {
  try {
    const result = await executeRotateApiKeyRpc(supabase, apiKeyId);
    validateRpcResult(result, "rotate_api_key");

    if (
      !result.data ||
      !Array.isArray(result.data) ||
      result.data.length === 0
    ) {
      throw new Error("Invalid response from API key rotation");
    }

    const rotatedKeyData = result.data[0];

    if (!rotatedKeyData.new_api_key || !rotatedKeyData.new_api_key_id) {
      throw new Error("Invalid response structure from API key rotation");
    }

    const rotatedKeyInfo: RotateApiKeyResult = {
      apiKey: rotatedKeyData.new_api_key,
      id: rotatedKeyData.new_api_key_id,
      status: "success",
    };

    logApiKeyRotation(logger, rotatedKeyInfo.id);
    return rotatedKeyInfo;
  } catch (error) {
    logError(logger, `Failed to rotate API key: ${error}`);
    throw new Error(`Failed to rotate API key: ${error}`);
  }
};
