import { SupabaseClient } from "@supabase/supabase-js";
import { Logger } from "../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../utils";

/**
 * Logs the attempt to set a parent role for a child role.
 * @param logger - The logger instance used for logging.
 * @param childRoleId - The ID of the child role.
 * @param parentRoleId - The ID of the parent role to be set.
 */
const logSetParentRoleAttempt = (
  logger: Logger,
  childRoleId: string,
  parentRoleId: string,
): void => {
  logDebug(
    logger,
    `Setting parent role for child role ${childRoleId} to ${parentRoleId}`,
  );
};

/**
 * Executes the database update to set the parent role for a child role.
 * @param supabase - The Supabase client instance.
 * @param childRoleId - The ID of the child role.
 * @param parentRoleId - The ID of the parent role to be set.
 * @returns A promise that resolves when the update is successful.
 * @throws Error if the database update fails.
 */
const executeUpdateParentRole = async (
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: string,
  parentRoleId: string,
): Promise<void> => {
  const { error } = await supabase
    .from("roles")
    .update({ parent_role_id: parentRoleId })
    .eq("id", childRoleId);

  if (error) {
    throw new Error(`Failed to update parent role: ${error.message}`);
  }
};

/**
 * Fetches the updated parent role information for a child role.
 * @param supabase - The Supabase client instance.
 * @param childRoleId - The ID of the child role.
 * @returns A promise that resolves with the updated parent role ID.
 * @throws Error if fetching the updated role information fails.
 */
const fetchUpdatedRoleInfo = async (
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: string,
): Promise<{ parent_role_id: string | null }> => {
  const { data, error } = await supabase
    .from("roles")
    .select("parent_role_id")
    .eq("id", childRoleId)
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to fetch updated role: ${
        error ? error.message : "No data returned"
      }`,
    );
  }

  return { parent_role_id: data.parent_role_id };
};

/**
 * Logs the successful setting of a parent role for a child role.
 * @param logger - The logger instance used for logging.
 * @param childRoleId - The ID of the child role.
 * @param parentRoleId - The ID of the parent role that was set.
 */
const logParentRoleSet = (
  logger: Logger,
  childRoleId: string,
  parentRoleId: string | null,
): void => {
  logInfo(
    logger,
    `Parent role set for child role ${childRoleId}: ${parentRoleId}`,
  );
};

/**
 * Handles errors that occur during the process of setting a parent role.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
const handleSetParentRoleError = (error: unknown, logger: Logger): never => {
  logError(logger, `Failed to set parent role: ${error}`);
  throw createDatabaseError(`Failed to set parent role: ${error}`);
};

/**
 * Sets the parent role for a child role.
 * @param supabase - The Supabase client used to interact with the database.
 * @param childRoleId - The ID of the child role.
 * @param parentRoleId - The ID of the parent role to be set.
 * @param logger - The logger instance used for logging events and errors.
 * @returns A promise that resolves with an object containing the parent role ID.
 * @throws AppError if the setting process fails.
 */
export const setParentRole = async (
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: string,
  parentRoleId: string,
  logger: Logger,
): Promise<{ parent_role_id: string | null }> => {
  try {
    logSetParentRoleAttempt(logger, childRoleId, parentRoleId);
    await executeUpdateParentRole(supabase, childRoleId, parentRoleId);
    const updatedRole = await fetchUpdatedRoleInfo(supabase, childRoleId);

    logParentRoleSet(logger, childRoleId, updatedRole.parent_role_id);
    return updatedRole;
  } catch (error) {
    return handleSetParentRoleError(error, logger);
  }
};
