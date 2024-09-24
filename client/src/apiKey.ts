import { v4 as uuidv4 } from "uuid";
import { SupabaseClient, PostgrestSingleResponse } from "@supabase/supabase-js";
import {
  ApiKeyInfo,
  ApiKeyMetadata,
  CompleteApiKeyInfo,
  RotateApiKeyResult,
  AppError,
  Logger,
} from "./types";

export const createApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  keyDescription: string,
  logger: Logger,
): Promise<CompleteApiKeyInfo> => {
  const uniqueId = uuidv4();
  const uniqueDescription = `${uniqueId}-${keyDescription}`; // TODO remove redundancy

  try {
    const { error } = await supabase.schema("keyhippo").rpc("create_api_key", {
      id_of_user: userId,
      key_description: uniqueDescription,
    });

    if (error) {
      throw new Error(`Create API key rpc failed: ${error.message}`);
    }

    const keyInfos = await loadApiKeyInfo(supabase, userId, logger);
    const createdKeyInfo = findCreatedKeyInfo(keyInfos, uniqueDescription);
    const apiKey = await getApiKey(supabase, userId, createdKeyInfo.id);

    const completeKeyInfo: CompleteApiKeyInfo = {
      id: createdKeyInfo.id,
      description: uniqueDescription,
      apiKey,
      status: "success",
    };

    logger.info(
      `New API key created for user: ${userId}, Key ID: ${completeKeyInfo.id}`,
    );

    return completeKeyInfo;
  } catch (error) {
    logger.error(`Failed to create new API key: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to create API key: ${getErrorMessage(error)}`,
    );
  }
};

export const loadApiKeyInfo = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<ApiKeyInfo[]> => {
  try {
    const result = await supabase
      .schema("keyhippo")
      .rpc("load_api_key_info", { id_of_user: userId });

    logRpcResult(logger, result);

    if (result.error) {
      throw new Error(`Error loading API key info: ${result.error.message}`);
    }

    const apiKeyInfo = parseApiKeyInfo(result.data);

    logger.info(
      `API key info loaded for user: ${userId}. Count: ${apiKeyInfo.length}`,
    );

    return apiKeyInfo;
  } catch (error) {
    logger.error(`Failed to load API key info: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to load API key info: ${getErrorMessage(error)}`,
    );
  }
};

function findCreatedKeyInfo(
  keyInfos: ApiKeyInfo[],
  description: string,
): ApiKeyInfo {
  const createdKeyInfo = keyInfos.find(
    (keyInfo) => keyInfo.description === description,
  );

  if (!createdKeyInfo) {
    throw new Error("Failed to find the newly created API key");
  }

  return createdKeyInfo;
}

async function getApiKey(
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  secretId: string,
): Promise<string> {
  const response: PostgrestSingleResponse<unknown> = await supabase
    .schema("keyhippo")
    .rpc("get_api_key", {
      id_of_user: userId,
      secret_id: secretId,
    });

  if (response.error) {
    throw new Error(`Failed to retrieve API key: ${response.error.message}`);
  }

  if (typeof response.data !== "string") {
    throw new Error("Invalid API key format returned");
  }

  return response.data;
}

export const revokeApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  secretId: string,
  logger: Logger,
): Promise<void> => {
  try {
    const { error } = await supabase.schema("keyhippo").rpc("revoke_api_key", {
      id_of_user: userId,
      secret_id: secretId,
    });

    if (error) {
      throw new Error(`Error revoking API key: ${error.message}`);
    }

    logger.info(`API key revoked for user: ${userId}, Secret ID: ${secretId}`);
  } catch (error) {
    logger.error(`Failed to revoke API key: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to revoke API key: ${getErrorMessage(error)}`,
    );
  }
};

export const getAllKeyMetadata = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<ApiKeyMetadata[]> => {
  try {
    logger.debug(`Calling get_api_key_metadata RPC for user: ${userId}`);
    const result = await supabase
      .schema("keyhippo")
      .rpc("get_api_key_metadata", { id_of_user: userId });

    logRpcResult(logger, result);

    if (result.error) {
      throw new Error(
        `Error getting API key metadata: ${result.error.message}`,
      );
    }

    const metadata = parseApiKeyMetadata(result.data);

    logger.info(`API key metadata retrieved. Count: ${metadata.length}`);
    return metadata;
  } catch (error) {
    logger.error(`Failed to get API key metadata: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to get API key metadata: ${getErrorMessage(error)}`,
    );
  }
};

