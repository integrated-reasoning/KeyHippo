import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, PolicyId, Policy } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to retrieve a policy.
 * @param logger - The logger instance used for logging.
 * @param policyId - The ID of the policy being retrieved.
 */
const logGetPolicyAttempt = (logger: Logger, policyId: PolicyId): void => {
  logDebug(logger, `Attempting to retrieve policy with ID: ${policyId}`);
};

/**
 * Executes the RPC call to retrieve a policy from the database.
 * @param supabase - The Supabase client instance.
 * @param policyId - The ID of the policy to retrieve.
 * @returns A promise that resolves with the policy data.
 * @throws Error if the RPC call fails to retrieve the policy.
 */
const executeGetPolicyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  policyId: PolicyId,
): Promise<Policy> => {
  const { data, error } = await supabase
    .schema("keyhippo_abac")
    .rpc("get_policy", {
      p_policy_id: policyId,
    })
    .single<Policy>();

  if (error) {
    throw new Error(`Get Policy RPC failed: ${error.message}`);
  }

  if (!data) {
    throw new Error(`Policy with ID ${policyId} not found`);
  }

  return data;
};

/**
 * Logs the successful retrieval of a policy.
 * @param logger - The logger instance used for logging.
 * @param policyId - The ID of the retrieved policy.
 */
const logGetPolicySuccess = (logger: Logger, policyId: PolicyId): void => {
  logInfo(logger, `Successfully retrieved policy with ID: ${policyId}`);
};

/**
 * Handles errors that occur during the get policy process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @param policyId - The ID of the policy involved in the failed operation.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleGetPolicyError = (
  error: unknown,
  logger: Logger,
  policyId: PolicyId,
): never => {
  logError(
    logger,
    `Failed to retrieve policy with ID: ${policyId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to get policy: ${error}`);
};

/**
 * Retrieves a policy by its ID.
 * @param supabase - The Supabase client.
 * @param policyId - The ID of the policy to retrieve.
 * @param logger - The logger instance.
 * @returns The retrieved policy.
 * @throws ApplicationError if the process fails.
 */
export const getPolicy = async (
  supabase: SupabaseClient<any, "public", any>,
  policyId: PolicyId,
  logger: Logger,
): Promise<Policy> => {
  try {
    logGetPolicyAttempt(logger, policyId);
    const policy = await executeGetPolicyRpc(supabase, policyId);
    logGetPolicySuccess(logger, policyId);
    return policy;
  } catch (error) {
    return handleGetPolicyError(error, logger, policyId);
  }
};
