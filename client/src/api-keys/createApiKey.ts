import { SupabaseClient } from "@supabase/supabase-js";
import {
  ApiKeyEntity,
  Logger,
  ApplicationError,
  ApiKeyText,
  ApiKeyId,
  UserId,
  Description,
  Timestamp,
} from "../types";
import { createDatabaseError } from "../utils";

/**
 * Interface for the result of the create API key RPC call.
 */
interface ApiKeyRpcResult {
  api_key: ApiKeyText;
  api_key_id: ApiKeyId;
}

/**
 * Executes the RPC call to create a new API key in the database.
 * @param supabase - The Supabase client instance.
 * @param keyDescription - A description for the new API key.
 * @returns A promise that resolves with the created API key and its ID.
 * @throws Error if the RPC call fails to create the API key.
 */
const executeCreateApiKeyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  keyDescription: Description,
): Promise<{ apiKey: ApiKeyText; apiKeyId: ApiKeyId }> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("create_api_key", { key_description: keyDescription })
    .single<ApiKeyRpcResult>();

  if (error) {
    throw new Error(`Create API key RPC failed: ${error.message}`);
  }

  if (!data || !data.api_key || !data.api_key_id) {
    throw new Error("Invalid API key data returned");
  }

  return { apiKey: data.api_key, apiKeyId: data.api_key_id };
};

/**
 * Fetches the full API key metadata from the database.
 * @param supabase - The Supabase client instance.
 * @param apiKeyId - The unique identifier of the API key.
 * @returns A promise that resolves with the full API key metadata.
 * @throws Error if the query fails to retrieve the API key metadata.
 */
const fetchApiKeyMetadata = async (
  supabase: SupabaseClient<any, "public", any>,
  apiKeyId: ApiKeyId,
): Promise<Omit<ApiKeyEntity, "apiKey">> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .from("api_key_metadata")
    .select("*")
    .eq("id", apiKeyId)
    .single<Omit<ApiKeyEntity, "apiKey">>();

  if (error) {
    throw new Error(`Failed to fetch API key metadata: ${error.message}`);
  }

  if (!data) {
    throw new Error("API key metadata not found");
  }

  return data;
};

/**
 * Logs the successful creation of a new API key.
 * @param logger - The logger instance used for logging.
 * @param keyId - The unique identifier of the newly created API key.
 */
const logApiKeyCreation = (
  logger: Logger,
  keyId: ApiKeyId,
): void => {
  logger.info(`New API key created with Key ID: ${keyId}`);
};

/**
 * Handles errors that occur during the API key creation process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleCreateApiKeyError = (error: unknown, logger: Logger): never => {
  logger.error(`Failed to create new API key: ${error}`);
  throw createDatabaseError(`Failed to create API key: ${error}`);
};

/**
 * Creates a new API key for a user.
 * @param supabase - The Supabase client.
 * @param keyDescription - Description of the API key.
 * @param logger - The logger instance.
 * @returns The comprehensive information of the created API key.
 * @throws ApplicationError if the creation process fails.
 */
export const createApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  keyDescription: Description,
  logger: Logger,
): Promise<ApiKeyEntity> => {
  try {
    const { apiKey, apiKeyId } = await executeCreateApiKeyRpc(
      supabase,
      keyDescription,
    );
    const apiKeyMetadata = await fetchApiKeyMetadata(supabase, apiKeyId);

    const apiKeyEntity: ApiKeyEntity = {
      ...apiKeyMetadata,
      apiKey,
    };

    logApiKeyCreation(logger, apiKeyEntity.id);
    return apiKeyEntity;
  } catch (error) {
    return handleCreateApiKeyError(error, logger);
  }
};
