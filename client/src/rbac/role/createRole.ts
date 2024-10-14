import { SupabaseClient } from "@supabase/supabase-js";
import { Logger, GroupId, RoleId } from "../../types";
import { logDebug, logInfo, logError, createDatabaseError } from "../../utils";

/**
 * Logs the attempt to create a new role.
 * @param logger - The logger instance used for logging.
 * @param roleName - The name of the role being created.
 * @param groupId - The ID of the group to which the role belongs.
 */
const logCreateRoleAttempt = (
  logger: Logger,
  roleName: string,
  groupId: GroupId,
): void => {
  logDebug(
    logger,
    `Attempting to create role '${roleName}' in Group ID: ${groupId}`,
  );
};

/**
 * Executes the RPC call to create a new role in the database.
 * @param supabase - The Supabase client instance.
 * @param roleName - The name of the role being created.
 * @param groupId - The ID of the group to which the role belongs.
 * @param description - A description of the role.
 * @returns A promise that resolves with the new role's ID.
 * @throws Error if the RPC call fails to create the role.
 */
const executeCreateRoleRpc = async (
  supabase: SupabaseClient<any, "public", any>,
  roleName: string,
  groupId: GroupId,
  description: string,
): Promise<{ role_id: RoleId }> => {
  const { data, error } = await supabase
    .schema("keyhippo_rbac")
    .rpc("create_role", {
      p_role_name: roleName,
      p_group_id: groupId,
      p_description: description,
    })
    .single<{ role_id: RoleId }>();

  if (error) {
    throw new Error(`Create Role RPC failed: ${error.message}`);
  }

  if (!data || !data.role_id) {
    throw new Error("Invalid data returned from create_role RPC");
  }

  return { role_id: data.role_id };
};

/**
 * Logs the successful creation of a new role.
 * @param logger - The logger instance used for logging.
 * @param roleName - The name of the role that was created.
 * @param roleId - The ID of the newly created role.
 */
const logCreateRoleSuccess = (
  logger: Logger,
  roleName: string,
  roleId: RoleId,
): void => {
  logInfo(
    logger,
    `Successfully created role '${roleName}' with Role ID: ${roleId}`,
  );
};

/**
 * Handles errors that occur during the create role process.
 * @param error - The error encountered during the process.
 * @param logger - The logger instance used for logging errors.
 * @throws ApplicationError encapsulating the original error with a descriptive message.
 */
const handleCreateRoleError = (
  error: unknown,
  logger: Logger,
  roleName: string,
  groupId: GroupId,
): never => {
  logError(
    logger,
    `Failed to create role '${roleName}' in Group ID: ${groupId}. Error: ${error}`,
  );
  throw createDatabaseError(`Failed to create role: ${error}`);
};

/**
 * Creates a new role within a specified group.
 * @param supabase - The Supabase client.
 * @param roleName - The name of the role to create.
 * @param groupId - The ID of the group to which the role belongs.
 * @param description - A description of the role.
 * @param logger - The logger instance.
 * @returns The ID of the newly created role.
 * @throws ApplicationError if the process fails.
 */
export const createRole = async (
  supabase: SupabaseClient<any, "public", any>,
  roleName: string,
  groupId: GroupId,
  description: string = "",
  logger: Logger,
): Promise<RoleId> => {
  try {
    logCreateRoleAttempt(logger, roleName, groupId);
    const result = await executeCreateRoleRpc(
      supabase,
      roleName,
      groupId,
      description,
    );
    logCreateRoleSuccess(logger, roleName, result.role_id);
    return result.role_id;
  } catch (error) {
    return handleCreateRoleError(error, logger, roleName, groupId);
  }
};