export const rotateApiKey = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  apiKeyId: string,
  logger: Logger,
): Promise<CompleteApiKeyInfo> => {
  try {
    const result = await supabase.schema("keyhippo").rpc("rotate_api_key", {
      p_api_key_id: apiKeyId,
    });

    if (result.error) {
      throw new Error(`Error rotating API key: ${result.error.message}`);
    }

    const rotatedKeyInfo = parseRotatedApiKeyInfo(result.data);

    logger.info(
      `API key rotated for user: ${userId}, New Key ID: ${rotatedKeyInfo.id}`,
    );

    return rotatedKeyInfo;
  } catch (error) {
    logger.error(`Failed to rotate API key: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to rotate API key: ${getErrorMessage(error)}`,
    );
  }
};

// RBAC Methods

export const addUserToGroup = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  groupId: string,
  roleName: string,
  logger: Logger,
): Promise<void> => {
  try {
    logger.debug(
      `Adding user ${userId} to group ${groupId} with role ${roleName}`,
    );
    const { error } = await supabase
      .schema("keyhippo_rbac")
      .rpc("add_user_to_group", {
        p_user_id: userId,
        p_group_id: groupId,
        p_role_name: roleName,
      });

    if (error) {
      throw new Error(`Failed to add user to group: ${error.message}`);
    }

    logger.info(`Successfully added user ${userId} to group ${groupId}`);
  } catch (error) {
    logger.error(
      `Failed to add user to group ${groupId}: ${getErrorMessage(error)}`,
    );
    throw createDatabaseError(
      `Failed to add user to group: ${getErrorMessage(error)}`,
    );
  }
};

export const setParentRole = async (
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: string,
  parentRoleId: string,
  logger: Logger,
): Promise<{ parent_role_id: string | null }> => {
  try {
    logger.debug(
      `Setting parent role for child role ${childRoleId} to ${parentRoleId}`,
    );

    await updateParentRole(supabase, childRoleId, parentRoleId);
    const updatedRole = await fetchUpdatedRole(supabase, childRoleId);

    logger.info(
      `Parent role set for child role ${childRoleId}: ${updatedRole.parent_role_id}`,
    );

    return updatedRole;
  } catch (error) {
    logger.error(`Failed to set parent role: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to set parent role: ${getErrorMessage(error)}`,
    );
  }
};

export const updateUserClaimsCache = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<void> => {
  try {
    logger.debug(`Updating claims cache for user ${userId}`);
    const { error } = await supabase
      .schema("keyhippo_rbac")
      .rpc("update_user_claims_cache", {
        p_user_id: userId,
      });

    if (error) {
      throw new Error(`Failed to update claims cache: ${error.message}`);
    }

    logger.info(`Successfully updated claims cache for user ${userId}`);
  } catch (error) {
    logger.error(
      `Failed to update claims cache for user ${userId}: ${getErrorMessage(error)}`,
    );
    throw createDatabaseError(
      `Failed to update claims cache: ${getErrorMessage(error)}`,
    );
  }
};

// ABAC Methods

export const createPolicy = async (
  supabase: SupabaseClient<any, "public", any>,
  policyName: string,
  description: string,
  policy: any,
  logger: Logger,
): Promise<void> => {
  try {
    logger.debug(`Creating policy with name ${policyName}`);
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

    logger.info(`Successfully created ABAC policy ${policyName}`);
  } catch (error) {
    logger.error(`Failed to create policy: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to create policy: ${getErrorMessage(error)}`,
    );
  }
};

export const evaluatePolicies = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<boolean> => {
  try {
    logger.debug(`Evaluating policies for user ${userId}`);

    await logUserAttributes(supabase, userId, logger);
    await logAllPolicies(supabase, logger);

    const { data, error } = await supabase
      .schema("keyhippo_abac")
      .rpc("evaluate_policies", {
        p_user_id: userId,
      });

    if (error) {
      throw new Error(`Failed to evaluate policies: ${error.message}`);
    }

    const result = data as boolean;
    logger.info(`Policy evaluation result for user ${userId}: ${result}`);
    return result;
  } catch (error) {
    logger.error(`Failed to evaluate policies: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to evaluate policies: ${getErrorMessage(error)}`,
    );
  }
};

