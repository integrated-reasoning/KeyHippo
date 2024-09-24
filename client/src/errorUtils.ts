import { AppError } from "./types";

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

export const isUnauthorizedError = (
  error: any,
): error is { _tag: "UnauthorizedError"; message: string } => {
  return isAppError(error) && error._tag === "UnauthorizedError";
};

export const isAuthenticationError = (
  error: any,
): error is { _tag: "AuthenticationError"; message: string } => {
  return isAppError(error) && error._tag === "AuthenticationError";
};

export const createUnauthorizedError = (message: string): AppError => ({
  _tag: "UnauthorizedError",
  message,
});

export const createAuthenticationError = (message: string): AppError => ({
  _tag: "AuthenticationError",
  message,
});

export const createDatabaseError = (message: string): AppError => ({
  _tag: "DatabaseError",
  message,
});

export const createValidationError = (message: string): AppError => ({
  _tag: "ValidationError",
  message,
});

export const createNetworkError = (message: string): AppError => ({
  _tag: "NetworkError",
  message,
});
