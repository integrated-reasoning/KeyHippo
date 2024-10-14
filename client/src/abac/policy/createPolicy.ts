import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to create a new policy.
 * @param logger - The logger instance used for logging.
 * @param policyName - The name of the policy being created.
 */
const logCreatePolicyAttempt = (logger: Logger, policyName: string): void => {
  logDebug(logger, `Creating policy with name ${policyName}`);
};

/**
 * Executes the RPC call to create a new policy in the database.
 * @param supabase - The Supabase client instance.
 * @param policyName - The name of the policy to create.
 * @param description - A description of the policy.
 * @param policy - The policy object to be created.
 * @returns A promise that resolves when the policy creation is successful.
 * @throws Error if the RPC call fails to create the policy.
 */
const executeCreatePolicyRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  policyName: string,
  description: string,
  policy: any,
): Promise<void> => {
  const { error } = await supabase
    .schema("keyhippo_abac")
    .rpc("create_policy", {
      p_name: policyName,
      p_description: description,
      p_policy: JSON.stringify(policy),
    });

  if (error) {
    throw new Error(`Failed to create policy: ${error.message}`);
  }
};

/**
 * Logs the successful creation of a new policy.
 * @param logger - The logger instance used for logging.
 * @param policyName - The name of the policy that was created.
 */
const logCreatePolicySuccess = (logger: Logger, policyName: string): void => {
  logInfo(logger, `Successfully created ABAC policy ${policyName}`);
};

/**
 * Handles errors that occur during the policy creation process.
 * @param error - The error encountered during the creation process.
 * @param logger - The logger instance used for logging errors.
 * @param policyName - The name of the policy that failed to be created.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleCreatePolicyError = (
  error: unknown,
  logger: Logger,
  policyName: string,
): never => {
  logError(logger, `Failed to create policy: ${error}`);
  throw createDatabaseError(`Failed to create policy: ${error}`);
};

/**
 * Creates a new policy.
 * @param supabase - The Supabase client used to interact with the database.
 * @param policyName - The name of the policy to create.
 * @param description - A description of the policy.
 * @param policy - The policy object to be created.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves when the policy has been successfully created.
 * @throws AppError if the creation process fails.
 */
export const createPolicy = async (
  supabase: SupabaseClient<any, "public", any>,
  policyName: string,
  description: string,
  policy: any,
  logger: Logger,
): Promise<void> => {
  try {
    logCreatePolicyAttempt(logger, policyName);
    await executeCreatePolicyRpc(supabase, policyName, description, policy);
    logCreatePolicySuccess(logger, policyName);
  } catch (error) {
    return handleCreatePolicyError(error, logger, policyName);
  }
};
