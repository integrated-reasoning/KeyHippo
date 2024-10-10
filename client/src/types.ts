import { SupabaseClient } from "@supabase/supabase-js";

// Base types
/**
 * A timestamp as a string.
 */
export type Timestamp = string;

/**
 * The actual text of an API key.
 */
export type ApiKeyText = string;

/**
 * The unique identifier of an API key.
 */
export type ApiKeyId = string;

/**
 * The unique identifier of a user.
 */
export type UserId = string;

/**
 * The unique identifier of a group.
 */
export type GroupId = string;

/**
 * The unique identifier of a role.
 */
export type RoleId = string;

/**
 * The unique identifier of a scope.
 */
export type ScopeId = string;

/**
 * A description text.
 */
export type Description = string;

/**
 * A permission level.
 */
export type Permission = string;

/**
 * A permission name
 */
export type PermissionName = string;

/**
 * A name or title.
 */
export type Name = string;

/**
 * A message string.
 */
export type Message = string;

/**
 * The unique identifier of a policy.
 */
export type PolicyId = string;

/**
 * The unique identifier of a permission.
 */
export type PermissionId = string;

// Utility types
/**
 * Makes a type optional by allowing it to be null.
 */
export type Optional<T> = T | null;

/**
 * Makes specified properties of a type optional.
 */
export type WithOptional<T, K extends keyof T> = Omit<T, K> &
  Partial<Pick<T, K>>;

// Status types
/**
 * The status of an operation.
 */
export type OperationStatus = "success" | "failed";

/**
 * The status of an API key.
 */
export type ApiKeyStatus = OperationStatus;

// Common interfaces
/**
 * Interface for objects that have a creation timestamp.
 */
export interface Timestamped {
  createdAt: Timestamp;
}

/**
 * Interface for objects that have a unique identifier.
 */
export interface Identifiable {
  id: ApiKeyId;
}

/**
 * Interface for objects that have a description.
 */
export interface Describable {
  description: Description;
}

// API Key related types
/**
 * Base interface for API key related types.
 */
export interface ApiKeyBase extends Identifiable, Describable {}

/**
 * A summarized view of an API key.
 */
export type ApiKeySummary = ApiKeyBase;

/**
 * Interface for API key metadata fields.
 */
export interface ApiKeyMetadataFields {
  name: Name;
  permission: Permission;
  lastUsedAt: Timestamp;
  revokedAt: Optional<Timestamp>;
  totalUses: number;
  successRate: number;
  totalCost: number;
}

/**
 * The full metadata of an API key.
 */
export type ApiKeyMetadata = ApiKeyBase & ApiKeyMetadataFields & Timestamped;

/**
 * The complete entity of an API key.
 */
export interface ApiKeyEntity extends ApiKeySummary {
  user_id: UserId;
  created_at: Timestamp;
  last_used_at: Optional<Timestamp>;
  expires_at: Timestamp;
  is_revoked: boolean;
  apiKey: Optional<ApiKeyText>;
}

// Operation result types
/**
 * Interface for the result of an operation.
 */
export interface OperationResult {
  success: boolean;
  error?: Message;
  message?: Message;
}

/**
 * The result of an API key operation.
 */
export interface ApiKeyOperationResult extends OperationResult {
  apiKey?: ApiKeyText;
}

/**
 * The result of rotating an API key.
 */
export interface RotateApiKeyResult {
  apiKey: ApiKeyText;
  id: ApiKeyId;
  status: OperationStatus;
}

// Error types
/**
 * The types of application errors.
 */
export type ErrorType =
  | "DatabaseError"
  | "UnauthorizedError"
  | "ValidationError"
  | "NetworkError"
  | "AuthenticationError";

/**
 * An application error with a type and message.
 */
export type ApplicationError = {
  [K in ErrorType]: { type: K; message: Message };
}[ErrorType];

// Authentication types
/**
 * The result of an authentication operation.
 */
export interface AuthenticationResult {
  userId: UserId;
  supabase: SupabaseClient<any, "public", any>;
}

/**
 * The result of an authentication operation.
 */
export interface AuthResult {
  /**
   * Authentication details.
   */
  auth: {
    /**
     * The unique identifier of the authenticated user.
     */
    user_id: UserId;
    /**
     * The permissions associated with the authenticated user.
     */
    permissions: Array<Permission>;
    /**
     * The scope identifier, if any.
     */
    scope_id: Optional<ScopeId>;
  };
  /**
   * The authenticated Supabase client instance.
   */
  supabase: SupabaseClient;
}

// Logger interface
/**
 * The available log levels.
 */
export type LogLevel = "info" | "warn" | "error" | "debug";

/**
 * Interface for a logger with methods for different log levels.
 */
export type Logger = {
  [K in LogLevel]: (message: Message) => void;
};
