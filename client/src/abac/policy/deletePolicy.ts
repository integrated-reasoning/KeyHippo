import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, PolicyId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to delete a policy.
 * @param logger - The logger instance used for logging.
 * @param policyId - The ID of the policy being deleted.
 */
const logDeletePolicyAttempt = (logger: Logger, policyId: PolicyId): void => {
  logDebug(logger, `Attempting to delete policy with ID: ${policyId}`);
};

/**
 * Executes the RPC call to delete a policy from the database.
 * @param supabase - The Supabase client instance.
 * @param policyId - The ID of the policy to be deleted.
 * @returns A promise that resolves with a boolean indicating success.
 * @throws Error if the RPC call fails to delete the policy.
 */
const executeDeletePolicyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  policyId: PolicyId,
): Promise<{ success: boolean }> => {
  const { data, error } = await supabase
    .schema("keyhippo_abac")
    .rpc("delete_policy", {
      p_policy_id: policyId,
    })
    .single<boolean>();

  if (error) {
    throw new Error(`Delete Policy RPC failed: ${error.message}`);
  }

  return { success: !!data };
};

/**
 * Logs the successful deletion of a policy.
 * @param logger - The logger instance used for logging.
 * @param policyId - The ID of the policy that was deleted.
 */
const logDeletePolicySuccess = (logger: Logger, policyId: PolicyId): void => {
  logInfo(logger, `Successfully deleted policy with ID: ${policyId}`);
};

/**
 * Handles errors that occur during the delete policy process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleDeletePolicyError = (
  error: unknown,
  logger: Logger,
  policyId: PolicyId,
): never => {
  logError(
    logger,
    `Failed to delete policy with ID: ${policyId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to delete policy: ${error}`);
};

/**
 * Deletes an existing policy from the ABAC system.
 * @param supabase - The Supabase client.
 * @param policyId - The ID of the policy to delete.
 * @param logger - The logger instance.
 * @returns A boolean indicating whether the deletion was successful.
 * @throws ApplicationError if the process fails.
 */
export const deletePolicy = async (
  supabase: SupabaseClient<any, "public", any>,
  policyId: PolicyId,
  logger: Logger,
): Promise<boolean> => {
  try {
    logDeletePolicyAttempt(logger, policyId);
    const result = await executeDeletePolicyRpc(supabase, policyId);
    logDeletePolicySuccess(logger, policyId);
    return result.success;
  } catch (error) {
    return handleDeletePolicyError(error, logger, policyId);
  }
};
