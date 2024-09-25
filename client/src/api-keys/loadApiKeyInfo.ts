import { SupabaseClient } from "@supabase/supabase-js";
import { ApiKeySummary, Logger } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

// Define the shape of the data returned from the query
interface ApiKeyMetadata {
  id: string;
  description: string;
}

/**
 * Executes the query to load API key summary information for the current user.
 * @param supabase - The Supabase client instance.
 * @returns A promise that resolves with the query result containing data or an error.
 * @throws Error if the query fails.
 */
const executeLoadApiKeySummaryQuery = async (
  supabase: SupabaseClient<any, "public", any>,
): Promise<{ data: ApiKeyMetadata[] | null; error: any }> => {
  return await supabase
    .schema("keyhippo")
    .from("api_key_metadata")
    .select("id, description")
    .eq("is_revoked", false);
};

/**
 * Logs detailed information about the query result.
 * @param logger - The logger instance used for logging.
 * @param result - The result object returned from the query.
 */
const logQueryResult = (
  logger: Logger,
  result: { data: ApiKeyMetadata[] | null; error: any },
): void => {
  logDebug(logger, `Raw result from query: ${JSON.stringify(result)}`);
  logDebug(logger, `Result error: ${JSON.stringify(result.error)}`);
  logDebug(logger, `Result data: ${JSON.stringify(result.data)}`);
};

/**
 * Logs the successful loading of API key summary information.
 * @param logger - The logger instance used for logging.
 * @param count - The number of API key summary entries loaded.
 */
const logApiKeySummaryLoaded = (logger: Logger, count: number): void => {
  logInfo(logger, `API key summaries loaded. Count: ${count}`);
};

/**
 * Handles errors that occur during the loading of API key summary information.
 * @param error - The error encountered during the loading process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleLoadApiKeySummaryError = (
  error: unknown,
  logger: Logger,
): never => {
  logError(logger, `Failed to load API key summaries: ${error}`);
  throw createDatabaseError(`Failed to load API key summaries: ${error}`);
};

/**
 * Loads API key summary information for the current user.
 * @param supabase - The Supabase client used to interact with the database.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with an array of API key summary information.
 * @throws AppError if the loading process fails.
 */
export const loadApiKeySummaries = async (
  supabase: SupabaseClient<any, "public", any>,
  logger: Logger,
): Promise<ApiKeySummary[]> => {
  try {
    const { data, error } = await executeLoadApiKeySummaryQuery(supabase);
    logQueryResult(logger, { data, error });

    if (error) {
      throw error;
    }

    if (!data) {
      return [];
    }

    const apiKeySummaries: ApiKeySummary[] = data.map(
      (item: ApiKeyMetadata) => ({
        id: item.id,
        description: item.description,
      }),
    );

    logApiKeySummaryLoaded(logger, apiKeySummaries.length);
    return apiKeySummaries;
  } catch (error) {
    return handleLoadApiKeySummaryError(error, logger);
  }
};
