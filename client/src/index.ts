import { SupabaseClient } from "@supabase/supabase-js";
import {
  createApiKey,
  getAllKeyMetadata,
  loadApiKeySummaries,
  revokeApiKey,
  rotateApiKey,
} from "./api-keys";
import { addUserToGroup, setParentRole, updateUserClaimsCache } from "./rbac";
import {
  createPolicy,
  evaluatePolicies,
  getUserAttribute,
  setUserAttribute,
} from "./abac";
import { authenticate } from "./auth";
import {
  Logger,
  ApiKeyEntity,
  ApiKeySummary,
  ApiKeyMetadata,
  AuthResult,
  UserId,
  ApiKeyId,
  Description,
  RotateApiKeyResult,
  GroupId,
  RoleId,
} from "./types";

/**
 * KeyHippo: API Key Management and Access Control System
 *
 * KeyHippo extends Supabase's Row Level Security (RLS) framework, enabling
 * seamless integration of API key authentication within existing security
 * policies. It addresses the challenge of incorporating API key authentication
 * in Supabase applications without compromising the integrity of Row Level
 * Security.
 *
 * Key features:
 * - Unified RLS policies supporting both session-based and API key
 *   authentication
 * - SQL-based API key issuance
 * - Preservation of existing Supabase RLS implementations
 * - Essential API key lifecycle management
 *
 * KeyHippo ensures that API keys are never stored in any form and cannot be
 * reconstructed, even with access to the database.
 */
export class KeyHippo {
  /**
   * Initializes a new instance of the KeyHippo system.
   *
   * @param supabase - A SupabaseClient instance for database operations. This
   *                   client should be properly configured with the necessary
   *                   permissions to access and modify the KeyHippo schema
   *                   tables.
   * @param logger - An optional logging interface. If not provided, console
   *                 logging is used by default. Custom loggers should implement
   *                 methods for info, warn, error, and debug log levels.
   *
   * The constructor sets up the basic infrastructure for KeyHippo operations.
   * It does not perform any database operations itself, but rather prepares the
   * system for subsequent method calls.
   *
   * Note: Ensure that the Supabase client is initialized with the correct
   * project URL and API key before passing it to the KeyHippo constructor.
   */
  constructor(
    private supabase: SupabaseClient,
    private logger: Logger = console,
  ) {}

