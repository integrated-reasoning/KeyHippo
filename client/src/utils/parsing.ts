import {
  ApiKeyInfo,
  ApiKeyMetadata,
  CompleteApiKeyInfo,
  RotateApiKeyResult,
} from "../types";

/**
 * Parses raw data into an array of ApiKeyInfo objects.
 * @param data - The raw data returned from the RPC call.
 * @returns An array of ApiKeyInfo objects.
 * @throws Error if the data is not an array or has an invalid structure.
 */
export const parseApiKeyInfo = (data: unknown): ApiKeyInfo[] => {
  if (data === null) {
    return [];
  }

  if (!Array.isArray(data)) {
    throw new Error(
      `Invalid data returned when loading API key info: ${JSON.stringify(data)}`,
    );
  }

  return data.map((item: any) => ({
    id: item.id,
    description: item.description,
  }));
};

/**
 * Parses raw data into an array of ApiKeyMetadata objects.
 * @param data - The raw data returned from the RPC call.
 * @returns An array of ApiKeyMetadata objects.
 * @throws Error if the data is not an array or has an invalid structure.
 */
export const parseApiKeyMetadata = (data: unknown): ApiKeyMetadata[] => {
  if (!Array.isArray(data)) {
    throw new Error("Invalid data returned when getting API key metadata");
  }

  return data.map((item: any) => ({
    api_key_id: item.api_key_id,
    name: item.name || "",
    permission: item.permission || "",
    last_used: item.last_used,
    created: item.created,
    revoked: item.revoked,
    total_uses: Number(item.total_uses),
    success_rate: Number(item.success_rate),
    total_cost: Number(item.total_cost),
  }));
};

/**
 * Parses raw data into a CompleteApiKeyInfo object after rotating an API key.
 * @param data - The raw data returned from the RPC call.
 * @returns A CompleteApiKeyInfo object containing the new API key details.
 * @throws Error if the data is not in the expected format or is empty.
 */
export const parseRotatedApiKeyInfo = (data: unknown): CompleteApiKeyInfo => {
  if (!Array.isArray(data) || data.length === 0) {
    throw new Error("No data returned after rotating API key");
  }

  const dataItem = data[0] as RotateApiKeyResult;

  if (!dataItem.new_api_key || !dataItem.new_api_key_id) {
    throw new Error("Invalid data structure returned after rotating API key");
  }

  return {
    id: dataItem.new_api_key_id,
    description: dataItem.description || "Rotated API Key",
    apiKey: dataItem.new_api_key,
    status: "success" as const,
  };
};

/**
 * Parses the evaluation result from the RPC data.
 * @param data - The raw data from the RPC call.
 * @returns A boolean indicating the evaluation result.
 * @throws Error if the data format is invalid.
 */
export const parseEvaluationResult = (data: unknown): boolean => {
  if (typeof data !== "boolean") {
    throw new Error("Invalid data format returned for policy evaluation");
  }
  return data;
};

/**
 * Validates the result of an RPC call.
 * @param result - The result object returned from the RPC call.
 * @param rpcName - The name of the RPC function being validated.
 * @throws Error if the RPC call resulted in an error.
 */
export const validateRpcResult = (result: any, rpcName: string): void => {
  if (result.error) {
    throw new Error(`Error in ${rpcName} RPC: ${result.error.message}`);
  }
};
