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
  setUserAttribute as setUserAttributeEffect,
  getAllKeyMetadata as getAllKeyMetadataEffect,
} from "./apiKey";
import { authenticate as authenticateEffect } from "./auth";
import {
  Logger,
  AppError,
  ApiKeyInfo,
  CompleteApiKeyInfo,
  ApiKeyMetadata,
  AuthResult,
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
   * Generates a new API key for the specified user.
   *
   * @param userId - The unique identifier of the user for whom the API key is
   *                 being created.
   * @param keyDescription - A human-readable description of the key's purpose
   *                         or context.
   * @returns A Promise resolving to an object containing the generated API key
   *          and its unique identifier.
   *
   * API Key Creation Process:
   * 1. Verifies that auth.uid() matches the provided userId.
   * 2. Generates a UUID (jti) using gen_random_uuid().
   * 3. Generates current timestamp and expiry (100 years from now).
   * 4. Constructs a JWT body (role, aud, iss, sub, iat, exp, jti).
   * 5. Retrieves user_api_key_secret, project_api_key_secret, and
   *    project_jwt_secret from Supabase Vault.
   * 6. Signs the JWT with project_jwt_secret.
   * 7. Generates api_key = HMAC(jwt, user_api_key_secret, sha512).
   * 8. Generates project_hash = HMAC(api_key, project_api_key_secret, sha512).
   * 9. Stores the JWT in vault.secrets with project_hash as the name and
   *    keyDescription as the description.
   * 10. Stores the secret_id and user_id in auth.jwts.
   * 11. Returns the derived api_key (which is not stored anywhere).
   *
   * Security features:
   * - Each invocation produces a unique key, regardless of input consistency.
   * - High-precision timestamps ensure uniqueness for rapid successive key
   *   creations.
   * - The multi-stage hashing process is cryptographically irreversible.
   * - Database compromise does not allow regeneration or deduction of original
   *   API keys.
   * - Utilization of Supabase Vault adds an additional layer of security.
   *
   * Usage example:
   * ```typescript
   * const { apiKey, apiKeyId } = await keyHippo.createApiKey(
   *   'user123',
   *   'Development environment read-only key'
   * );
   * console.log(`New API key created: ${apiKey}`);
   * console.log(`API key ID: ${apiKeyId}`);
   * ```
   *
   * Note: The generated API key is returned only once and cannot be retrieved
   * later. Ensure it's securely transmitted to the user.
   */
  async createApiKey(
    userId: string,
    keyDescription: string,
  ): Promise<CompleteApiKeyInfo> {
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

  /**
   * Retrieves metadata for all API keys associated with a user.
   *
   * @param userId - The unique identifier of the user whose API key information
   *                 is being requested.
   * @returns A Promise resolving to an array of API key metadata objects.
   *
   * This method retrieves the following information for each API key:
   * - id: The unique identifier for the API key in the database.
   * - description: The human-readable description provided when the key was
   *   created.
   *
   * The method performs the following steps:
   * 1. Calls the 'load_api_key_info' RPC function with the provided userId.
   * 2. Processes the returned data to extract the relevant API key information.
   * 3. Logs the operation and any errors that occur during the process.
   *
   * This method is useful for:
   * - Auditing active API keys for a user
   * - Retrieving key descriptions for display in user interfaces
   * - Preparing data for key management operations
   *
   * Usage example:
   * ```typescript
   * const apiKeys = await keyHippo.loadApiKeyInfo('user123');
   * apiKeys.forEach(key => {
   *   console.log(`Key ID: ${key.id}, Description: ${key.description}`);
   * });
   * ```
   *
   * Note: This method only returns metadata and does not provide access to the
   * actual API key values.
   */
  async loadApiKeyInfo(userId: string): Promise<ApiKeyInfo[]> {
    return Effect.runPromise(
      loadApiKeyInfoEffect(this.supabase, userId, this.logger),
    );
  }

  /**
   * Revokes an API key, immediately invalidating it for all future requests.
   *
   * @param userId - The unique identifier of the user who owns the API key.
   * @param apiKeyId - The unique identifier of the API key to be revoked.
   * @returns A Promise that resolves when the key has been successfully revoked.
   *
   * Revocation process:
   * 1. Calls the 'revoke_api_key' RPC function with the provided userId and
   *    apiKeyId.
   * 2. Verifies that the API key belongs to the specified user.
   * 3. Updates the key's status to 'revoked' in the database.
   * 4. Logs the revocation event for audit purposes.
   *
   * Security implications:
   * - Revocation takes effect immediately for new requests.
   * - Requests in progress at the time of revocation will complete.
   * - Revoked keys cannot be reinstated; a new key must be created if access is
   *   required again.
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.revokeApiKey('user123', 'apiKey456');
   *   console.log('API key successfully revoked');
   * } catch (error) {
   *   console.error('Failed to revoke API key:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the API key doesn't exist or doesn't belong to the
   *   specified user.
   * - Throws an error if there are database connectivity issues.
   *
   * Note: It's recommended to implement monitoring for failed API key usage
   * attempts to detect and respond to potential security incidents.
   */
  async revokeApiKey(userId: string, secretId: string): Promise<void> {
    return Effect.runPromise(
      revokeApiKeyEffect(this.supabase, userId, secretId, this.logger),
    );
  }

  /**
   * Retrieves comprehensive metadata for all API keys belonging to a user.
   *
   * @param userId - The unique identifier of the user whose API keys are being
   *                 queried.
   * @returns A Promise resolving to an array of API key metadata objects.
   *
   * This method provides an extensive overview of each API key, including:
   * - api_key_id: The unique identifier for the API key
   * - name: The human-readable name or description of the key
   * - permission: The permission level associated with the key
   * - last_used: Timestamp of the key's last usage
   * - created: Timestamp of the key's creation
   * - revoked: Timestamp of the key's revocation (if applicable)
   * - total_uses: Number of times the key has been used
   * - success_rate: Percentage of successful API calls made with this key
   * - total_cost: Cumulative cost associated with the key's usage
   *
   * The method performs the following steps:
   * 1. Calls the 'get_api_key_metadata' RPC function with the provided userId.
   * 2. Processes the returned data to extract the comprehensive API key
   *    information.
   * 3. Logs the operation and any errors that occur during the process.
   *
   * Use cases:
   * - Performing security audits
   * - Analyzing API usage patterns
   * - Monitoring key performance and cost
   * - Identifying unused or potentially compromised keys
   *
   * Usage example:
   * ```typescript
   * const keyMetadata = await keyHippo.getAllKeyMetadata('user123');
   * keyMetadata.forEach(key => {
   *   console.log(`Key ID: ${key.api_key_id}, Uses: ${key.total_uses},
   *   Success Rate: ${key.success_rate}%`);
   * });
   * ```
   *
   * Note: This method provides a comprehensive view of key usage and
   * performance, which can be valuable for both security and operational
   * purposes.
   */
  async getAllKeyMetadata(userId: string): Promise<ApiKeyMetadata[]> {
    return Effect.runPromise(
      Effect.catchAll(
        getAllKeyMetadataEffect(this.supabase, userId, this.logger),
        (error: AppError) =>
          Effect.fail(`Error getting API key metadata: ${error.message}`),
      ),
    );
  }

  /**
   * Rotates an existing API key, generating a new key while invalidating the
   * old one.
   *
   * @param userId - The unique identifier of the user who owns the API key.
   * @param apiKeyId - The unique identifier of the API key to be rotated.
   * @returns A Promise resolving to an object containing the new API key and
   * its identifier.
   *
   * Key rotation process:
   * 1. Calls the 'rotate_api_key' RPC function with the provided apiKeyId.
   * 2. Verifies the ownership and validity of the existing key.
   * 3. Generates a new API key using the same process as createApiKey().
   * 4. Transfers all metadata, permissions, and associations from the old key
   *    to the new key.
   * 5. Updates the database to associate the new key hash with the user.
   * 6. Marks the old key as revoked but maintains its historical data.
   * 7. Logs the rotation event for audit purposes.
   *
   * Security benefits:
   * - Limits the exposure window of potentially compromised keys.
   * - Allows for regular updates to access credentials without changing
   *   permissions.
   * - Provides an opportunity to review and adjust associated permissions if
   *   needed.
   *
   * Usage considerations:
   * - Coordinate key rotation with API consumers to ensure smooth transition.
   * - Implement a grace period where both old and new keys are valid to prevent
   *   service interruptions.
   * - Consider automating key rotation as part of a regular security
   *   maintenance routine.
   *
   * Usage example:
   * ```typescript
   * try {
   *   const { new_api_key, new_api_key_id } = await keyHippo.rotateApiKey(
   *     'user123',
   *     'oldApiKey456'
   *   );
   *   console.log(`New API key: ${new_api_key}`);
   *   console.log(`New API key ID: ${new_api_key_id}`);
   *   // Securely transmit the new key to the user or service
   * } catch (error) {
   *   console.error('Failed to rotate API key:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the original API key doesn't exist or doesn't belong
   *   to the specified user.
   * - Throws an error if there are database connectivity issues.
   *
   * Note: After rotation, the old API key will no longer be valid for
   * authentication, but its metadata is preserved for historical and audit
   * purposes.
   */
  async rotateApiKey(
    userId: string,
    apiKeyId: string,
  ): Promise<CompleteApiKeyInfo> {
    return Effect.runPromise(
      Effect.catchAll(
        rotateApiKeyEffect(this.supabase, userId, apiKeyId, this.logger),
        (error: AppError) =>
          Effect.fail(`Error rotating API key: ${error.message}`),
      ),
    );
  }

  /**
   * Authenticates a user based on the provided request headers.
   *
   * @param headers - The HTTP headers from the incoming request, typically
   *                  containing the KeyHippo API key or session credentials.
   * @returns A Promise resolving to the authenticated user object and an
   *          authenticated Supabase client.
   *
   * Authentication process:
   * 1. Extracts the Authorization header from the provided request headers.
   * 2. If the Authorization header contains a KeyHippo API key:
   *    a. Extracts the API key from the header. **Note:** The KeyHippo API key
   *       is not a bearer token but a sha512 hash.
   *    b. Reinitializes the Supabase client with the API key for authentication
   *       purposes.
   *    c. Calls the 'get_uid_for_key' RPC function to retrieve the user ID
   *       associated with the KeyHippo API key.
   *    d. Verifies if the API key is valid (e.g., not revoked, expired, or
   *       invalid).
   *    e. If valid, returns the user ID and the authenticated Supabase client.
   * 3. If no KeyHippo API key is provided, it attempts session-based
   *    authentication:
   *    a. Calls Supabase's `auth.getUser()` to retrieve the session user.
   *    b. If the user is authenticated, returns the user ID and the Supabase
   *       client.
   *    c. If no valid session exists, throws an error indicating the user is
   *       not authenticated.
   *
   * Security considerations:
   * - KeyHippo API keys are sha512 hashes and should be handled securely.
   * - Failed authentication attempts are logged with request details.
   * - Implement rate limiting to prevent brute-force attacks on API keys.
   *
   * Usage example:
   * ```typescript
   * const headers = new Headers({
   *   'Authorization': 'KeyHippoKey a4f1e0a5d...<sha512 hash>'
   * });
   * try {
   *   const { userId, supabase } = await keyHippo.authenticate(headers);
   *   console.log(`Authenticated user: ${userId}`);
   *   // Use the authenticated Supabase client for further operations
   * } catch (error) {
   *   console.error('Authentication failed:', error.message);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if authentication fails due to an invalid KeyHippo API
   *   key, missing session, or other issues.
   *
   * Note: This method supports both API key-based authentication and
   * session-based authentication.
   */
  async authenticate(headers: Headers): Promise<AuthResult> {
    return Effect.runPromise(
      authenticateEffect(headers, this.supabase, this.logger),
    );
  }

  // RBAC methods

  /**
   * Adds a user to a specified group with a given role.
   *
   * @param userId - The unique identifier of the user being added to the group.
   * @param groupId - The unique identifier of the group to which the user will
   *                  be added.
   * @param roleName - The role that the user will be assigned within the group.
   * @returns A Promise resolving when the user has been successfully added to
   *          the group.
   *
   * Adding a user to a group involves the following steps:
   * 1. Calls the 'add_user_to_group' RPC function with the provided userId,
   *    groupId, and roleName.
   * 2. Verifies that the group and role exist in the RBAC schema.
   * 3. Assigns the user to the specified role within the group.
   * 4. Logs the group addition for audit purposes.
   *
   * Security implications:
   * - Ensure that only authorized administrators have the ability to assign
   *   users to groups and roles.
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.addUserToGroup('user123', 'group456', 'admin');
   *   console.log('User successfully added to group');
   * } catch (error) {
   *   console.error('Failed to add user to group:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the group or role does not exist.
   * - Throws an error if there are database connectivity issues.
   */
  async addUserToGroup(
    userId: string,
    groupId: string,
    roleName: string,
  ): Promise<void> {
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

  /**
   * Sets a parent role for a specified child role.
   *
   * @param childRoleId - The unique identifier of the child role.
   * @param parentRoleId - The unique identifier of the parent role.
   * @returns A Promise resolving when the parent role has been successfully set.
   *
   * This operation establishes a hierarchical relationship between roles:
   * 1. Calls the 'set_parent_role' RPC function with the provided childRoleId
   *    and parentRoleId.
   * 2. Ensures that the parent role inherits permissions granted to the child
   *    role.
   * 3. Logs the role hierarchy update for auditing purposes.
   *
   * Security implications:
   * - Role hierarchies allow for streamlined permission management but must be
   *   used cautiously to prevent privilege escalation.
   * - Ensure that only authorized users have the ability to modify role
   *   hierarchies.
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.setParentRole('childRole123', 'parentRole456');
   *   console.log('Parent role successfully set');
   * } catch (error) {
   *   console.error('Failed to set parent role:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the role IDs do not exist or if there are connectivity
   *   issues.
   */
  async setParentRole(
    childRoleId: string,
    parentRoleId: string,
  ): Promise<void> {
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

  /**
   * Updates the claims cache for a specified user, ensuring their role-based
   * claims are up-to-date.
   *
   * @param userId - The unique identifier of the user whose claims cache needs
   *                 to be updated.
   * @returns A Promise resolving when the claims cache has been successfully
   * updated.
   *
   * This operation is necessary to reflect changes in a user's group
   * memberships or role assignments.
   * 1. Calls the 'update_user_claims_cache' RPC function with the provided
   *    userId.
   * 2. Refreshes the user's claims cache to reflect their latest roles and
   *    permissions.
   * 3. Logs the cache update for auditing purposes.
   *
   * Use cases:
   * - This method should be called after any significant changes in the user's
   *   permissions or role assignments.
   *
   * Usage example:
   * ```typescript
   * try {
   *   await keyHippo.updateUserClaimsCache('user123');
   *   console.log('User claims cache updated');
   * } catch (error) {
   *   console.error('Failed to update user claims cache:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the user does not exist or if there are database
   *   connectivity issues.
   */
  async updateUserClaimsCache(userId: string): Promise<void> {
    return Effect.runPromise(
      updateUserClaimsCacheEffect(this.supabase, userId, this.logger),
    );
  }

  // ABAC methods

  /**
   * Creates a new ABAC (Attribute-Based Access Control) policy.
   *
   * @param policyName - The unique name of the policy being created.
   * @param description - A human-readable description of the policy's purpose.
   * @param policy - A JSON object defining the policy rules and conditions.
   * @returns A Promise resolving when the policy has been successfully created.
   *
   * Policy creation process:
   * 1. Calls the 'create_policy' RPC function with the provided policyName,
   *    description, and policy object.
   * 2. Stores the policy in the ABAC schema for future evaluations.
   * 3. Logs the creation of the policy for auditing purposes.
   *
   * Security implications:
   * - ABAC policies provide dynamic access control based on user attributes and
   *   request context.
   * - Ensure that only trusted administrators can define or modify policies.
   *
   * Usage example:
   * ```typescript
   * const policy = {
   *   action: 'read',
   *   resource: 'document',
   *   condition: { attribute: 'department', value: 'engineering' }
   * };
   * try {
   *   await keyHippo.createPolicy('EngineeringReadPolicy', 'Policy for
   *   engineers to read documents', policy);
   *   console.log('Policy successfully created');
   * } catch (error) {
   *   console.error('Failed to create policy:', error);
   * }
   * ```
   *
   * Error handling:
   * - Throws an error if the policy creation fails due to validation or
   *   connectivity issues.
   */
  async createPolicy(
    policyName: string,
    description: string,
    policy: any,
  ): Promise<void> {
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

  /**
   * Evaluates ABAC policies for a specified user, determining if access is granted.
   *
   * @param userId - The unique identifier of the user whose policies are being
   *                 evaluated.
   * @returns A Promise resolving to a boolean indicating whether access is
   *          granted.
   *
   * Policy evaluation process:
   * 1. Calls the 'evaluate_policies' RPC function with the provided userId.
   * 2. Applies the relevant ABAC policies based on user attributes and request
   *    context.
   * 3. Logs the result of the evaluation for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * const hasAccess = await keyHippo.evaluatePolicies('user123');
   * if (hasAccess) {
   *   console.log('Access granted');
   * } else {
   *   console.log('Access denied');
   * }
   * ```
   *
   * Security implications:
   * - Ensure that policy rules are properly defined to prevent unauthorized
   *   access.
   *
   * Error handling:
   * - Throws an error if the evaluation fails due to database connectivity or
   *   invalid policies.
   */
  async evaluatePolicies(userId: string): Promise<boolean> {
    return Effect.runPromise(
      Effect.catchAll(
        evaluatePoliciesEffect(this.supabase, userId, this.logger),
        (error: AppError) =>
          Effect.fail(`Error evaluating policies: ${error.message}`),
      ),
    );
  }

  /**
   * Retrieves a specific attribute for a given user from the ABAC system.
   *
   * @param userId - The unique identifier of the user whose attribute is being
   *                 retrieved.
   * @param attribute - The name of the attribute to retrieve.
   * @returns A Promise resolving to the value of the requested attribute.
   *
   * Attribute retrieval process:
   * 1. Calls the 'get_user_attribute' RPC function with the provided userId and
   *    attribute name.
   * 2. Retrieves the attribute value from the ABAC schema.
   * 3. Logs the retrieval operation for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * const department = await keyHippo.getUserAttribute('user123',
   * 'department');
   * console.log(`User department: ${department}`);
   * ```
   *
   * Security implications:
   * - Ensure that only authorized users can retrieve sensitive attributes.
   *
   * Error handling:
   * - Throws an error if the attribute does not exist or if there are database
   *   connectivity issues.
   */
  async getUserAttribute(userId: string, attribute: string): Promise<any> {
    return Effect.runPromise(
      Effect.map(
        getUserAttributeEffect(this.supabase, userId, attribute, this.logger),
        (response) => response.data,
      ),
    );
  }

  /**
   * Sets a user attribute in the ABAC system.
   *
   * @param userId - The unique identifier of the user whose attribute is being
   *                 set.
   * @param attribute - The name of the attribute to set for the user.
   * @param value - The value of the attribute to assign.
   * @returns A Promise resolving when the attribute has been successfully set.
   *
   * Attribute setting process:
   * 1. Calls the 'set_user_attribute' RPC function with the provided userId,
   *    attribute, and value.
   * 2. Stores or updates the attribute in the ABAC schema.
   * 3. Logs the operation for auditing purposes.
   *
   * Usage example:
   * ```typescript
   * await keyHippo.setUserAttribute('user123', 'department', 'engineering');
   * console.log('User attribute set successfully');
   * ```
   *
   * Security implications:
   * - Ensure that only authorized users can modify sensitive attributes.
   *
   * Error handling:
   * - Throws an error if the attribute cannot be set or if there are database
   *   connectivity issues.
   */
  async setUserAttribute(
    userId: string,
    attribute: string,
    value: any,
  ): Promise<void> {
    return Effect.runPromise(
      Effect.catchAll(
        setUserAttributeEffect(
          this.supabase,
          userId,
          attribute,
          value,
          this.logger,
        ),
        (error: AppError) =>
          Effect.fail(`Error setting user attribute: ${error.message}`),
      ),
    );
  }
}
