import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, GroupId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to create a new group.
 * @param logger - The logger instance used for logging.
 * @param groupName - The name of the group being created.
 */
const logCreateGroupAttempt = (logger: Logger, groupName: string): void => {
  logDebug(logger, `Attempting to create group '${groupName}'`);
};

/**
 * Executes the RPC call to create a new group in the database.
 * @param supabase - The Supabase client instance.
 * @param groupName - The name of the group being created.
 * @param description - A description of the group.
 * @returns A promise that resolves with the new group's ID.
 * @throws Error if the RPC call fails to create the group.
 */
const executeCreateGroupRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  groupName: string,
  description: string,
): Promise<GroupId> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("create_group", {
      p_name: groupName,
      p_description: description,
    });

  if (error) {
    throw new Error(`Create Group RPC failed: ${error.message}`);
  }

  if (!data) {
    throw new Error("Invalid data returned from create_group RPC");
  }

  return data as GroupId;
};

/**
 * Logs the successful creation of a new group.
 * @param logger - The logger instance used for logging.
 * @param groupName - The name of the group that was created.
 * @param groupId - The ID of the newly created group.
 */
const logCreateGroupSuccess = (
  logger: Logger,
  groupName: string,
  groupId: GroupId,
): void => {
  logInfo(
    logger,
    `Successfully created group '${groupName}' with Group ID: ${groupId}`,
  );
};

/**
 * Handles errors that occur during the create group process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleCreateGroupError = (
  error: unknown,
  logger: Logger,
  groupName: string,
): never => {
  logError(logger, `Failed to create group '${groupName}'. Error: ${error}`);
  throw createDatabaseError(`Failed to create group: ${error}`);
};

/**
 * Creates a new group.
 * @param supabase - The Supabase client.
 * @param groupName - The name of the group to create.
 * @param description - A description of the group.
 * @param logger - The logger instance.
 * @returns The ID of the newly created group.
 * @throws ApplicationError if the process fails.
 */
export const createGroup = async (
  supabase: SupabaseClient<any, "public", any>,
  groupName: string,
  description: string,
  logger: Logger,
): Promise<GroupId> => {
  try {
    logCreateGroupAttempt(logger, groupName);
    const groupId = await executeCreateGroupRpc(
      supabase,
      groupName,
      description,
    );
    logCreateGroupSuccess(logger, groupName, groupId);
    return groupId;
  } catch (error) {
    return handleCreateGroupError(error, logger, groupName);
  }
};
