import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { KeyHippo } from "../src/index";
import { setupTest, TestSetup } from "./testSetup";
import { createClient } from "@supabase/supabase-js";

let testSetup: TestSetup;

beforeAll(async () => {
  testSetup = await setupTest();
});

const teardown = async () => {
  try {
    const keyInfos = await testSetup.keyHippo.loadApiKeyInfo(testSetup.userId);
    for (const keyInfo of keyInfos) {
      await testSetup.keyHippo.revokeApiKey(testSetup.userId, keyInfo.id);
    }
  } catch (error) {
    console.error("Cleanup failed", error);
  }
};

afterAll(teardown);

describe("KeyHippo Client Tests", () => {
  it("should create an API key", async () => {
    const keyDescription = "Test Key";
    const result = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );
    expect(result).toHaveProperty("id");
    expect(result).toHaveProperty("description");
    expect(result).toHaveProperty("apiKey");
    expect(result.status).toBe("success");
    expect(result.description).toContain(keyDescription);
  });

  it("should load API key info", async () => {
    const keyInfos = await testSetup.keyHippo.loadApiKeyInfo(testSetup.userId);

    expect(Array.isArray(keyInfos)).toBe(true);
    expect(keyInfos.length).toBeGreaterThan(0);
    expect(keyInfos[0]).toHaveProperty("id");
    expect(keyInfos[0]).toHaveProperty("description");
  });

  it("should get all key metadata", async () => {
    const metadata = await testSetup.keyHippo.getAllKeyMetadata(
      testSetup.userId,
    );

    expect(Array.isArray(metadata)).toBe(true);
    expect(metadata.length).toBeGreaterThan(0);
    expect(metadata[0]).toHaveProperty("api_key_id");
    expect(metadata[0]).toHaveProperty("name");
    expect(metadata[0]).toHaveProperty("permission");
    expect(metadata[0]).toHaveProperty("last_used");
    expect(metadata[0]).toHaveProperty("created");
    expect(metadata[0]).toHaveProperty("revoked");
    expect(metadata[0]).toHaveProperty("total_uses");
    expect(metadata[0]).toHaveProperty("success_rate");
    expect(metadata[0]).toHaveProperty("total_cost");
  });

  it("should authenticate with an API key", async () => {
    const keyDescription = "Auth Test Key";
    const createdKeyInfo = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );
    const createdKey = createdKeyInfo.apiKey;
    const mockHeaders = new Headers({
      Authorization: `Bearer ${createdKey}`,
    });
    const { userId, supabase } =
      await testSetup.keyHippo.authenticate(mockHeaders);

    expect(userId).toBe(testSetup.userId);
    expect(supabase).toBeDefined();

    const { data: obtainedUserId, error: _ } = await supabase
      .schema("keyhippo")
      .rpc("get_uid_for_key", { user_api_key: createdKey });

    expect(obtainedUserId).toBe(userId);
  });

  it("should revoke an API key", async () => {
    const keyDescription = "Key to be revoked";
    const createdKeyInfo = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );

    await testSetup.keyHippo.revokeApiKey(testSetup.userId, createdKeyInfo.id);

    const keyInfos = await testSetup.keyHippo.loadApiKeyInfo(testSetup.userId);
    const revokedKey = keyInfos.find((key) => key.id === createdKeyInfo.id);

    expect(revokedKey).toBeUndefined();
  });

  it("should handle errors when creating an invalid API key", async () => {
    await expect(
      testSetup.keyHippo.createApiKey("", "Invalid Key"),
    ).rejects.toThrow("Error creating API key");
  });

  it("should handle errors when getting metadata for non-existent user", async () => {
    await expect(
      testSetup.keyHippo.getAllKeyMetadata("non-existent-user"),
    ).rejects.toThrow("Error getting API key metadata");
  });

  it("should rotate an API key", async () => {
    const keyDescription = "Key to Rotate";
    const createdKeyInfo = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );

    const rotatedKeyInfo = await testSetup.keyHippo.rotateApiKey(
      testSetup.userId,
      createdKeyInfo.id,
    );

    expect(rotatedKeyInfo).toHaveProperty("id");
    expect(rotatedKeyInfo).toHaveProperty("apiKey");
    expect(rotatedKeyInfo.status).toBe("success");

    // Verify the old API key is revoked
    const keyInfos = await testSetup.keyHippo.loadApiKeyInfo(testSetup.userId);
    const oldKeyExists = keyInfos.some((key) => key.id === createdKeyInfo.id);
    expect(oldKeyExists).toBe(false);

    // Verify the new API key works
    const mockHeaders = new Headers({
      Authorization: `Bearer ${rotatedKeyInfo.apiKey}`,
    });
    const { userId, supabase } =
      await testSetup.keyHippo.authenticate(mockHeaders);

    expect(userId).toBe(testSetup.userId);
    expect(supabase).toBeDefined();
  });

  it("should handle errors when rotating a non-existent API key", async () => {
    await expect(
      testSetup.keyHippo.rotateApiKey(testSetup.userId, "invalid-api-key-id"),
    ).rejects.toThrow("Error rotating API key");
  });

  it("should not rotate an API key owned by another user", async () => {
    // Create another user and API key with a separate Supabase client
    const supabase = createClient(
      process.env.SUPABASE_URL!,
      process.env.SUPABASE_ANON_KEY!,
    );
    const { data: newUserData } = await supabase.auth.signInAnonymously();
    const newUserId = newUserData.user!.id;
    const newUserKeyHippo = new KeyHippo(supabase, console);
    const newUserKeyInfo = await newUserKeyHippo.createApiKey(
      newUserId,
      "Another User's Key",
    );

    // Use the original user's Supabase client
    const originalUserKeyHippo = testSetup.keyHippo;

    // Attempt to rotate the new user's API key as the original user
    await expect(
      originalUserKeyHippo.rotateApiKey(testSetup.userId, newUserKeyInfo.id),
    ).rejects.toThrow("Error rotating API key");

    // Clean up
    await newUserKeyHippo.revokeApiKey(newUserId, newUserKeyInfo.id);
  });

  describe("KeyHippo Client RBAC and ABAC Tests", () => {
    it("should add user to a group with a role (RBAC)", async () => {
      const groupId = "test-group-id";
      const roleName = "admin";

      // Add user to a group with a role
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        groupId,
        roleName,
      );

      // Query claims cache directly to verify
      const claimsCacheResult = await testSetup.supabase
        .from("keyhippo_rbac.claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId);

      expect(claimsCacheResult.data).toBeDefined();
      expect(claimsCacheResult.data?.[0]?.rbac_claims).toBeDefined();
      expect(claimsCacheResult.data?.[0]?.rbac_claims[groupId]).toContain(
        roleName,
      );
    });

    it("should set parent role in RBAC hierarchy", async () => {
      const childRoleId = "test-child-role-id";
      const parentRoleId = "test-parent-role-id";

      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // You can assert by checking if the parent role is assigned correctly in the DB.
      // For example, you might query Supabase to fetch the child role's parent.
      const parentRoleResult = await testSetup.supabase
        .from("keyhippo_rbac.roles")
        .select("parent_role_id")
        .eq("id", childRoleId);

      expect(parentRoleResult.data![0].parent_role_id).toBe(parentRoleId);
    });
    it("should assign a parent role to a child role", async () => {
      const childRoleId = "child-role-id";
      const parentRoleId = "parent-role-id";

      // Assign the parent role
      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // Verify the parent role assignment
      const parentRoleResult = await testSetup.supabase
        .from("keyhippo_rbac.roles")
        .select("parent_role_id")
        .eq("id", childRoleId);

      expect(parentRoleResult.data).toBeDefined();
      expect(parentRoleResult.data?.[0]?.parent_role_id).toBe(parentRoleId);
    });

    it("should create an ABAC policy", async () => {
      const policyName = "test-policy";
      const description = "Test Policy Description";
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      await testSetup.keyHippo.createPolicy(policyName, description, policy);

      // Verify the policy creation in the database
      const createdPolicy = await testSetup.supabase
        .from("keyhippo_abac.policies")
        .select("*")
        .eq("name", policyName);

      expect(createdPolicy.data).toBeDefined();
      expect(createdPolicy.data![0].description).toBe(description);
      expect(createdPolicy.data![0].policy).toEqual(policy);
    });
    it("should create and retrieve a policy (ABAC)", async () => {
      const policy = { attribute: "department", type: "equals", value: "IT" };
      const description = "Test Policy";

      // Create the ABAC policy
      await testSetup.keyHippo.createPolicy("Test Policy", description, policy);

      // Verify the policy was created
      const createdPolicy = await testSetup.supabase
        .from("keyhippo_abac.policies")
        .select("description, policy")
        .eq("name", "Test Policy");

      expect(createdPolicy.data).toBeDefined();
      expect(createdPolicy.data?.[0]?.description).toBe(description);
      expect(createdPolicy.data?.[0]?.policy).toEqual(policy);
    });

    it("should evaluate ABAC policies for a user", async () => {
      const userId = testSetup.userId;

      const result = await testSetup.keyHippo.evaluatePolicies(userId);

      expect(result).toBe(true); // Assuming the policies allow access for this test case
    });

    it("should retrieve user attributes (ABAC)", async () => {
      const attribute = "department";
      const expectedValue = "engineering";

      // Assuming the user has the attribute set in the system
      const attributeValue = await testSetup.keyHippo.getUserAttribute(
        testSetup.userId,
        attribute,
      );

      expect(attributeValue).toEqual(expectedValue);
    });

    it("should fail when creating a duplicate policy", async () => {
      const policyName = "duplicate-policy";
      const description = "Duplicate Policy";
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      // Create the policy once
      await testSetup.keyHippo.createPolicy(policyName, description, policy);

      // Try creating the same policy again, expecting an error
      await expect(
        testSetup.keyHippo.createPolicy(policyName, description, policy),
      ).rejects.toThrow("Error creating policy");
    });
  });
});
