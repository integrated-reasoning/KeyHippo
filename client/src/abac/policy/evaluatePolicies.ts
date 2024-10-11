import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../types";
import {
  logDebug,
  logInfo,
  logError,
  logWarn,
  createDatabaseError,
  validateRpcResult,
  parseEvaluationResult,
} from "../utils";
import { logUserAttributes, logAllPolicies } from "../utils";

/**
 * Logs the attempt to evaluate policies for a user.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose policies are being evaluated.
 */
const logEvaluatePoliciesAttempt = (logger: Logger, userId: string): void => {
  logDebug(logger, `Evaluating policies for user ${userId}`);
};

/**
 * Executes the RPC call to evaluate policies for a user in the database.
 * @param supabase - The Supabase client instance.
 * @param userId - The ID of the user whose policies are to be evaluated.
 * @returns A promise that resolves with the RPC result containing data or an error.
 * @throws Error if the RPC call fails to evaluate the policies.
 */
const executeEvaluatePoliciesRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
): Promise<any> => {
  return await supabase.schema("keyhippo_abac").rpc("evaluate_policies", {
    p_user_id: userId,
  });
};

/**
 * Logs the result of the policy evaluation for a user.
 * @param logger - The logger instance used for logging.
 * @param userId - The ID of the user whose policy evaluation was performed.
 * @param result - The boolean result of the policy evaluation.
 */
const logEvaluatePoliciesResult = (
  logger: Logger,
  userId: string,
  result: boolean,
): void => {
  logInfo(logger, `Policy evaluation result for user ${userId}: ${result}`);
};

/**
 * Handles errors that occur during the policy evaluation process.
 * @param error - The error encountered during the evaluation process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleEvaluatePoliciesError = (error: unknown, logger: Logger): never => {
  logError(logger, `Failed to evaluate policies: ${error}`);
  throw createDatabaseError(`Failed to evaluate policies: ${error}`);
};

/**
 * Evaluates policies for a user.
 * This function logs the attempt, fetches user attributes and all policies,
 * executes the policy evaluation RPC, parses the result, logs the outcome,
 * and returns the evaluation result.
 *
 * @param supabase - The Supabase client used to interact with the database.
 * @param userId - The ID of the user whose policies are to be evaluated.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with a boolean indicating the result of the policy evaluation.
 * @throws AppError if the evaluation process fails.
 */
export const evaluatePolicies = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<boolean> => {
  try {
    logEvaluatePoliciesAttempt(logger, userId);
    await logUserAttributes(supabase, userId, logger);
    await logAllPolicies(supabase, logger);

    const result = await executeEvaluatePoliciesRpc(supabase, userId);
    validateRpcResult(result, "evaluate_policies");

    const evaluationResult = parseEvaluationResult(result.data);
    logEvaluatePoliciesResult(logger, userId, evaluationResult);

    return evaluationResult;
  } catch (error) {
    return handleEvaluatePoliciesError(error, logger);
  }
};
