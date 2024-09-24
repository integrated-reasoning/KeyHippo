import { Effect, pipe } from "effect";
import { v4 as uuidv4 } from "uuid";
import { SupabaseClient, PostgrestSingleResponse } from "@supabase/supabase-js";
import {
  ApiKeyInfo,
  ApiKeyMetadata,
  CompleteApiKeyInfo,
  AppError,
  Logger,
} from "./types";

export const createApiKey = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  keyDescription: string,
  logger: Logger,
): Effect.Effect<CompleteApiKeyInfo, AppError> => {
  const uniqueId = uuidv4();
  const uniqueDescription = `${uniqueId}-${keyDescription}`;
  return pipe(
    Effect.tryPromise({
      try: () =>
        supabase.schema("keyhippo").rpc("create_api_key", {
          id_of_user: userId,
          key_description: uniqueDescription,
        }),
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to create API key: ${String(error)}`,
      }),
    }),
    Effect.flatMap(() => loadApiKeyInfo(supabase, userId, logger)),
    Effect.tap((keyInfos) =>
      Effect.sync(() =>
        logger.info(`Loaded key info: ${JSON.stringify(keyInfos)}`),
      ),
    ),
    Effect.flatMap((keyInfos) => {
      const createdKeyInfo = keyInfos.find(
        (keyInfo) => keyInfo.description === uniqueDescription,
      );
      if (!createdKeyInfo) {
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: "Failed to find the newly created API key",
        });
      }
      return Effect.succeed(createdKeyInfo);
    }),
    Effect.flatMap((keyInfo) =>
      pipe(
        Effect.tryPromise({
          try: () =>
            supabase.schema("keyhippo").rpc("get_api_key", {
              id_of_user: userId,
              secret_id: keyInfo.id,
            }),
          catch: (error): AppError => ({
            _tag: "DatabaseError",
            message: `Failed to retrieve API key: ${String(error)}`,
          }),
        }),
        Effect.map(
          (response: PostgrestSingleResponse<unknown>): CompleteApiKeyInfo => {
            if (response.error) {
              throw new Error(
                `Failed to retrieve API key: ${response.error.message}`,
              );
            }
            if (typeof response.data !== "string") {
              throw new Error("Invalid API key format returned");
            }
            return {
              id: keyInfo.id,
              description: uniqueDescription,
              apiKey: response.data,
              status: "success",
            };
          },
        ),
      ),
    ),
    Effect.tap((completeKeyInfo: CompleteApiKeyInfo) =>
      Effect.sync(() =>
        logger.info(
          `New API key created for user: ${userId}, Key ID: ${completeKeyInfo.id}`,
        ),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() =>
        logger.error(`Failed to create new API key: ${error.message}`),
      ),
    ),
  );
};

export const loadApiKeyInfo = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Effect.Effect<ApiKeyInfo[], AppError> => {
  return pipe(
    Effect.tryPromise({
      try: () =>
        supabase
          .schema("keyhippo")
          .rpc("load_api_key_info", { id_of_user: userId }),
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to load API key info: ${String(error)}`,
      }),
    }),
    Effect.tap((result: any) =>
      Effect.sync(() => {
        logger.debug(`Raw result from RPC: ${JSON.stringify(result)}`);
        logger.debug(
          `Result status: ${result.status}, statusText: ${result.statusText}`,
        );
        logger.debug(`Result error: ${JSON.stringify(result.error)}`);
        logger.debug(`Result data: ${JSON.stringify(result.data)}`);
      }),
    ),
    Effect.flatMap((result: any) => {
      if (result.error) {
        logger.error(`Database error: ${result.error.message}`);
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: `Error loading API key info: ${result.error.message}`,
        });
      }
      if (result.data === null) {
        logger.warn(`No data returned for user: ${userId}`);
        return Effect.succeed([]);
      }
      if (!Array.isArray(result.data)) {
        logger.error(`Invalid data structure: ${JSON.stringify(result.data)}`);
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: `Invalid data returned when loading API key info: ${JSON.stringify(result)}`,
        });
      }
      try {
        const apiKeyInfo = result.data.map((item: any) => ({
          id: item.id,
          description: item.description,
        }));
        return Effect.succeed(apiKeyInfo);
      } catch (error) {
        logger.error(`Error parsing API key info: ${String(error)}`);
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: `Failed to parse API key info: ${String(error)}`,
        });
      }
    }),
    Effect.tap((apiKeyInfo: ApiKeyInfo[]) =>
      Effect.sync(() =>
        logger.info(
          `API key info loaded for user: ${userId}. Count: ${apiKeyInfo.length}`,
        ),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() => {
        logger.error(`Failed to load API key info: ${JSON.stringify(error)}`);
      }),
    ),
  );
};

