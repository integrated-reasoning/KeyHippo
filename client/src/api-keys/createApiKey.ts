import { SupabaseClient } from "@supabase/supabase-js";
import { v4 as uuidv4 } from "uuid";
import { CompleteApiKeyInfo, Logger } from "../types";
import { logInfo, logError, createDatabaseError } from "../utils";

/**
 * Generates a unique description by appending a UUID to the provided key description.
 * @param keyDescription - The base description for the API key.
 * @returns A unique description string combining a UUID and the provided key description.
 */
const generateUniqueDescription = (keyDescription: string): string => {
  const uniqueId = uuidv4();
  return `${uniqueId}-${keyDescription}`;
};

/**
 * Executes the RPC call to create a new API key in the database.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user for whom the API key is being created.
 * @param uniqueDescription - A unique description for the new API key.
 * @returns A promise that resolves with the created API key and its ID.
 * @throws Error if the RPC call fails to create the API key.
 */
const executeCreateApiKeyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  uniqueDescription: string,
): Promise<{ apiKey: string; apiKeyId: string }> => {
  const { data, error } = await supabase
    .schema("keyhippo")
    .rpc("create_api_key", {
      id_of_user: userId,
      key_description: uniqueDescription,
    })
    .single<{ api_key: string; api_key_id: string }>();

  if (error) {
    throw new Error(`Create API key RPC failed: ${error.message}`);
  }

  if (!data || !data.api_key || !data.api_key_id) {
    throw new Error("Invalid API key data returned");
  }

  return { apiKey: data.api_key, apiKeyId: data.api_key_id };
};

/**
 * Constructs a CompleteApiKeyInfo object from the provided details.
 * @param id - The unique identifier of the API key.
 * @param description - The description of the API key.
 * @param apiKey - The actual API key string.
 * @returns A CompleteApiKeyInfo object containing all relevant API key details.
 */
const buildCompleteApiKeyInfo = (
  id: string,
  description: string,
  apiKey: string,
): CompleteApiKeyInfo => ({
  id,
  description,
  apiKey,
  status: "success",
});

/**
 * Logs the successful creation of a new API key for a user.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user for whom the API key was created.
 * @param keyId - The unique identifier of the newly created API key.
 */
const logApiKeyCreation = (
  logger: Logger,
  userId: string,
  keyId: string,
): void => {
  logInfo(logger, `New API key created for user: ${userId}, Key ID: ${keyId}`);
};

/**
 * Handles errors that occur during the API key creation process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleCreateApiKeyError = (error: unknown, logger: Logger): never => {
  logError(logger, `Failed to create new API key: ${error}`);
  throw createDatabaseError(`Failed to create API key: ${error}`);
};

/**
 * Creates a new API key for a user.
 * @param supabase - The Supabase client.
 * @param userId - The ID of the user.
 * @param keyDescription - Description of the API key.
 * @param logger - The logger instance.
 * @returns The complete information of the created API key.
 * @throws AppError if the creation process fails.
 */
export const createApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  keyDescription: string,
  logger: Logger,
): Promise<CompleteApiKeyInfo> => {
  const uniqueDescription = generateUniqueDescription(keyDescription);

  try {
    // Call the RPC to create the API key and get the result
    const { apiKey, apiKeyId } = await executeCreateApiKeyRpc(
      supabase,
      userId,
      uniqueDescription,
    );

    // Build the complete API key information object
    const completeKeyInfo: CompleteApiKeyInfo = buildCompleteApiKeyInfo(
      apiKeyId,
      uniqueDescription,
      apiKey,
    );

    // Log the successful API key creation
    logApiKeyCreation(logger, userId, completeKeyInfo.id);

    return completeKeyInfo;
  } catch (error) {
    return handleCreateApiKeyError(error, logger);
  }
};
