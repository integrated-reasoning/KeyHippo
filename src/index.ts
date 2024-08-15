import { SupabaseClient, createClient } from "@supabase/supabase-js";
import { Effect } from "effect";
import {
  createApiKey,
  loadApiKeyInfo,
  revokeApiKey,
  getAllKeyMetadata,
} from "./apiKey";
import { authenticate } from "./auth";
import { KeyHippoConfig, Logger } from "./types";

export * from "./types";

export class KeyHippo {
  private supabase: SupabaseClient;
  private logger: Logger;

  constructor(config: KeyHippoConfig) {
    this.supabase = createClient(config.supabaseUrl, config.supabaseAnonKey);
    this.logger = config.logger || console;
  }

  createApiKey(userId: string, keyDescription: string) {
    return Effect.runPromise(
      createApiKey(this.supabase, userId, keyDescription, this.logger),
    );
  }

  loadApiKeyInfo(userId: string) {
    return Effect.runPromise(
      loadApiKeyInfo(this.supabase, userId, this.logger),
    );
  }

  revokeApiKey(userId: string, secretId: string) {
    return Effect.runPromise(
      revokeApiKey(this.supabase, userId, secretId, this.logger),
    );
  }

  getAllKeyMetadata(userId: string) {
    return Effect.runPromise(
      getAllKeyMetadata(this.supabase, userId, this.logger),
    );
  }

  authenticate(request: Request) {
    return Effect.runPromise(authenticate(request, this.supabase, this.logger));
  }
}
