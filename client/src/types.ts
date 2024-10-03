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
 * A name or title.
 */
export type Name = string;

/**
 * A message string.
 */
export type Message = string;

// Utility types
/**
 * Makes a type optional by allowing it to be null.
 */
type Optional<T> = T | null;

/**
 * Makes specified properties of a type optional.
 */
type WithOptional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;

// Status types
/**
 * The status of an operation.
 */
type OperationStatus = "success" | "failed";

/**
 * The status of an API key.
 */
type ApiKeyStatus = OperationStatus;

// Common fields
/**
 * Interface for objects that have a creation timestamp.
 */
interface Timestamped {
  createdAt: Timestamp;
}

/**
 * Interface for objects that have a unique identifier.
 */
interface Identifiable {
  id: ApiKeyId;
}

/**
 * Interface for objects that have a description.
 */
interface Describable {
  description: Description;
}

// API Key related types
/**
 * Base interface for API key related types.
 */
interface ApiKeyBase extends Identifiable, Describable {}

/**
 * A summarized view of an API key.
 */
export type ApiKeySummary = ApiKeyBase;

/**
 * Interface for API key metadata fields.
 */
interface ApiKeyMetadataFields {
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
interface OperationResult {
  success: boolean;
  error?: Message;
  message?: Message;
}

/**
 * The result of an API key operation.
 */
export type ApiKeyOperationResult = OperationResult & {
  apiKey?: ApiKeyText;
};

/**
 * The result of rotating an API key.
 */
export type RotateApiKeyResult = {
  apiKey: ApiKeyText;
  id: ApiKeyId;
  status: OperationStatus;
};

// Error types
/**
 * The types of application errors.
 */
type ErrorType =
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
export type AuthenticationResult = {
  userId: UserId;
  supabase: SupabaseClient<any, "public", any>;
};

// Authorization types
export type AuthResult = {
  /**
   * An array containing the authentication result.
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
};

// Logger interface
/**
 * The available log levels.
 */
type LogLevel = "info" | "warn" | "error" | "debug";

/**
 * Interface for a logger with methods for different log levels.
 */
export type Logger = {
  [K in LogLevel]: (message: Message) => void;
};
