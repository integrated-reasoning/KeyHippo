import { SupabaseClient } from "@supabase/supabase-js";
import { Effect } from "effect";
import { v4 as uuidv4 } from "uuid";
import {
  addUserToGroup as addUserToGroupEffect,
  createPolicy as createPolicyEffect,
  evaluatePolicies as evaluatePoliciesEffect,
  getUserAttribute as getUserAttributeEffect,
  setParentRole as setParentRoleEffect,
  updateUserClaimsCache as updateUserClaimsCacheEffect,
  createApiKey as createApiKeyEffect,
  loadApiKeyInfo as loadApiKeyInfoEffect,
  revokeApiKey as revokeApiKeyEffect,
  rotateApiKey as rotateApiKeyEffect,
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

  async rotateApiKey(userId: string, apiKeyId: string) {
    return Effect.runPromise(
      Effect.catchAll(
        rotateApiKeyEffect(this.supabase, userId, apiKeyId, this.logger),
        (error: AppError) =>
          Effect.fail(`Error rotating API key: ${error.message}`),
      ),
    );
  }

  async authenticate(headers: Headers) {
    return Effect.runPromise(
      authenticateEffect(headers, this.supabase, this.logger),
    );
  }

  // RBAC methods
  async addUserToGroup(userId: string, groupId: string, roleName: string) {
    return Effect.runPromise(
      Effect.catchAll(
        addUserToGroupEffect(
          this.supabase,
          userId,
          groupId,
          roleName,
          this.logger,
        ),
        (error: AppError) =>
          Effect.fail(`Error adding user to group: ${error.message}`),
      ),
    );
  }

  async setParentRole(childRoleId: string, parentRoleId: string) {
    return Effect.runPromise(
      Effect.catchAll(
        setParentRoleEffect(
          this.supabase,
          childRoleId,
          parentRoleId,
          this.logger,
        ),
        (error: AppError) =>
          Effect.fail(`Error setting parent role: ${error.message}`),
      ),
    );
  }

  async updateUserClaimsCache(userId: string) {
    return Effect.runPromise(
      updateUserClaimsCacheEffect(this.supabase, userId, this.logger),
    );
  }

  // ABAC methods
  async createPolicy(policyName: string, description: string, policy: any) {
    return Effect.runPromise(
      Effect.catchAll(
        createPolicyEffect(
          this.supabase,
          policyName,
          description,
          policy,
          this.logger,
        ),
        (error: AppError) =>
          Effect.fail(`Error creating policy: ${error.message}`),
      ),
    );
  }

  async evaluatePolicies(userId: string) {
    return Effect.runPromise(
      Effect.catchAll(
        evaluatePoliciesEffect(this.supabase, userId, this.logger),
        (error: AppError) =>
          Effect.fail(`Error evaluating policies: ${error.message}`),
      ),
    );
  }

  async getUserAttribute(userId: string, attribute: string) {
    return Effect.runPromise(
      Effect.catchAll(
        getUserAttributeEffect(this.supabase, userId, attribute, this.logger),
        (error: AppError) =>
          Effect.fail(`Error retrieving user attribute: ${error.message}`),
      ),
    );
  }
}