export const revokeApiKey = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  secretId: string,
  logger: Logger,
): Effect.Effect<void, AppError> =>
  pipe(
    Effect.tryPromise({
      try: () =>
        supabase.schema("keyhippo").rpc("revoke_api_key", {
          id_of_user: userId,
          secret_id: secretId,
        }),
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to revoke API key: ${String(error)}`,
      }),
    }),
    Effect.flatMap((result: any) => {
      if (result.error) {
        return Effect.fail({
          _tag: "DatabaseError",
          message: `Error revoking API key: ${result.error.message}`,
        } as const);
      }
      return Effect.succeed(undefined);
    }),
    Effect.tap(() =>
      Effect.sync(() =>
        logger.info(
          `API key revoked for user: ${userId}, Secret ID: ${secretId}`,
        ),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() =>
        logger.error(`Failed to revoke API key: ${error.message}`),
      ),
    ),
  );

export const getAllKeyMetadata = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Effect.Effect<ApiKeyMetadata[], AppError> =>
  pipe(
    Effect.tryPromise({
      try: () => {
        logger.debug(`Calling get_api_key_metadata RPC for user: ${userId}`);
        return supabase
          .schema("keyhippo")
          .rpc("get_api_key_metadata", { id_of_user: userId });
      },
      catch: (error): AppError => {
        logger.error(`Error in RPC call: ${String(error)}`);
        return {
          _tag: "DatabaseError",
          message: `Failed to get API key metadata: ${String(error)}`,
        };
      },
    }),
    Effect.tap((result: any) =>
      Effect.sync(() => logger.debug(`RPC result: ${JSON.stringify(result)}`)),
    ),
    Effect.flatMap((result: PostgrestSingleResponse<unknown>) => {
      if (result.error) {
        logger.error(`Database error: ${result.error.message}`);
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: `Error getting API key metadata: ${result.error.message}`,
        });
      }
      logger.debug(`Raw data from database: ${JSON.stringify(result.data)}`);
      if (!Array.isArray(result.data)) {
        logger.error(`Invalid data structure: ${JSON.stringify(result.data)}`);
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: "Invalid data returned when getting API key metadata",
        });
      }
      const metadata: ApiKeyMetadata[] = result.data.map((item: any) => ({
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
      logger.debug(`Processed metadata: ${JSON.stringify(metadata)}`);
      return Effect.succeed(metadata);
    }),
    Effect.tap((metadata: ApiKeyMetadata[]) =>
      Effect.sync(() =>
        logger.info(`API key metadata retrieved. Count: ${metadata.length}`),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() =>
        logger.error(
          `Failed to get API key metadata: ${JSON.stringify(error)}`,
        ),
      ),
    ),
  );

export const rotateApiKey = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  apiKeyId: string,
  logger: Logger,
): Effect.Effect<CompleteApiKeyInfo, AppError> => {
  type RotateApiKeyResult = {
    new_api_key: string;
    new_api_key_id: string;
  };

  return pipe(
    Effect.tryPromise({
      try: () =>
        supabase.schema("keyhippo").rpc("rotate_api_key", {
          p_api_key_id: apiKeyId,
        }),
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to rotate API key: ${String(error)}`,
      }),
    }),
    Effect.flatMap((result: PostgrestSingleResponse<RotateApiKeyResult[]>) => {
      if (result.error) {
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: `Error rotating API key: ${result.error.message}`,
        });
      }
      if (!Array.isArray(result.data) || result.data.length === 0) {
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: "No data returned after rotating API key",
        });
      }
      const dataItem = result.data[0];

      const completeApiKeyInfo: CompleteApiKeyInfo = {
        id: dataItem.new_api_key_id,
        description: "", // You may need to fetch or retain the description
        apiKey: dataItem.new_api_key,
        status: "success" as const, // Ensure 'status' is of type '"success" | "failed"'
      };
      return Effect.succeed(completeApiKeyInfo);
    }),
    Effect.tap((rotatedKeyInfo: CompleteApiKeyInfo) =>
      Effect.sync(() =>
        logger.info(
          `API key rotated for user: ${userId}, New Key ID: ${rotatedKeyInfo.id}`,
        ),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() =>
        logger.error(`Failed to rotate API key: ${error.message}`),
      ),
    ),
  );
};

