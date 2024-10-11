import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, UserId, Policy } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to check an ABAC policy.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user being checked against the policy.
 */
const logCheckAbacPolicyAttempt = (logger: Logger, userId: UserId): void => {
  logDebug(
    logger,
    `Attempting to check ABAC policy for user with ID: ${userId}`,
  );
};

/**
 * Executes the RPC call to check an ABAC policy in the database.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user being checked against the policy.
 * @param policy - The policy to check.
 * @returns A promise that resolves with a boolean indicating whether the policy check passed.
 * @throws Error if the RPC call fails to check the policy.
 */
const executeCheckAbacPolicyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: UserId,
  policy: Policy,
): Promise<boolean> => {
  const { data, error } = await supabase
    .schema("keyhippo_abac")
    .rpc("check_abac_policy", {
      p_user_id: userId,
      p_policy: policy,
    })
    .single<boolean>();

  if (error) {
    throw new Error(`Check ABAC Policy RPC failed: ${error.message}`);
  }

  return !!data;
};

/**
 * Logs the result of checking an ABAC policy.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user checked against the policy.
 * @param result - The result of the policy check.
 */
const logCheckAbacPolicyResult = (
  logger: Logger,
  userId: UserId,
  result: boolean,
): void => {
  logInfo(
    logger,
    `ABAC policy check for user ${userId} resulted in: ${result ? "PASS" : "FAIL"}`,
  );
};

/**
 * Handles errors that occur during the check ABAC policy process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @param userId - The ID of the user involved in the failed operation.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleCheckAbacPolicyError = (
  error: unknown,
  logger: Logger,
  userId: UserId,
): never => {
  logError(
    logger,
    `Failed to check ABAC policy for user with ID: ${userId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to check ABAC policy: ${error}`);
};

/**
 * Checks an ABAC policy for a specific user.
 * @param supabase - The Supabase client.
 * @param userId - The ID of the user to check against the policy.
 * @param policy - The policy to check.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the policy check passed.
 * @throws ApplicationError if the process fails.
 */
export const checkAbacPolicy = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: UserId,
  policy: Policy,
  logger: Logger,
): Promise<boolean> => {
  try {
    logCheckAbacPolicyAttempt(logger, userId);
    const result = await executeCheckAbacPolicyRpc(supabase, userId, policy);
    logCheckAbacPolicyResult(logger, userId, result);
    return result;
  } catch (error) {
    return handleCheckAbacPolicyError(error, logger, userId);
  }
};