  /**
   * Creates a new API key for the autnticated user.
   *
   * @param keyDescription - A human-readable description of the key's purpose
   *                         or context.
   * @returns A Promise resolving to an ApiKeyEntity object containing the generated API key
   *          and its associated metadata.
   *
   * API Key Creation Process:
   * 1. Generates a secure random API key.
   * 2. Creates a new entry in the api_key_metadata table.
   * 3. Stores the hashed key in the api_key_secrets table.
   * 4. Returns the API key and its metadata.
   *
   * Security features:
   * - Each invocation produces a unique key, regardless of input consistency.
   * - The hashing process is cryptographically irreversible.
   * - Database compromise does not allow regeneration or deduction of original API keys.
   *
   * Usage example:
   * ```typescript
   * const apiKeyEntity = await keyHippo.createApiKey(
   *   'Development environment read-only key'
   * );
   * console.log(`New API key created: ${apiKeyEntity.apiKey}`);
   * console.log(`API key ID: ${apiKeyEntity.id}`);
   * ```
   *
   * Note: The generated API key is returned only once and cannot be retrieved
   * later. Ensure it's securely transmitted to the user.
   */
  async createApiKey(keyDescription: Description): Promise<ApiKeyEntity> {
    try {
      return await createApiKey(this.supabase, keyDescription, this.logger);
    } catch (error) {
      this.logger.error(
        `Error creating API key: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Retrieves summary information for all active API keys associated with the current user.
   *
   * @returns A Promise resolving to an array of ApiKeySummary objects.
   *
   * This method retrieves the following information for each API key:
   * - id: The unique identifier for the API key in the database.
   * - description: The human-readable description provided when the key was created.
   *
   * The method performs the following steps:
   * 1. Queries the api_key_metadata table for the current user's active API keys.
   * 2. Processes the returned data to extract the relevant API key information.
   * 3. Logs the operation and any errors that occur during the process.
   *
   * This method is useful for:
   * - Auditing active API keys for the current user
   * - Retrieving key descriptions for display in user interfaces
   * - Preparing data for key management operations
   *
   * Usage example:
   * ```typescript
   * const apiKeys = await keyHippo.loadApiKeySummaries();
   * apiKeys.forEach(key => {
   *   console.log(`Key ID: ${key.id}, Description: ${key.description}`);
   * });
   * ```
   *
   * Note: This method only returns metadata for active (non-revoked) API keys and does not provide access to the
   * actual API key values.
   */
  async loadApiKeySummaries(): Promise<ApiKeySummary[]> {
    try {
      return await loadApiKeySummaries(this.supabase, this.logger);
    } catch (error) {
      this.logger.error(
        `Error loading API key summaries: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Revokes an API key, immediately invalidating it for all future requests.
   *
   * @param apiKeyId - The unique identifier of the API key to be revoked.
   * @returns A Promise that resolves to a boolean indicating whether the key was successfully revoked.
   *
   * Revocation process:
   * 1. Calls the 'revoke_api_key' function with the authenticated userId and apiKeyId.
   * 2. Verifies that the API key belongs to the specified user.
   * 3. Updates the key's is_revoked status to true in the database.
   * 4. Logs the revocation event for audit purposes.
   *
   * Security implications:
   * - Revocation takes effect immediately for new requests.
   * - Requests in progress at the time of revocation will complete.
   * - Revoked keys cannot be reinstated; a new key must be created if access is required again.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const revoked = await keyHippo.revokeApiKey('apiKey456');
   *   if (revoked) {
   *     console.log('API key successfully revoked');
   *   } else {
   *     console.log('API key not found or already revoked');
   *   }
   * } catch (error) {
   *   console.error('Failed to revoke API key:', error);
   * }
   * ```
   *
   * Error handling:
   * - Returns false if the API key doesn't exist or doesn't belong to the user.
   * - Throws an error if there are database connectivity issues.
   *
   * Note: It's recommended to implement monitoring for failed API key usage
   * attempts to detect and respond to potential security incidents.
   */
  async revokeApiKey(apiKeyId: ApiKeyId): Promise<boolean> {
    try {
      return await revokeApiKey(this.supabase, apiKeyId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error revoking API key: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Retrieves comprehensive metadata for all API keys belonging to a user.
   *
   * @param userId - The unique identifier of the user whose API keys are being queried.
   * @returns A Promise resolving to an array of ApiKeyMetadata objects.
   *
   * This method provides an extensive overview of each API key, including:
   * - id: The unique identifier for the API key
   * - description: The human-readable description of the key
   * - created_at: Timestamp of the key's creation
   * - last_used_at: Timestamp of the key's last usage
   * - expires_at: Timestamp when the key will expire
   * - is_revoked: Boolean indicating if the key has been revoked
   *
   * The method performs the following steps:
   * 1. Queries the api_key_metadata table for the specified user.
   * 2. Processes the returned data to extract the comprehensive API key information.
   * 3. Logs the operation and any errors that occur during the process.
   *
   * Use cases:
   * - Performing security audits
   * - Analyzing API usage patterns
   * - Monitoring key status and expiration
   * - Identifying unused or potentially compromised keys
   *
   * Usage example:
   * ```typescript
   * const keyMetadata = await keyHippo.getAllKeyMetadata('user123');
   * keyMetadata.forEach(key => {
   *   console.log(`Key ID: ${key.id}, Last Used: ${key.last_used_at}, Expires: ${key.expires_at}`);
   * });
   * ```
   *
   * Note: This method provides a comprehensive view of key metadata, which can be
   * valuable for both security and operational purposes.
   */
  async getAllKeyMetadata(userId: UserId): Promise<ApiKeyMetadata[]> {
    try {
      return await getAllKeyMetadata(this.supabase, userId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error getting API key metadata: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Rotates an existing API key.
   *
   * @param apiKeyId - The ID of the API key to rotate.
   * @returns A promise that resolves with the information of the rotated API key.
   * @throws Error if the rotation process fails.
   *
   * This method performs the following steps:
   * 1. Calls the rotate_api_key RPC function with the provided API key ID.
   * 2. Revokes the old API key and creates a new one with the same description.
   * 3. Returns the new API key information.
   *
   * Usage example:
   * ```typescript
   * const rotatedKey = await keyHippo.rotateApiKey('old-api-key-id');
   * console.log(`New API Key: ${rotatedKey.apiKey}, New ID: ${rotatedKey.id}`);
   * ```
   *
   * Note: This method will fail if the user is not authenticated or if they don't own the API key being rotated.
   */
  async rotateApiKey(apiKeyId: ApiKeyId): Promise<RotateApiKeyResult> {
    try {
      return await rotateApiKey(this.supabase, apiKeyId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error rotating API key: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Authenticates a user based on the provided request headers.
   *
   * @param headers - The HTTP headers from the incoming request, typically
   *                  containing the KeyHippo API key or session credentials.
   * @returns A Promise resolving to an AuthResult object containing the authenticated user context
   *          and an authenticated Supabase client.
   *
   * Authentication process:
   * 1. Extracts the API key from the Authorization header (Bearer token).
   * 2. If an API key is present:
   *    a. Creates an authenticated Supabase client with the API key.
   *    b. Calls the 'current_user_context' RPC function to validate the API key and retrieve the associated user context.
   *    c. If valid, returns the user context and the authenticated Supabase client.
   * 3. If no API key is provided, it attempts session-based authentication:
   *    a. Uses the existing Supabase client to call the 'current_user_context' RPC function.
   *    b. If the user is authenticated, returns the user context and the existing Supabase client.
   * 4. If neither API key nor session authentication succeeds, throws an error.
   *
   * Security considerations:
   * - API keys should be transmitted securely (e.g., over HTTPS).
   * - Failed authentication attempts are logged with request details.
   * - Implement rate limiting to prevent brute-force attacks on API keys.
   *
   * Usage example:
   * ```typescript
   * const headers = new Headers({
   *   'Authorization': 'Bearer LntFjMwR8s0jjjVzampW6zXA...'
   * });
   * try {
   *   const { auth, supabase } = await keyHippo.authenticate(headers);
   *   console.log(`Authenticated user: ${auth.user_id}`);
   *   console.log(`User permissions: ${auth.permissions}`);
   *   // Use the authenticated Supabase client for further operations
   * } catch (error) {
   *   console.error('Authentication failed:', error.message);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if authentication fails due to an invalid KeyHippo API key,
   *   missing session, or other issues.
   * - All authentication errors are logged before being re-thrown.
   *
   * Note: This method supports both API key-based authentication and
   * session-based authentication, providing a unified interface for both methods.
   */
  async authenticate(headers: Headers): Promise<AuthResult> {
    try {
      return await authenticate(headers, this.supabase, this.logger);
    } catch (error) {
      this.logger.error(
        `Authentication failed: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Adds a user to a specified group with a given role.
   *
   * @param userId - The unique identifier of the user being added to the group.
   * @param groupId - The unique identifier of the group to which the user will be added.
   * @param roleName - The name of the role that the user will be assigned within the group.
   * @returns A Promise resolving to void when the user has been successfully added to the group.
   *
   * Adding a user to a group involves the following steps:
   * 1. Calls the 'assign_role_to_user' function with the provided userId, groupId, and roleName.
   * 2. Verifies that the group and role exist in the RBAC schema.
   * 3. Assigns the user to the specified role within the group.
   * 4. Updates the user's claims cache to reflect the new role assignment.
   * 5. Logs the group addition for audit purposes.
   *
   * Security implications:
   * - Ensure that only authorized administrators have the ability to assign users to groups and roles.
   * - This operation affects the user's permissions, so it should be carefully controlled.
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.addUserToGroup('user123', 'group456', 'admin');
   *   console.log('User successfully added to group with specified role');
   * } catch (error) {
   *   console.error('Failed to add user to group:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the group or role does not exist.
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the user is already assigned to the role in the group.
   */
  async addUserToGroup(
    userId: UserId,
    groupId: GroupId,
    roleName: string,
  ): Promise<void> {
    try {
      await addUserToGroup(
        this.supabase,
        userId,
        groupId,
        roleName,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error adding user to group: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Sets a parent role for a specified child role.
   *
   * @param childRoleId - The unique identifier of the child role.
   * @param parentRoleId - The unique identifier of the parent role.
   * @returns A Promise resolving to an object containing the new parent_role_id, or null if cleared.
   *
   * This operation establishes or modifies a hierarchical relationship between roles:
   * 1. Calls the 'set_parent_role' function with the provided childRoleId and parentRoleId.
   * 2. If parentRoleId is null, it removes the current parent role (if any).
   * 3. If parentRoleId is provided, it sets the specified role as the parent of the child role.
   * 4. Ensures that the parent role inherits permissions granted to the child role.
   * 5. Logs the role hierarchy update for auditing purposes.
   *
   * Security implications:
   * - Role hierarchies allow for streamlined permission management but must be used cautiously to prevent privilege escalation.
   * - Ensure that only authorized users have the ability to modify role hierarchies.
   * - Circular dependencies in role hierarchies are prevented by the database function.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const result = await keyHippo.setParentRole('childRole123', 'parentRole456');
   *   console.log('Parent role successfully set:', result.parent_role_id);
   * } catch (error) {
   *   console.error('Failed to set parent role:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the role IDs do not exist.
   * - Throws an error if setting the parent role would create a circular dependency.
   * - Throws an error if there are database connectivity issues.
   */
  /* // TODO
  async setParentRole(
    childRoleId: RoleId,
    parentRoleId: RoleId|null,
  ): Promise<{ parent_role_id: RoleId }> {
    try {
      return await setParentRole(
        this.supabase,
        childRoleId,
        parentRoleId,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error setting parent role: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }
  */

  /**
   * Updates the claims cache for a specified user, ensuring their role-based claims are up-to-date.
   *
   * @param userId - The unique identifier of the user whose claims cache needs to be updated.
   * @returns A Promise resolving to void when the claims cache has been successfully updated.
   *
   * This operation is necessary to reflect changes in a user's group memberships or role assignments:
   * 1. Calls the 'update_user_claims_cache' function with the provided userId.
   * 2. Retrieves all current group memberships and role assignments for the user.
   * 3. Constructs a new claims object based on the user's current roles and group memberships.
   * 4. Updates the claims_cache table with the new claims for the user.
   * 5. Logs the cache update for auditing purposes.
   *
   * Use cases:
   * - This method should be called after any significant changes in the user's permissions or role assignments.
   * - It's crucial for keeping the user's effective permissions in sync with their assigned roles.
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.updateUserClaimsCache('user123');
   *   console.log('User claims cache updated successfully');
   * } catch (error) {
   *   console.error('Failed to update user claims cache:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the user does not exist.
   * - Throws an error if there are database connectivity issues.
   *
   * Note: This method is automatically called by other methods that modify user roles or group memberships,
   * but it can also be called manually if needed.
   */
  async updateUserClaimsCache(userId: UserId): Promise<void> {
    try {
      await updateUserClaimsCache(this.supabase, userId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error updating user claims cache: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Creates a new ABAC (Attribute-Based Access Control) policy.
   *
   * @param policyName - The unique name of the policy being created.
   * @param description - A human-readable description of the policy's purpose.
   * @param policy - A JSON object defining the policy rules and conditions.
   * @returns A Promise resolving to void when the policy has been successfully created.
   *
   * Policy creation process:
   * 1. Calls the 'create_policy' function with the provided policyName, description, and policy object.
   * 2. Validates the policy object structure and content.
   * 3. Stores the policy in the ABAC schema for future evaluations.
   * 4. Logs the creation of the policy for auditing purposes.
   *
   * Security implications:
   * - ABAC policies provide dynamic access control based on user attributes and request context.
   * - Ensure that only trusted administrators can define or modify policies.
   * - Poorly defined policies can lead to unintended access or restrictions.
   *
   * Usage example:
   * ```typescript
   * const policy = {
   *   attribute: 'department',
   *   value: 'engineering',
   *   type: 'attribute_equals'
   * };
   * try {
   *   await keyHippo.createPolicy('EngineeringAccessPolicy', 'Grants access to engineering department', policy);
   *   console.log('Policy successfully created');
   * } catch (error) {
   *   console.error('Failed to create policy:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the policy creation fails due to validation issues.
   * - Throws an error if a policy with the same name already exists.
   * - Throws an error if there are database connectivity issues.
   *
   * Note: Policies should be carefully designed and tested to ensure they provide the intended access control.
   */
  async createPolicy(
    policyName: string,
    description: string,
    policy: any,
  ): Promise<void> {
    try {
      await createPolicy(
        this.supabase,
        policyName,
        description,
        policy,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error creating policy: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Evaluates ABAC policies for a specified user, determining if access is granted.
   *
   * @param userId - The unique identifier of the user whose policies are being evaluated.
   * @returns A Promise resolving to a boolean indicating whether access is granted.
   *
   * Policy evaluation process:
   * 1. Calls the 'evaluate_policies' function with the provided userId.
   * 2. Retrieves all applicable ABAC policies.
   * 3. Fetches the user's attributes from the user_attributes table.
   * 4. Applies each policy's conditions against the user's attributes.
   * 5. Returns true if all policies pass, false otherwise.
   * 6. Logs the result of the evaluation for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const hasAccess = await keyHippo.evaluatePolicies('user123');
   *   if (hasAccess) {
   *     console.log('Access granted');
   *   } else {
   *     console.log('Access denied');
   *   }
   * } catch (error) {
   *   console.error('Error evaluating policies:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that policy rules are properly defined to prevent unauthorized access.
   * - Consider the performance impact of policy evaluation, especially with a large number of policies.
   *
   * Error handling:
   * - Throws an error if the evaluation fails due to database connectivity issues.
   * - Throws an error if the user does not exist.
   * - Returns false if there are no applicable policies for the user.
   *
   * Note: This method evaluates all policies. For fine-grained control, consider implementing
   * policy evaluation for specific resources or actions.
   */
  async evaluatePolicies(userId: UserId): Promise<boolean> {
    try {
      return await evaluatePolicies(this.supabase, userId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error evaluating policies: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Retrieves a specific attribute for a given user from the ABAC system.
   *
   * @param userId - The unique identifier of the user whose attribute is being retrieved.
   * @param attribute - The name of the attribute to retrieve.
   * @returns A Promise resolving to the value of the requested attribute, or null if not found.
   *
   * Attribute retrieval process:
   * 1. Calls the 'get_user_attribute' function with the provided userId and attribute name.
   * 2. Retrieves the attribute value from the user_attributes table in the ABAC schema.
   * 3. Logs the retrieval operation for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const departmentValue = await keyHippo.getUserAttribute('user123', 'department');
   *   console.log(`User department: ${departmentValue}`);
   * } catch (error) {
   *   console.error('Error getting user attribute:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized users can retrieve sensitive attributes.
   * - Consider implementing attribute-level access control if needed.
   *
   * Error handling:
   * - Returns null if the attribute does not exist for the user.
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the user does not exist.
   *
   * Note: This method retrieves a single attribute. For retrieving multiple attributes,
   * consider implementing a batch retrieval method.
   */
  async getUserAttribute(userId: UserId, attribute: string): Promise<any> {
    try {
      return await getUserAttribute(
        this.supabase,
        userId,
        attribute,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error getting user attribute: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }
  /**
   * Sets a user attribute in the ABAC system.
   *
   * @param userId - The unique identifier of the user whose attribute is being set.
   * @param attribute - The name of the attribute to set for the user.
   * @param value - The value of the attribute to assign.
   * @returns A Promise resolving to void when the attribute has been successfully set.
   *
   * Attribute setting process:
   * 1. Calls the 'set_user_attribute' function with the provided userId, attribute, and value.
   * 2. If the attribute doesn't exist for the user, it creates a new entry.
   * 3. If the attribute already exists, it updates the existing value.
   * 4. Stores or updates the attribute in the user_attributes table in the ABAC schema.
   * 5. Logs the operation for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.setUserAttribute('user123', 'department', 'engineering');
   *   console.log('User attribute set successfully');
   * } catch (error) {
   *   console.error('Error setting user attribute:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized users can modify sensitive attributes.
   * - Consider implementing attribute-level access control for write operations.
   * - Be cautious about allowing users to set their own attributes, as this could potentially be abused.
   *
   * Error handling:
   * - Throws an error if the attribute cannot be set due to database constraints.
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the user does not exist.
   *
   * Note: This method sets a single attribute. For setting multiple attributes at once,
   * consider implementing a batch update method.
   */
  async setUserAttribute(
    userId: UserId,
    attribute: string,
    value: any,
  ): Promise<void> {
    try {
      await setUserAttribute(
        this.supabase,
        userId,
        attribute,
        value,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error setting user attribute: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }
}
