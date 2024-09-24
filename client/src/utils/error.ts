import { AppError, Logger } from "../types";

/**
 * Retrieves a user-friendly error message from an unknown error object.
 * @param error - The error object from which to extract the message.
 * @returns A string representing the error message.
 */
export const getErrorMessage = (error: unknown): string => {
  return error instanceof Error ? error.message : String(error);
};

/**
 * Handles an error by logging it and throwing a standardized database error.
 * @param error - The error object encountered during the process.
 * @param logger - The logger instance used for logging the error.
 * @param message - A descriptive message providing context for the error.
 * @throws AppError encapsulating the original error with a descriptive message.
 */
export const handleError = (
  error: unknown,
  logger: Logger,
  message: string,
): never => {
  logger.error(`${message}: ${getErrorMessage(error)}`);
  throw createDatabaseError(`${message}: ${getErrorMessage(error)}`);
};

/**
 * Type guard to determine if an error is an instance of AppError.
 * @param error - The error object to check.
 * @returns A boolean indicating whether the error is an AppError.
 */
export const isAppError = (error: any): error is AppError => {
  return (
    error &&
    typeof error === "object" &&
    "_tag" in error &&
    typeof error._tag === "string" &&
    "message" in error &&
    typeof error.message === "string"
  );
};

/**
 * Type guard to determine if an error is an UnauthorizedError.
 * @param error - The error object to check.
 * @returns A boolean indicating whether the error is an UnauthorizedError.
 */
export const isUnauthorizedError = (
  error: any,
): error is { _tag: "UnauthorizedError"; message: string } => {
  return isAppError(error) && error._tag === "UnauthorizedError";
};

/**
 * Type guard to determine if an error is an AuthenticationError.
 * @param error - The error object to check.
 * @returns A boolean indicating whether the error is an AuthenticationError.
 */
export const isAuthenticationError = (
  error: any,
): error is { _tag: "AuthenticationError"; message: string } => {
  return isAppError(error) && error._tag === "AuthenticationError";
};

/**
 * Creates an UnauthorizedError.
 * @param message - A descriptive message for the UnauthorizedError.
 * @returns An AppError object representing the UnauthorizedError.
 */
export const createUnauthorizedError = (message: string): AppError => ({
  _tag: "UnauthorizedError",
  message,
});

/**
 * Creates an AuthenticationError.
 * @param message - A descriptive message for the AuthenticationError.
 * @returns An AppError object representing the AuthenticationError.
 */
export const createAuthenticationError = (message: string): AppError => ({
  _tag: "AuthenticationError",
  message,
});

/**
 * Creates a DatabaseError.
 * @param message - A descriptive message for the DatabaseError.
 * @returns An AppError object representing the DatabaseError.
 */
export const createDatabaseError = (message: string): AppError => ({
  _tag: "DatabaseError",
  message,
});

/**
 * Creates a ValidationError.
 * @param message - A descriptive message for the ValidationError.
 * @returns An AppError object representing the ValidationError.
 */
export const createValidationError = (message: string): AppError => ({
  _tag: "ValidationError",
  message,
});

/**
 * Creates a NetworkError.
 * @param message - A descriptive message for the NetworkError.
 * @returns An AppError object representing the NetworkError.
 */
export const createNetworkError = (message: string): AppError => ({
  _tag: "NetworkError",
  message,
});
