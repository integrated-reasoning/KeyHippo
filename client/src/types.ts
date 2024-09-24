import { SupabaseClient } from "@supabase/supabase-js";

/**
 * Logger interface defining methods for different logging levels.
 */
export interface Logger {
  /**
   * Logs an informational message.
   * @param message - The informational message to log.
   */
  info: (message: string) => void;

  /**
   * Logs a warning message.
   * @param message - The warning message to log.
   */
  warn: (message: string) => void;

  /**
   * Logs an error message.
   * @param message - The error message to log.
   */
  error: (message: string) => void;

  /**
   * Logs a debug message.
   * @param message - The debug message to log.
   */
  debug: (message: string) => void;
}

/**
 * Represents the response containing an API key.
 */
export type ApiKeyResponse = {
  /**
   * The API key string.
   */
  api_key: string;
};

/**
 * Represents a record of an API key in the database.
 */
export type ApiKeyRecord = {
  /**
   * The unique identifier of the API key.
   */
  id: string;

  /**
   * A description of the API key.
   */
  description: string;

  /**
   * The API key string.
   */
  api_key: string;
};

/**
 * Represents basic information about an API key.
 */
export type ApiKeyInfo = {
  /**
   * The unique identifier of the API key.
   */
  id: string;

  /**
   * A description of the API key.
   */
  description: string;
};

/**
 * Extends ApiKeyInfo with additional details about the API key.
 */
export interface CompleteApiKeyInfo extends ApiKeyInfo {
  /**
   * The API key string. It can be null if the key is not available.
   */
  apiKey: string | null;

  /**
   * The status of the API key creation or rotation.
   */
  status: "success" | "failed";

  /**
   * Optional error message if the status is "failed".
   */
  error?: string;
}

/**
 * Represents the result of an API key operation.
 */
export interface ApiKeyResult {
  /**
   * Indicates whether the operation was successful.
   */
  success: boolean;

  /**
   * The API key string if the operation was successful.
   */
  api_key?: string;

  /**
   * The error message if the operation failed.
   */
  error?: string;

  /**
   * An optional message providing additional context.
   */
  message?: string;
}

/**
 * Represents the result of rotating an API key.
 */
export type RotateApiKeyResult = {
  /**
   * The new API key string generated after rotation.
   */
  new_api_key: string;

  /**
   * The unique identifier of the new API key.
   */
  new_api_key_id: string;

  /**
   * An optional description of the new API key.
   */
  description?: string;
};

/**
 * Represents metadata associated with an API key.
 */
export type ApiKeyMetadata = {
  /**
   * The unique identifier of the API key.
   */
  api_key_id: string;

  /**
   * The name of the API key.
   */
  name: string;

  /**
   * The permission level associated with the API key.
   */
  permission: string;

  /**
   * The timestamp of when the API key was last used.
   */
  last_used: string;

  /**
   * The timestamp of when the API key was created.
   */
  created: string;

  /**
   * The timestamp of when the API key was revoked, if applicable.
   */
  revoked: string;

  /**
   * The total number of times the API key has been used.
   */
  total_uses: number;

  /**
   * The success rate of the API key usage.
   */
  success_rate: number;

  /**
   * The total cost associated with the API key usage.
   */
  total_cost: number;
};

/**
 * Represents various application-specific errors.
 */
export type AppError =
  | { _tag: "DatabaseError"; message: string }
  | { _tag: "UnauthorizedError"; message: string }
  | { _tag: "ValidationError"; message: string }
  | { _tag: "NetworkError"; message: string }
  | { _tag: "AuthenticationError"; message: string };

/**
 * Represents the result of an authentication operation.
 */
export type AuthResult = {
  /**
   * The unique identifier of the authenticated user.
   */
  userId: string;

  /**
   * The Supabase client instance associated with the authenticated session.
   */
  supabase: SupabaseClient<any, "public", any>;
};
