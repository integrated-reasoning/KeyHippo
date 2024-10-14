import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, PolicyId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to update a policy.
 * @param logger - The logger instance used for logging.
 * @param policyId - The ID of the policy being updated.
 */
const logUpdatePolicyAttempt = (logger: Logger, policyId: PolicyId): void => {
  logDebug(logger, `Attempting to update policy with ID: ${policyId}`);
};

/**
 * Executes the RPC call to update a policy in the database.
 * @param supabase - The Supabase client instance.
 * @param policyId - The ID of the policy being updated.
 * @param name - The new name for the policy.
 * @param description - The new description for the policy.
 * @param policy - The new policy JSON.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to update the policy.
 */
const executeUpdatePolicyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  policyId: PolicyId,
  name: string,
  description: string,
  policy: object,
): Promise<{ success: boolean }> => {
  const { data, error } = await supabase
    .schema("keyhippo_abac")
    .rpc("update_policy", {
      p_policy_id: policyId,
      p_name: name,
      p_description: description,
      p_policy: policy,
    })
    .single<boolean>();

  if (error) {
    throw new Error(`Update Policy RPC failed: ${error.message}`);
  }

  return { success: !!data };
};

/**
 * Logs the successful update of a policy.
 * @param logger - The logger instance used for logging.
 * @param policyId - The ID of the policy that was updated.
 */
const logUpdatePolicySuccess = (logger: Logger, policyId: PolicyId): void => {
  logInfo(logger, `Successfully updated policy with ID: ${policyId}`);
};

/**
 * Handles errors that occur during the update policy process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleUpdatePolicyError = (
  error: unknown,
  logger: Logger,
  policyId: PolicyId,
): never => {
  logError(
    logger,
    `Failed to update policy with ID: ${policyId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to update policy: ${error}`);
};

/**
 * Updates an existing policy in the ABAC system.
 * @param supabase - The Supabase client.
 * @param policyId - The ID of the policy to update.
 * @param name - The new name for the policy.
 * @param description - The new description for the policy.
 * @param policy - The new policy JSON.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the update was successful.
 * @throws ApplicationError if the process fails.
 */
export const updatePolicy = async (
  supabase: SupabaseClient<any, "public", any>,
  policyId: PolicyId,
  name: string,
  description: string,
  policy: object,
  logger: Logger,
): Promise<boolean> => {
  try {
    logUpdatePolicyAttempt(logger, policyId);
    const result = await executeUpdatePolicyRpc(
      supabase,
      policyId,
      name,
      description,
      policy,
    );
    logUpdatePolicySuccess(logger, policyId);
    return result.success;
  } catch (error) {
    return handleUpdatePolicyError(error, logger, policyId);
  }
};