export const getUserAttribute = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  attribute: string,
  logger: Logger,
): Promise<any> => {
  try {
    logger.debug(`Retrieving user attribute ${attribute} for user ${userId}`);
    const { data, error } = await supabase
      .schema("keyhippo_abac")
      .rpc("get_user_attribute", {
        p_user_id: userId,
        p_attribute: attribute,
      });

    if (error) {
      throw new Error(`Failed to retrieve user attribute: ${error.message}`);
    }

    logger.info(
      `User ${userId} attribute ${attribute}: ${JSON.stringify(data)}`,
    );
    return data;
  } catch (error) {
    logger.error(
      `Failed to retrieve user attribute: ${getErrorMessage(error)}`,
    );
    throw createDatabaseError(
      `Failed to retrieve user attribute: ${getErrorMessage(error)}`,
    );
  }
};

export const setUserAttribute = async (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  attribute: string,
  value: any,
  logger: Logger,
): Promise<void> => {
  try {
    logger.debug(`Setting attribute ${attribute} for user ${userId}`);
    const { error } = await supabase
      .schema("keyhippo_abac")
      .rpc("set_user_attribute", {
        p_user_id: userId,
        p_attribute: attribute,
        p_value: value,
      });

    if (error) {
      throw new Error(`Failed to set user attribute: ${error.message}`);
    }

    logger.info(`Successfully set attribute ${attribute} for user ${userId}`);
  } catch (error) {
    logger.error(`Failed to set user attribute: ${getErrorMessage(error)}`);
    throw createDatabaseError(
      `Failed to set user attribute: ${getErrorMessage(error)}`,
    );
  }
};

// Helper functions

async function logUserAttributes(
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Promise<void> {
  const { data: userAttributes, error } = await supabase
    .schema("keyhippo_abac")
    .from("user_attributes")
    .select("attributes")
    .eq("user_id", userId)
    .single();

  if (error) {
    logger.warn(`Failed to fetch user attributes: ${error.message}`);
  } else {
    logger.debug(`User attributes: ${JSON.stringify(userAttributes)}`);
  }
}

async function logAllPolicies(
  supabase: SupabaseClient<any, "public", any>,
  logger: Logger,
): Promise<void> {
  const { data: policies, error } = await supabase
    .schema("keyhippo_abac")
    .from("policies")
    .select("*");

  if (error) {
    logger.warn(`Failed to fetch policies: ${error.message}`);
  } else {
    logger.debug(`All policies: ${JSON.stringify(policies)}`);
  }
}

async function updateParentRole(
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: string,
  parentRoleId: string,
): Promise<void> {
  const { error } = await supabase
    .from("roles")
    .update({ parent_role_id: parentRoleId })
    .eq("id", childRoleId);

  if (error) {
    throw new Error(`Failed to update parent role: ${error.message}`);
  }
}

async function fetchUpdatedRole(
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: string,
): Promise<{ parent_role_id: string | null }> {
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
}

function parseApiKeyMetadata(data: unknown): ApiKeyMetadata[] {
  if (!Array.isArray(data)) {
    throw new Error("Invalid data returned when getting API key metadata");
  }

  return data.map((item: any) => ({
    api_key_id: item.api_key_id,
    name: item.name || "",
    permission: item.permission || "",
    last_used: item.last_used,
    created: item.created,
    revoked: item.revoked,
    total_uses: Number(item.total_uses),
    success_rate: Number(item.success_rate),
    total_cost: Number(item.total_cost),
  }));
}

function parseRotatedApiKeyInfo(data: unknown): CompleteApiKeyInfo {
  if (!Array.isArray(data) || data.length === 0) {
    throw new Error("No data returned after rotating API key");
  }

  const dataItem = data[0] as RotateApiKeyResult;

  if (!dataItem.new_api_key || !dataItem.new_api_key_id) {
    throw new Error("Invalid data structure returned after rotating API key");
  }

  return {
    id: dataItem.new_api_key_id,
    description: dataItem.description || "Rotated API Key",
    apiKey: dataItem.new_api_key,
    status: "success" as const,
  };
}

function logRpcResult(logger: Logger, result: any): void {
  logger.debug(`Raw result from RPC: ${JSON.stringify(result)}`);
  logger.debug(
    `Result status: ${result.status}, statusText: ${result.statusText}`,
  );
  logger.debug(`Result error: ${JSON.stringify(result.error)}`);
  logger.debug(`Result data: ${JSON.stringify(result.data)}`);
}

function parseApiKeyInfo(data: unknown): ApiKeyInfo[] {
  if (data === null) {
    return [];
  }

  if (!Array.isArray(data)) {
    throw new Error(
      `Invalid data returned when loading API key info: ${JSON.stringify(data)}`,
    );
  }

  return data.map((item: any) => ({
    id: item.id,
    description: item.description,
  }));
}

function getErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function createDatabaseError(message: string): AppError {
  return { _tag: "DatabaseError", message };
}
