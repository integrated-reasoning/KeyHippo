import { SupabaseClient } from "@supabase/supabase-js";
import {
  createApiKey,
  getAllKeyMetadata,
  loadApiKeySummaries,
  revokeApiKey,
  rotateApiKey,
} from "./api-keys";
import {
  assignPermissionToRole,
  addUserToGroup,
  removeUserFromGroup,
  createRole,
  createGroup,
  createPermission,
  deleteGroup,
  deletePermission,
  getGroup,
  getParentRole,
  setParentRole,
  getRolePermissions,
  updateGroup,
  updateUserClaimsCache,
  userHasPermission,
} from "./rbac";
import {
  checkAbacPolicy,
  createPolicy,
  deletePolicy,
  evaluatePolicies,
  getGroupAttribute,
  getPolicy,
  getUserAttribute,
  setGroupAttribute,
  setUserAttribute,
  updatePolicy,
} from "./abac";
import { authenticate } from "./auth";
import {
  ApiKeyEntity,
  ApiKeyId,
  ApiKeyMetadata,
  ApiKeySummary,
  AuthResult,
  Description,
  GroupId,
  Logger,
  PermissionId,
  PermissionName,
  Policy,
  PolicyId,
  RoleId,
  RotateApiKeyResult,
  UserId,
} from "./types";