// RBAC Methods
export const addUserToGroup = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  groupId: string,
  roleName: string,
  logger: Logger,
): Effect.Effect<void, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        logger.debug(
          `Adding user ${userId} to group ${groupId} with role ${roleName}`,
        );
        const result = await supabase
          .schema("keyhippo_rbac")
          .rpc("add_user_to_group", {
            p_user_id: userId,
            p_group_id: groupId,
            p_role_name: roleName,
          });
        logger.debug(
          `Result of adding user to group: ${JSON.stringify(result)}`,
        );
        return result;
      },
      catch: (error): AppError => {
        logger.error(
          `Failed to add user to group ${groupId}: ${String(error)}`,
        );
        return {
          _tag: "DatabaseError",
          message: `Failed to add user to group: ${String(error)}`,
        };
      },
    }),
    Effect.tap(() =>
      Effect.sync(() =>
        logger.info(`Successfully added user ${userId} to group ${groupId}`),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() =>
        logger.error(`Failed to add user to group: ${error.message}`),
      ),
    ),
  );

export const setParentRole = (
  supabase: SupabaseClient<any, "public", any>,
  childRoleId: string,
  parentRoleId: string,
  logger: Logger,
): Effect.Effect<{ parent_role_id: string | null }, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        logger.debug(
          `Setting parent role for child role ${childRoleId} to ${parentRoleId}`,
        );

        // Update the parent_role_id
        const { error } = await supabase
          .from("roles")
          .update({ parent_role_id: parentRoleId })
          .eq("id", childRoleId);

        if (error) {
          throw new Error(`Failed to set parent role: ${error.message}`);
        }

        // Fetch the updated role to get the new parent_role_id
        const { data, error: fetchError } = await supabase
          .from("roles")
          .select("parent_role_id")
          .eq("id", childRoleId)
          .single();

        if (fetchError || !data) {
          throw new Error(
            `Failed to fetch updated role: ${
              fetchError ? fetchError.message : "No data returned"
            }`,
          );
        }

        // Return the updated parent_role_id
        return { parent_role_id: data.parent_role_id };
      },
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to set parent role: ${JSON.stringify(error)}`,
      }),
    }),
    Effect.tap((result) =>
      Effect.sync(() =>
        logger.info(
          `Parent role set for child role ${childRoleId}: ${result.parent_role_id}`,
        ),
      ),
    ),
  );

export const updateUserClaimsCache = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Effect.Effect<void, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        logger.debug(`Updating claims cache for user ${userId}`);
        const result = await supabase
          .schema("keyhippo_rbac")
          .rpc("update_user_claims_cache", {
            p_user_id: userId,
          });
        logger.debug(
          `Result of updating claims cache: ${JSON.stringify(result)}`,
        );
        return result;
      },
      catch: (error): AppError => {
        logger.error(
          `Failed to update claims cache for user ${userId}: ${String(error)}`,
        );
        return {
          _tag: "DatabaseError",
          message: `Failed to update claims cache: ${String(error)}`,
        };
      },
    }),
    Effect.tap(() =>
      Effect.sync(() =>
        logger.info(`Successfully updated claims cache for user ${userId}`),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() =>
        logger.error(`Failed to update claims cache: ${error.message}`),
      ),
    ),
  );

// ABAC Methods

export const createPolicy = (
  supabase: SupabaseClient<any, "public", any>,
  policyName: string,
  description: string,
  policy: any,
  logger: Logger,
): Effect.Effect<void, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        logger.debug(`Creating policy with name ${policyName}`);
        const result = await supabase
          .schema("keyhippo_abac")
          .rpc("create_policy", {
            p_name: policyName,
            p_description: description,
            p_policy: JSON.stringify(policy),
          });
        logger.debug(`Result of creating policy: ${JSON.stringify(result)}`);
        if (result.error) throw result.error;
        return result;
      },
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to create policy: ${JSON.stringify(error)}`,
      }),
    }),
    Effect.tap(() =>
      Effect.sync(() =>
        logger.info(`Successfully created ABAC policy ${policyName}`),
      ),
    ),
  );

