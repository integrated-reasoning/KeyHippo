import { Effect, pipe } from "effect";
import { PostgrestSingleResponse } from "@supabase/supabase-js";
import { SupabaseClient } from "@supabase/supabase-js";
import { v4 as uuidv4 } from "uuid";
import {
  ApiKeyInfo,
  CompleteApiKeyInfo,
  AppError,
  ApiKeyMetadata,
} from "./types";

export const createApiKey = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  keyDescription: string,
): Effect.Effect<CompleteApiKeyInfo, AppError> => {
  // This should only ever be called during key creation.
  const getApiKey = (
    supabase: SupabaseClient<any, "public", any>,
    userId: string,
    secretId: string,
  ): Effect.Effect<string, AppError> =>
    pipe(
      Effect.tryPromise({
        try: () =>
          supabase.rpc("get_api_key", {
            id_of_user: userId,
            secret_id: secretId,
          }),
        catch: (error): AppError => ({
          _tag: "DatabaseError",
          message: `Failed to get API key: ${String(error)}`,
        }),
      }),
      Effect.flatMap((result: any) => {
        if (result.error) {
          return Effect.fail<AppError>({
            _tag: "DatabaseError",
            message: `Error getting API key: ${result.error.message}`,
          });
        }

        if (typeof result.data !== "string" || result.data.trim() === "") {
          console.error("Invalid or empty API key returned:", result.data);
          return Effect.fail<AppError>({
            _tag: "DatabaseError",
            message: "Invalid or empty API key returned",
          });
        }
        return Effect.succeed(result.data);
      }),
      Effect.tapError((error) =>
        Effect.logError(
          `Failed to get API key: ${JSON.stringify(error, null, 2)}`,
        ),
      ),
    );
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
    Effect.flatMap(() => loadApiKeyInfo(supabase, userId)),
    Effect.tap((keyInfos) =>
      Effect.logInfo(`Loaded key info: ${JSON.stringify(keyInfos)}`),
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
    Effect.flatMap((createdKeyInfo) =>
      pipe(
        getApiKey(supabase, userId, createdKeyInfo.id),
        Effect.map(
          (apiKey): CompleteApiKeyInfo => ({
            ...createdKeyInfo,
            apiKey, // Key creation is the one and only time we return a key.
            status: "success",
          }),
        ),
        Effect.catchAll((error) =>
          Effect.succeed<CompleteApiKeyInfo>({
            ...createdKeyInfo,
            apiKey: null,
            status: "failed",
            error: error.message,
          }),
        ),
      ),
    ),
    Effect.tap((completeKeyInfo: CompleteApiKeyInfo) =>
      Effect.logInfo(
        `New API key created for user: ${userId}, Key ID: ${completeKeyInfo.id}`,
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.logError(`Failed to create new API key: ${error.message}`),
    ),
  );
};

export const loadApiKeyInfo = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
): Effect.Effect<ApiKeyInfo[], AppError> =>
  pipe(
    Effect.tryPromise({
      try: () => supabase.rpc("load_api_key_info", { id_of_user: userId }),
      catch: (error): AppError => ({
        _tag: "DatabaseError",
        message: `Failed to load API key info: ${String(error)}`,
      }),
    }),
    Effect.flatMap((result: PostgrestSingleResponse<unknown>) => {
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
      Effect.logInfo(
        `API key info loaded for user: ${userId}. Count: ${apiKeyInfo.length}`,
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.logError(`Failed to load API key info: ${error.message}`),
    ),
  );

export const revokeApiKey = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
  secretId: string,
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
      Effect.logInfo(
        `API key revoked for user: ${userId}, Secret ID: ${secretId}`,
      ),
    ),
    Effect.tapError((error: AppError) =>
      Effect.logError(`Failed to revoke API key: ${error.message}`),
    ),
  );

export const getAllKeyMetadata = (
  supabase: SupabaseClient<any, "public", any>,
  userId: string,
): Effect.Effect<ApiKeyMetadata[], AppError> =>
  pipe(
    Effect.tryPromise({
      try: () => {
        console.log(`Calling get_api_key_metadata RPC for user: ${userId}`);
        console.log(
          `RPC call parameters: ${JSON.stringify({ p_user_id: userId })}`,
        );
        return supabase.rpc("get_api_key_metadata", { p_user_id: userId });
      },
      catch: (error): AppError => {
        console.error(`Error in RPC call: ${String(error)}`);
        return {
          _tag: "DatabaseError",
          message: `Failed to get API key metadata: ${String(error)}`,
        };
      },
    }),
    Effect.tap((result: any) => {
      console.log(`RPC result: ${JSON.stringify(result)}`);
      return Effect.logDebug(`RPC result: ${JSON.stringify(result)}`);
    }),
    Effect.flatMap((result: any) => {
      if (result.error) {
        console.error(`Database error: ${result.error.message}`);
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: `Error getting API key metadata: ${result.error.message}`,
        });
      }
      console.log(`Raw data from database: ${JSON.stringify(result.data)}`);
      if (!Array.isArray(result.data)) {
        console.error(`Invalid data structure: ${JSON.stringify(result.data)}`);
        return Effect.fail<AppError>({
          _tag: "DatabaseError",
          message: "Invalid data returned when getting API key metadata",
        });
      }
      const metadata: ApiKeyMetadata[] = result.data.map((item: any) => {
        console.log(`Processing item: ${JSON.stringify(item)}`);
        return {
          api_key_reference: item.api_key_reference,
          name: item.name || "",
          permission: item.permission || "",
          last_used: item.last_used,
          created: item.created,
          revoked: item.revoked,
          total_uses: Number(item.total_uses),
          success_rate: Number(item.success_rate),
          total_cost: Number(item.total_cost),
        };
      });
      console.log(`Processed metadata: ${JSON.stringify(metadata)}`);
      return Effect.succeed(metadata);
    }),
    Effect.tap((metadata: ApiKeyMetadata[]) =>
      Effect.logInfo(`API key metadata retrieved. Count: ${metadata.length}`),
    ),
    Effect.tapError((error: AppError) =>
      Effect.logError(
        `Failed to get API key metadata: ${JSON.stringify(error)}`,
      ),
    ),
  );
