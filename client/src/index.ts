import { SupabaseClient } from "@supabase/supabase-js";
import { Effect } from "effect";
import { v4 as uuidv4 } from "uuid";
import {
  createApiKey as createApiKeyEffect,
  loadApiKeyInfo as loadApiKeyInfoEffect,
  revokeApiKey as revokeApiKeyEffect,
  getAllKeyMetadata as getAllKeyMetadataEffect,
} from "./apiKey";
import { authenticate as authenticateEffect } from "./auth";
import { Logger, AppError } from "./types";

export class KeyHippo {
  constructor(
    private supabase: SupabaseClient,
    private logger: Logger = console,
  ) {}

  async createApiKey(userId: string, keyDescription: string) {
    const uniqueId = uuidv4();
    const uniqueDescription = `${uniqueId}-${keyDescription}`;
    return Effect.runPromise(
      Effect.catchAll(
        createApiKeyEffect(
          this.supabase,
          userId,
          uniqueDescription,
          this.logger,
        ),
        (error: AppError) =>
          Effect.fail(`Error creating API key: ${error.message}`),
      ),
    );
  }

  async loadApiKeyInfo(userId: string) {
    return Effect.runPromise(
      loadApiKeyInfoEffect(this.supabase, userId, this.logger),
    );
  }

  async revokeApiKey(userId: string, secretId: string) {
    return Effect.runPromise(
      revokeApiKeyEffect(this.supabase, userId, secretId, this.logger),
    );
  }

  async getAllKeyMetadata(userId: string) {
    return Effect.runPromise(
      Effect.catchAll(
        getAllKeyMetadataEffect(this.supabase, userId, this.logger),
        (error: AppError) =>
          Effect.fail(`Error getting API key metadata: ${error.message}`),
      ),
    );
  }

  async authenticate(headers: Headers) {
    return Effect.runPromise(
      authenticateEffect(headers, this.supabase, this.logger),
    );
  }
}