export const evaluatePolicies = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  logger: Logger,
): Effect.Effect<boolean, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        logger.debug(`Evaluating policies for user ${userId}`);

        // Log the current user attributes
        const userAttributes = await supabase
          .schema("keyhippo_abac")
          .from("user_attributes")
          .select("attributes")
          .eq("user_id", userId)
          .single();
        logger.debug(`User attributes: ${JSON.stringify(userAttributes.data)}`);

        // Log all policies
        const policies = await supabase
          .schema("keyhippo_abac")
          .from("policies")
          .select("*");
        logger.debug(`All policies: ${JSON.stringify(policies.data)}`);

        const result = await supabase
          .schema("keyhippo_abac")
          .rpc("evaluate_policies", {
            p_user_id: userId,
          });
        logger.debug(
          `Result of evaluating policies: ${JSON.stringify(result)}`,
        );
        if (result.error) throw result.error;
        return result.data as boolean;
      },
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to evaluate policies: ${JSON.stringify(error)}`,
      }),
    }),
    Effect.tap((result) =>
      Effect.sync(() =>
        logger.info(`Policy evaluation result for user ${userId}: ${result}`),
      ),
    ),
  );

export const getUserAttribute = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  attribute: string,
  logger: Logger,
): Effect.Effect<any, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        logger.debug(
          `Retrieving user attribute ${attribute} for user ${userId}`,
        );
        const result = await supabase
          .schema("keyhippo_abac")
          .rpc("get_user_attribute", {
            p_user_id: userId,
            p_attribute: attribute,
          });
        logger.debug(
          `Result of retrieving user attribute: ${JSON.stringify(result)}`,
        );
        return result;
      },
      catch: (error): AppError => {
        logger.error(
          `Failed to retrieve user attribute ${attribute} for user ${userId}: ${String(error)}`,
        );
        return {
          _tag: "DatabaseError",
          message: `Failed to retrieve user attribute: ${String(error)}`,
        };
      },
    }),
    Effect.tap((attributeValue) =>
      Effect.sync(() =>
        logger.info(`User ${userId} attribute ${attribute}: ${attributeValue}`),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() =>
        logger.error(`Failed to retrieve user attribute: ${error.message}`),
      ),
    ),
  );

export const setUserAttribute = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  attribute: string,
  value: any,
  logger: Logger,
): Effect.Effect<void, AppError> =>
  pipe(
    Effect.tryPromise({
      try: async () => {
        logger.debug(`Setting attribute ${attribute} for user ${userId}`);
        const result = await supabase
          .schema("keyhippo_abac")
          .rpc("set_user_attribute", {
            p_user_id: userId,
            p_attribute: attribute,
            p_value: value,
          });
        logger.debug(
          `Result of setting user attribute: ${JSON.stringify(result)}`,
        );
        return result;
      },
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to set user attribute: ${String(error)}`,
      }),
    }),
    Effect.tap(() =>
      Effect.sync(() =>
        logger.info(
          `Successfully set attribute ${attribute} for user ${userId}`,
        ),
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.sync(() =>
        logger.error(`Failed to set user attribute: ${error.message}`),
      ),
    ),
  );
