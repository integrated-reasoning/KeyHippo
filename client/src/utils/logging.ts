import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../types";

/**
 * Logs an informational message.
 * @param logger - The logger instance used for logging.
 * @param message - The informational message to log.
 */
export const logInfo = (logger: Logger, message: string): void => {
  logger.info(message);
};

/**
 * Logs a debug message.
 * @param logger - The logger instance used for logging.
 * @param message - The debug message to log.
 */
export const logDebug = (logger: Logger, message: string): void => {
  logger.debug(message);
};

/**
 * Logs an error message.
 * @param logger - The logger instance used for logging.
 * @param message - The error message to log.
 */
export const logError = (logger: Logger, message: string): void => {
  logger.error(message);
};

/**
 * Logs a warning message.
 * @param logger - The logger instance used for logging.
 * @param message - The warning message to log.
 */
export const logWarn = (logger: Logger, message: string): void => {
  logger.warn(message);
};

/**
 * Logs user attributes.
 * @param supabase - The Supabase client used to interact with the database.
 * @param userId - The ID of the user whose attributes are to be logged.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves when the user attributes have been logged.
 * @throws AppError if fetching user attributes fails.
 */
export async function logUserAttributes(
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<void> {
  const { data: userAttributes, error } = await supabase
    .schema("keyhippo_abac")
    .from("user_attributes")
    .select("attributes")
    .eq("user_id", userId)
    .single();

  if (error) {
    logger.warn(`Failed to fetch user attributes: ${error.message}`);
    // Depending on the application's error handling strategy, you might want to throw an error here.
    // For example:
    // throw createDatabaseError(`Failed to fetch user attributes: ${error.message}`);
  } else {
    logger.debug(`User attributes: ${JSON.stringify(userAttributes)}`);
  }
}

/**
 * Logs all policies.
 * @param supabase - The Supabase client used to interact with the database.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves when all policies have been logged.
 * @throws AppError if fetching policies fails.
 */
export async function logAllPolicies(
  supabase: SupabaseClient<any, "public", any>,
  logger: Logger,
): Promise<void> {
  const { data: policies, error } = await supabase
    .schema("keyhippo_abac")
    .from("policies")
    .select("*");

  if (error) {
    logger.warn(`Failed to fetch policies: ${error.message}`);
    // Depending on the application's error handling strategy, you might want to throw an error here.
    // For example:
    // throw createDatabaseError(`Failed to fetch policies: ${error.message}`);
  } else {
    logger.debug(`All policies: ${JSON.stringify(policies)}`);
  }
}

/**
 * Logs the raw RPC result for debugging purposes.
 * @param logger - The logger instance used for logging.
 * @param result - The RPC result object to log.
 */
export function logRpcResult(logger: Logger, result: any): void {
  logger.debug(`Raw result from RPC: ${JSON.stringify(result)}`);
  logger.debug(
    `Result status: ${result.status}, statusText: ${result.statusText}`,
  );
  logger.debug(`Result error: ${JSON.stringify(result.error)}`);
  logger.debug(`Result data: ${JSON.stringify(result.data)}`);
}
