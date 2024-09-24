import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../types";
import { logDebug, logInfo } from "../utils/logging";
import { handleError } from "../utils";

/**
 * Logs an attempt to retrieve a specific user attribute.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose attribute is being retrieved.
 * @param attribute - The name of the attribute being retrieved.
 */
const logGetUserAttributeAttempt = (
  logger: Logger,
  userId: string,
  attribute: string,
): void => {
  logDebug(logger, `Retrieving user attribute ${attribute} for user ${userId}`);
};

/**
 * Executes the RPC call to retrieve a user attribute from the database.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user whose attribute is being retrieved.
 * @param attribute - The name of the attribute to retrieve.
 * @returns An object containing the retrieved data or an error if the operation fails.
 * @throws Error if the RPC call fails to retrieve the user attribute.
 */
const executeGetUserAttributeRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  attribute: string,
): Promise<{ data: any; error: any }> => {
  const { data, error } = await supabase
    .schema("keyhippo_abac")
    .rpc("get_user_attribute", {
      p_user_id: userId,
      p_attribute: attribute,
    });

  if (error) {
    throw new Error(`Failed to retrieve user attribute: ${error.message}`);
  }

  return { data, error };
};

/**
 * Logs the successful retrieval of a user attribute.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose attribute was retrieved.
 * @param attribute - The name of the attribute that was retrieved.
 * @param data - The data of the retrieved attribute.
 */
const logGetUserAttributeSuccess = (
  logger: Logger,
  userId: string,
  attribute: string,
  data: any,
): void => {
  logInfo(
    logger,
    `User ${userId} attribute ${attribute}: ${JSON.stringify(data)}`,
  );
};

/**
 * Retrieves a specific attribute for a user from the database.
 * @param supabase - The Supabase client instance used to interact with the database.
 * @param userId - The ID of the user whose attribute is to be retrieved.
 * @param attribute - The name of the attribute to retrieve.
 * @param logger - The logger instance used for logging events and errors.
 * @returns The value of the requested user attribute.
 * @throws AppError if the retrieval process fails.
 */
export const getUserAttribute = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  attribute: string,
  logger: Logger,
): Promise<any> => {
  try {
    logGetUserAttributeAttempt(logger, userId, attribute);
    const result = await executeGetUserAttributeRpc(
      supabase,
      userId,
      attribute,
    );

    if (result.error) {
      throw new Error(
        `Failed to retrieve user attribute: ${result.error.message}`,
      );
    }

    logGetUserAttributeSuccess(logger, userId, attribute, result.data);
    return result.data;
  } catch (error) {
    return handleError(error, logger, "Failed to retrieve user attribute");
  }
};
