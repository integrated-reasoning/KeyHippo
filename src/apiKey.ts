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
        supabase.rpc("create_api_key", {
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
      Effect.tryPromise({
        try: () =>
          supabase.rpc("get_api_key", {
            id_of_user: userId,
            secret_id: keyInfo.id,
          }),
        catch: (error): AppError => ({
          _tag: "DatabaseError",
          message: `Failed to retrieve API key: ${String(error)}`,
        }),
      }),
    ),
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
          id: uniqueId,
          description: uniqueDescription,
          apiKey: response.data,
          status: "success",
        };
      },
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
): Effect.Effect<ApiKeyInfo[], AppError> =>
  pipe(
    Effect.tryPromise({
      try: () => supabase.rpc("load_api_key_info", { id_of_user: userId }),
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to load API key info: ${String(error)}`,
      }),
    }),
    Effect.flatMap((result: any) => {
      if (result.error) {
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: `Error loading API key info: ${result.error.message}`,
        });
      }
      if (!Array.isArray(result.data)) {
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: "Invalid data returned when loading API key info",
        });
      }
      try {
        const parsedData = result.data.map((item: unknown) => {
          if (typeof item !== "string") {
            throw new Error("Invalid item type in API key info");
          }
          const parsed = JSON.parse(item);
          if (!("id" in parsed) || !("description" in parsed)) {
            throw new Error("Invalid API key info structure");
          }
          return parsed as ApiKeyInfo;
        });
        return Effect.succeed(parsedData);
      } catch (error) {
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
      Effect.sync(() =>
        logger.error(`Failed to load API key info: ${error.message}`),
      ),
    ),
  );

export const revokeApiKey = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  secretId: string,
  logger: Logger,
): Effect.Effect<void, AppError> =>
  pipe(
    Effect.tryPromise({
      try: () =>
        supabase.rpc("revoke_api_key", {
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
        return supabase.rpc("get_api_key_metadata", { p_user_id: userId });
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
        api_key_reference: item.api_key_reference,
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