/* TODO: Add:
3. RBAC (Role-Based Access Control):
   - removePermissionFromRole

4. Utils:
   - No missing functions

5. Root level:
   - createGroup
   - updateGroup
   - deleteGroup
   - getGroup
   - createPermission
   - updatePermission
   - deletePermission
   - getPermission
   - createScope
   - updateScope
   - deleteScope
   - getScope
   - addPermissionToScope
   - removePermissionFromScope
   - getScopePermissions
*/

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
   * Creates a new API key for the authenticated user.
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
    const hasPermission = await this.userHasPermission("rotate_api_key");
    if (!hasPermission) {
      throw new Error(
        "Unauthorized: User does not have permission to rotate API keys",
      );
    }
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
   * Assigns a permission to a role in the RBAC system.
   *
   * @param roleId - The unique identifier of the role to which the permission is being assigned.
   * @param permissionName - The name of the permission to be assigned.
   * @returns A Promise that resolves when the assignment is successful.
   *
   * Permission assignment process:
   * 1. Validates the input parameters.
   * 2. Checks if the role and permission exist.
   * 3. Creates an entry in the role_permissions table within the RBAC schema.
   * 4. Handles potential conflicts (e.g., if the permission is already assigned to the role).
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.assignPermissionToRole('role123', 'READ_DOCUMENTS');
   *   console.log('Permission successfully assigned to role');
   * } catch (error) {
   *   console.error('Failed to assign permission to role:', error);
   * }
   * ```

   *
   * Security implications:
   * - Ensure that only authorized administrators can assign permissions to roles.
   * - Assigning permissions affects the overall access control structure of the application.
   * - Consider implementing an audit log for permission assignments.
   *
   * Error handling:
   * - Throws an error if the role or permission does not exist.
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the permission is already assigned to the role.
   */
  async assignPermissionToRole(
    roleId: RoleId,
    permissionName: PermissionName,
  ): Promise<void> {
    try {
      await assignPermissionToRole(
        this.supabase,
        roleId,
        permissionName,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error assigning permission to role: ${error instanceof Error ? error.message : String(error)}`,
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
   * Removes a user from a group in the RBAC system.
   *
   * @param userId - The unique identifier of the user to be removed from the group.
   * @param groupId - The unique identifier of the group from which the user is being removed.
   * @returns A Promise that resolves when the removal is successful.
   *
   * User removal process:
   * 1. Validates the input parameters.
   * 2. Checks if the user is a member of the specified group.
   * 3. Removes the user-group association from the user_groups table within the RBAC schema.
   * 4. Handles potential cascading effects (e.g., removing associated roles or permissions).
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.removeUserFromGroup('user123', 'group456');
   *   console.log('User successfully removed from group');
   * } catch (error) {
   *   console.error('Failed to remove user from group:', error);
   * }
   * ```

   *
   * Security implications:
   * - Ensure that only authorized administrators can remove users from groups.
   * - Removing a user from a group affects their access rights within the application.
   * - Consider implementing an audit log for user-group removals.
   *
   * Error handling:
   * - Throws an error if the user or group does not exist.
   * - Throws an error if the user is not a member of the specified group.
   * - Throws an error if there are database connectivity issues.
   */
  async removeUserFromGroup(userId: UserId, groupId: GroupId): Promise<void> {
    try {
      await removeUserFromGroup(this.supabase, userId, groupId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error removing user from group: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Retrieves the parent role of a specified role in the RBAC system.
   *
   * @param roleId - The unique identifier of the role whose parent is being retrieved.
   * @returns A Promise resolving to the parent role ID or null if no parent role exists.
   *
   * Parent role retrieval process:
   * 1. Validates the input parameter.
   * 2. Queries the roles table within the RBAC schema for the specified role.
   * 3. Returns the parent_role_id if found, or null if the role has no parent.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const parentRoleId = await keyHippo.getParentRole('role123');
   *   if (parentRoleId) {
   *     console.log(`Parent role ID: ${parentRoleId}`);
   *   } else {
   *     console.log('This role has no parent role.');
   *   }
   * } catch (error) {
   *   console.error('Failed to retrieve parent role:', error);
   * }
   * ```

   *
   * Security implications:
   * - Ensure that only authorized users or systems can retrieve role hierarchies.
   * - Be cautious about exposing the full role hierarchy to prevent potential misuse.
   *
   * Error handling:
   * - Throws an error if the role retrieval fails due to database issues.
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the specified role does not exist.
   * - Returns null if the role exists but has no parent (does not throw an error).
   */
  async getParentRole(roleId: RoleId): Promise<RoleId | null> {
    try {
      return await getParentRole(this.supabase, roleId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error retrieving parent role: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Sets a parent role for a specified child role.
   *
   * @param childRoleId - The unique identifier of the child role.
   * @param parentRoleId - The unique identifier of the parent role, or null to remove the parent role.
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
  async setParentRole(
    childRoleId: RoleId,
    parentRoleId: RoleId | null,
  ): Promise<{ parent_role_id: RoleId | null }> {
    try {
      const result = await setParentRole(
        this.supabase,
        childRoleId,
        parentRoleId,
        this.logger,
      );
      this.logger.info(`setParentRole result: ${JSON.stringify(result)}`);
      return result;
    } catch (error) {
      this.logger.error(
        `Error setting parent role: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

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
   * Checks an ABAC policy for a specific user in the system.
   *
   * @param userId - The unique identifier of the user to check against the policy.
   * @param policy - The policy object to evaluate.
   * @returns A Promise resolving to a boolean indicating whether the policy check passed.
   *
   * Policy check process:
   * 1. Retrieves the user's attributes from the user_attributes table.
   * 2. Evaluates the policy based on its type (and, or, attribute_equals, attribute_contains, attribute_contained_by).
   * 3. Returns true if the policy check passes, false otherwise.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const policy = { type: 'attribute_equals', attribute: 'role', value: 'admin' };
   *   const policyPassed = await keyHippo.checkAbacPolicy('user123', policy);
   *   console.log(`Policy check result: ${policyPassed ? 'PASS' : 'FAIL'}`);
   * } catch (error) {
   *   console.error('Failed to check ABAC policy:', error);
   * }
   * ```

   *
   * Security implications:
   * - This function is crucial for enforcing access control decisions.
   * - Ensure that policies are properly designed and tested to avoid unintended access.
   * - Consider caching frequently checked policies or user attributes for performance.
   *
   * Error handling:
   * - Throws an error if the user does not exist or has no attributes.
   * - Throws an error if the policy type is unsupported.
   * - Throws an error if there are database connectivity issues.
   */
  async checkAbacPolicy(userId: UserId, policy: Policy): Promise<boolean> {
    try {
      return await checkAbacPolicy(this.supabase, userId, policy, this.logger);
    } catch (error) {
      this.logger.error(
        `Error checking ABAC policy: ${error instanceof Error ? error.message : String(error)}`,
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

  /**
   * Creates a new role in the RBAC system.
   *
   * @param roleName - The name of the role to be created.
   * @param groupId - The unique identifier of the group to which the role will be associated.
   * @param description - An optional description of the role's purpose or scope.
   * @returns A Promise resolving to the RoleId of the newly created role.
   *
   * Role creation process:
   * 1. Calls the 'create_role' function with the provided roleName, groupId, and description.
   * 2. Validates the input parameters and checks for existing roles with the same name in the group.
   * 3. Creates a new entry in the roles table within the RBAC schema.
   * 4. Logs the creation of the new role for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const newRoleId = await keyHippo.createRole('Editor', 'group123', 'Can edit and publish content');
   *   console.log(`New role created with ID: ${newRoleId}`);
   * } catch (error) {
   *   console.error('Failed to create role:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized administrators can create new roles.
   * - Creating roles affects the overall permission structure of the application.
   *
   * Error handling:
   * - Throws an error if the role creation fails due to validation issues or conflicts.
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the group does not exist.
   */
  async createRole(
    roleName: string,
    groupId: GroupId,
    description: string = "",
  ): Promise<RoleId> {
    try {
      return await createRole(
        this.supabase,
        roleName,
        groupId,
        description,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error creating role: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Retrieves the permissions associated with a specific role.
   *
   * @param roleId - The unique identifier of the role whose permissions are being queried.
   * @returns A Promise resolving to an array of permission names associated with the role.
   *
   * This method performs the following steps:
   * 1. Calls the 'get_role_permissions' function with the provided roleId.
   * 2. Queries the role_permissions table in the RBAC schema.
   * 3. Retrieves and returns a list of permission names associated with the role.
   * 4. Logs the operation for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const permissions = await keyHippo.getRolePermissions('role123');
   *   console.log('Role permissions:', permissions);
   * } catch (error) {
   *   console.error('Error retrieving role permissions:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized users can query role permissions.
   * - This method can be used for auditing and verifying role configurations.
   *
   * Error handling:
   * - Throws an error if the role does not exist.
   * - Throws an error if there are database connectivity issues.
   *
   * Note: This method retrieves direct permissions assigned to the role and does not include
   * permissions inherited from parent roles. For a complete permission set, consider implementing
   * a method that includes inherited permissions.
   */
  async getRolePermissions(roleId: RoleId): Promise<string[]> {
    try {
      return await getRolePermissions(this.supabase, roleId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error getting role permissions: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Sets an attribute for a specific group in the ABAC system.
   *
   * @param groupId - The unique identifier of the group whose attribute is being set.
   * @param attribute - The name of the attribute to set for the group.
   * @param value - The value to assign to the attribute.
   * @returns A Promise resolving to void when the attribute has been successfully set.
   *
   * This method performs the following steps:
   * 1. Calls the 'set_group_attribute' function with the provided groupId, attribute, and value.
   * 2. If the attribute doesn't exist for the group, it creates a new entry.
   * 3. If the attribute already exists, it updates the existing value.
   * 4. Stores or updates the attribute in the group_attributes table in the ABAC schema.
   * 5. Logs the operation for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.setGroupAttribute('group123', 'max_members', 100);
   *   console.log('Group attribute set successfully');
   * } catch (error) {
   *   console.error('Error setting group attribute:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized users can modify group attributes.
   * - Group attributes can affect access control decisions, so they should be carefully managed.
   *
   * Error handling:
   * - Throws an error if the attribute cannot be set due to database constraints.
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the group does not exist.
   *
   * Note: This method sets a single attribute. For setting multiple attributes at once,
   * consider implementing a batch update method.
   */
  async setGroupAttribute(
    groupId: GroupId,
    attribute: string,
    value: any,
  ): Promise<void> {
    try {
      await setGroupAttribute(
        this.supabase,
        groupId,
        attribute,
        value,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error setting group attribute: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Checks if the current user has a specific permission.
   *
   * @param permissionName - The name of the permission to check.
   * @returns A Promise resolving to a boolean indicating whether the user has the specified permission.
   *
   * This method involves the following steps:
   * 1. Calls the 'user_has_permission' function with the provided permissionName.
   * 2. Verifies the user's permissions against the RBAC schema.
   * 3. Returns true if the user has the permission, false otherwise.
   *
   * Security implications:
   * - This method should be used to enforce access control throughout the application.
   * - It's crucial for maintaining the principle of least privilege.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const canRotateKey = await keyHippo.userHasPermission('rotate_api_key');
   *   if (canRotateKey) {
   *     console.log('User can rotate API keys');
   *   } else {
   *     console.log('User does not have permission to rotate API keys');
   *   }
   * } catch (error) {
   *   console.error('Failed to check user permission:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the permission check fails for any reason.
   */
  async userHasPermission(permissionName: string): Promise<boolean> {
    try {
      return await userHasPermission(
        this.supabase,
        permissionName,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error checking user permission: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Creates a new permission in the RBAC system.
   *
   * @param permissionName - The name of the permission to create.
   * @param description - An optional description of the permission.
   * @returns A Promise resolving to the ID of the newly created permission.
   *
   * This method involves the following steps:
   * 1. Calls the 'create_permission' RPC function with the provided permissionName and description.
   * 2. Creates a new permission entry in the RBAC schema.
   * 3. Returns the ID of the newly created permission.
   *
   * Security implications:
   * - This method should be used carefully, typically by administrators or during system setup.
   * - Creating new permissions can impact the overall access control structure of the application.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const newPermissionId = await keyHippo.createPermission('edit_user_profile', 'Allows editing of user profiles');
   *   console.log('New permission created with ID:', newPermissionId);
   * } catch (error) {
   *   console.error('Failed to create permission:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the permission creation fails for any reason (e.g., duplicate permission name).
   */
  async createPermission(
    permissionName: string,
    description: string = "",
  ): Promise<PermissionId> {
    try {
      return await createPermission(
        this.supabase,
        permissionName,
        description,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error creating permission: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Updates an existing ABAC policy in the system.
   *
   * @param policyId - The unique identifier of the policy to be updated.
   * @param name - The new name for the policy.
   * @param description - The new description for the policy.
   * @param policy - The new policy JSON object.
   * @returns A Promise resolving to a boolean indicating whether the update was successful.
   *
   * Policy update process:
   * 1. Validates the input parameters.
   * 2. Updates the policy entry in the policies table within the ABAC schema.
   * 3. Returns true if the policy was found and updated, false otherwise.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const policyJson = { condition: "user.age >= 18", effect: "allow" };
   *   const updateSuccess = await keyHippo.updatePolicy('policy123', 'Adult Content', 'Allows access to adult content', policyJson);
   *   console.log(`Policy update ${updateSuccess ? 'successful' : 'failed'}`);
   * } catch (error) {
   *   console.error('Failed to update policy:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized administrators can update policies.
   * - Updating policies affects the overall access control structure of the application.
   *
   * Error handling:
   * - Throws an error if the policy update fails due to validation issues or conflicts.
   * - Throws an error if there are database connectivity issues.
   * - Throws an error if the policy does not exist.
   */
  async updatePolicy(
    policyId: PolicyId,
    name: string,
    description: string,
    policy: object,
  ): Promise<boolean> {
    try {
      return await updatePolicy(
        this.supabase,
        policyId,
        name,
        description,
        policy,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error updating policy: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Deletes an existing ABAC policy from the system.
   *
   * @param policyId - The unique identifier of the policy to be deleted.
   * @returns A Promise resolving to a boolean indicating whether the deletion was successful.
   *
   * Policy deletion process:
   * 1. Validates the input parameter.
   * 2. Deletes the policy entry from the policies table within the ABAC schema.
   * 3. Returns true if the policy was found and deleted, false otherwise.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const deleteSuccess = await keyHippo.deletePolicy('policy123');
   *   console.log(`Policy deletion ${deleteSuccess ? 'successful' : 'failed'}`);
   * } catch (error) {
   *   console.error('Failed to delete policy:', error);
   * }
   * ```

   *
   * Security implications:
   * - Ensure that only authorized administrators can delete policies.
   * - Deleting policies affects the overall access control structure of the application.
   * - Consider implementing a soft delete mechanism if policy history needs to be maintained.
   *
   * Error handling:
   * - Throws an error if the policy deletion fails due to database issues.
   * - Throws an error if there are database connectivity issues.
   * - Returns false if the policy does not exist (but does not throw an error).
   */
  async deletePolicy(policyId: PolicyId): Promise<boolean> {
    try {
      return await deletePolicy(this.supabase, policyId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error deleting policy: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Retrieves an attribute for a specified group in the ABAC system.
   *
   * @param groupId - The unique identifier of the group.
   * @param attribute - The name of the attribute to retrieve.
   * @returns A Promise resolving to the value of the attribute or null if not set.
   *
   * Group attribute retrieval process:
   * 1. Validates the input parameters.
   * 2. Queries the group_attributes table within the ABAC schema for the specified group and attribute.
   * 3. Returns the value of the attribute if found, or null if not set.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const maxMembers = await keyHippo.getGroupAttribute('group123', 'max_members');
   *   console.log(`Maximum members for the group: ${maxMembers}`);
   * } catch (error) {
   *   console.error('Failed to retrieve group attribute:', error);
   * }
   * ```

   *
   * Security implications:
   * - Ensure that only authorized users or systems can retrieve group attributes.
   * - Be cautious about exposing sensitive group information through attributes.
   *
   * Error handling:
   * - Throws an error if the attribute retrieval fails due to database issues.
   * - Throws an error if there are database connectivity issues.
   * - Returns null if the attribute is not set for the group (but does not throw an error).
   */
  async getGroupAttribute(groupId: GroupId, attribute: string): Promise<any> {
    try {
      return await getGroupAttribute(
        this.supabase,
        groupId,
        attribute,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error retrieving group attribute: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Retrieves a policy from the ABAC system by its ID.
   *
   * @param policyId - The unique identifier of the policy to retrieve.
   * @returns A Promise resolving to the Policy object.
   *
   * Policy retrieval process:
   * 1. Validates the input parameter.
   * 2. Queries the policies table within the ABAC schema for the specified policy ID.
   * 3. Returns the policy data if found.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const policy = await keyHippo.getPolicy('policy123');
   *   console.log('Retrieved policy:', policy);
   * } catch (error) {
   *   console.error('Failed to retrieve policy:', error);
   * }
   * ```

   *
   * Security implications:
   * - Ensure that only authorized users or systems can retrieve policy information.
   * - Be cautious about exposing sensitive policy details to unauthorized parties.
   *
   * Error handling:
   * - Throws an error if the policy does not exist.
   * - Throws an error if there are database connectivity issues.
   */
  async getPolicy(policyId: PolicyId): Promise<Policy> {
    try {
      return await getPolicy(this.supabase, policyId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error retrieving policy: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }
  /**
   * Creates a new group in the RBAC system.
   *
   * @param groupName - The name of the group to be created.
   * @param description - A description of the group's purpose or scope.
   * @returns A Promise resolving to the GroupId of the newly created group.
   *
   * Group creation process:
   * 1. Calls the 'create_group' function with the provided groupName and description.
   * 2. Creates a new entry in the groups table within the RBAC schema.
   * 3. Returns the ID of the newly created group.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const newGroupId = await keyHippo.createGroup('Administrators', 'Group for system administrators');
   *   console.log(`New group created with ID: ${newGroupId}`);
   * } catch (error) {
   *   console.error('Failed to create group:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized administrators can create new groups.
   * - Creating groups affects the overall permission structure of the application.
   *
   * Error handling:
   * - Throws an error if the group creation fails due to validation issues or conflicts.
   * - Throws an error if there are database connectivity issues.
   */
  async createGroup(groupName: string, description: string): Promise<GroupId> {
    try {
      return await createGroup(
        this.supabase,
        groupName,
        description,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error creating group: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }
  /**
 * Updates an existing group in the RBAC system.
 *
 * @param groupId - The unique identifier of the group to be updated.
 * @param groupName - The new name for the group.
 * @param description - The new description for the group.
 * @returns A Promise resolving to a boolean indicating whether the update was successful.
 *
 * Group update process:
 * 1. Calls the 'update_group' function with the provided groupId, groupName, and description.
 * 2. Updates the existing entry in the groups table within the RBAC schema.
 * 3. Returns true if the group was successfully updated, false otherwise.
 *
 * Usage example:
 * ```typescript
 * try {
 *   const updated = await keyHippo.updateGroup('group123', 'Senior Administrators', 'Group for senior system administrators');
 *   if (updated) {
 *     console.log('Group successfully updated');
 *   } else {
 *     console.log('Group not found or update failed');
 *   }
 * } catch (error) {
 *   console.error('Failed to update group:', error);
 * }
 * ```

 *
 * Security implications:
 * - Ensure that only authorized administrators can update existing groups.
 * - Updating groups may affect the overall permission structure of the application.
 *
 * Error handling:
 * - Throws an error if the group update fails due to validation issues or conflicts.
 * - Throws an error if there are database connectivity issues.
 * - Returns false if the group does not exist (but does not throw an error).
 */
  async updateGroup(
    groupId: GroupId,
    groupName: string,
    description: string,
  ): Promise<boolean> {
    try {
      return await updateGroup(
        this.supabase,
        groupId,
        groupName,
        description,
        this.logger,
      );
    } catch (error) {
      this.logger.error(
        `Error updating group: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }
  /**
   * Deletes an existing group from the RBAC system.
   *
   * @param groupId - The unique identifier of the group to be deleted.
   * @returns A Promise resolving to a boolean indicating whether the deletion was successful.
   *
   * Group deletion process:
   * 1. Calls the 'delete_group' function with the provided groupId.
   * 2. Removes the group entry from the groups table within the RBAC schema.
   * 3. Returns true if the group was successfully deleted, false otherwise.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const deleted = await keyHippo.deleteGroup('group123');
   *   if (deleted) {
   *     console.log('Group successfully deleted');
   *   } else {
   *     console.log('Group not found or deletion failed');
   *   }
   * } catch (error) {
   *   console.error('Failed to delete group:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized administrators can delete existing groups.
   * - Deleting groups may affect the overall permission structure of the application.
   * - Consider implementing a soft delete mechanism if group history needs to be maintained.
   *
   * Error handling:
   * - Throws an error if the group deletion fails due to database issues.
   * - Throws an error if there are database connectivity issues.
   * - Returns false if the group does not exist (but does not throw an error).
   */
  async deleteGroup(groupId: GroupId): Promise<boolean> {
    try {
      return await deleteGroup(this.supabase, groupId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error deleting group: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }
  /**
   * Retrieves an existing group from the RBAC system.
   *
   * @param groupId - The unique identifier of the group to be retrieved.
   * @returns A Promise resolving to the Group object if found, or null if not found.
   *
   * Group retrieval process:
   * 1. Calls the 'get_group' function with the provided groupId.
   * 2. Retrieves the group entry from the groups table within the RBAC schema.
   * 3. Returns the Group object if found, or null if not found.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const group = await keyHippo.getGroup('group123');
   *   if (group) {
   *     console.log('Group found:', group);
   *   } else {
   *     console.log('Group not found');
   *   }
   * } catch (error) {
   *   console.error('Failed to retrieve group:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized users can retrieve group information.
   * - Be cautious about exposing sensitive group details to unauthorized parties.
   *
   * Error handling:
   * - Throws an error if there are database connectivity issues.
   * - Returns null if the group does not exist (but does not throw an error).
   */
  async getGroup(groupId: GroupId): Promise<Group | null> {
    try {
      return await getGroup(this.supabase, groupId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error retrieving group: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

  /**
   * Deletes an existing permission from the RBAC system.
   *
   * @param permissionId - The unique identifier of the permission to be deleted.
   * @returns A Promise resolving to a boolean indicating whether the deletion was successful.
   *
   * Permission deletion process:
   * 1. Calls the 'delete_permission' function with the provided permissionId.
   * 2. Removes the permission entry from the permissions table within the RBAC schema.
   * 3. Returns true if the permission was successfully deleted, false otherwise.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const deleted = await keyHippo.deletePermission('permission123');
   *   if (deleted) {
   *     console.log('Permission successfully deleted');
   *   } else {
   *     console.log('Permission not found or deletion failed');
   *   }
   * } catch (error) {
   *   console.error('Failed to delete permission:', error);
   * }
   * ```
   *
   * Security implications:
   * - Ensure that only authorized administrators can delete existing permissions.
   * - Deleting permissions may affect the overall access control structure of the application.
   * - Consider implementing a soft delete mechanism if permission history needs to be maintained.
   *
   * Error handling:
   * - Throws an error if the permission deletion fails due to database issues.
   * - Throws an error if there are database connectivity issues.
   * - Returns false if the permission does not exist (but does not throw an error).
   */
  async deletePermission(permissionId: PermissionId): Promise<boolean> {
    try {
      return await deletePermission(this.supabase, permissionId, this.logger);
    } catch (error) {
      this.logger.error(
        `Error deleting permission: ${error instanceof Error ? error.message : String(error)}`,
      );
      throw error;
    }
  }

}
