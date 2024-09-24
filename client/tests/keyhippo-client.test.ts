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
    // Optionally, clean up RBAC and ABAC entries if created during tests
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
    const otherSupabase = createClient(
      process.env.SUPABASE_URL!,
      process.env.SUPABASE_ANON_KEY!,
    );
    const { data: newUserData, error: signInError } =
      await otherSupabase.auth.signInAnonymously();

    if (signInError || !newUserData.user) {
      throw new Error(`Error signing in as new user: ${signInError?.message}`);
    }

    const newUserId = newUserData.user.id;
    const newUserKeyHippo = new KeyHippo(otherSupabase, console);
    const newUserKeyInfo = await newUserKeyHippo.createApiKey(
      newUserId,
      "Another User's Key",
    );

    // Use the original user's KeyHippo client
    const originalUserKeyHippo = testSetup.keyHippo;

    // Attempt to rotate the new user's API key as the original user
    await expect(
      originalUserKeyHippo.rotateApiKey(testSetup.userId, newUserKeyInfo.id),
    ).rejects.toThrow("[KeyHippo] Unauthorized: You do not own this API key");

    // Clean up
    await newUserKeyHippo.revokeApiKey(newUserId, newUserKeyInfo.id);
  });

  describe("KeyHippo Client RBAC and ABAC Tests", () => {
    it("should add user to a group with a role (RBAC)", async () => {
      const groupId = testSetup.adminGroupId;
      const roleName = "Admin";

      // Add user to a group with a role
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        groupId,
        roleName,
      );

      // Query claims cache directly to verify
      const claimsCacheResult = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId)
        .single();

      console.log("RBAC Claims:", claimsCacheResult.data!.rbac_claims);

      expect(claimsCacheResult.data).toBeDefined();
      expect(claimsCacheResult.data!.rbac_claims).toBeDefined();
      expect(
        claimsCacheResult.data!.rbac_claims[testSetup.adminGroupId],
      ).toContain(roleName);
    });

    it("should set parent role in RBAC hierarchy", async () => {
      const childRoleId = testSetup.userRoleId;
      const parentRoleId = testSetup.adminRoleId;

      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // Instead of checking the returned data, verify the role hierarchy directly
      const roleHierarchy = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("roles")
        .select("parent_role_id")
        .eq("id", childRoleId)
        .single();

      expect(roleHierarchy.data).toBeDefined();
      expect(roleHierarchy.data!.parent_role_id).toBe(parentRoleId);
    });

    it("should assign a parent role to a child role", async () => {
      const childRoleId = testSetup.userRoleId; // 'User' role
      const parentRoleId = testSetup.adminRoleId; // 'Admin' role

      // Assign the parent role
      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // Verify the parent role assignment
      const parentRoleResult = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("roles")
        .select("parent_role_id")
        .eq("id", childRoleId)
        .single();

      expect(parentRoleResult.data).toBeDefined();
      expect(parentRoleResult.data!.parent_role_id).toBe(parentRoleId);
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
      const createdPolicy = await testSetup.serviceSupabase
        .schema("keyhippo_abac")
        .from("policies")
        .select("*")
        .eq("name", policyName)
        .single();

      expect(createdPolicy.data).toBeDefined();
      expect(createdPolicy.data.description).toBe(description);
      expect(JSON.parse(createdPolicy.data.policy)).toEqual(policy);
    });

    it("should create and retrieve a policy (ABAC)", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "IT",
      };
      const description = "Test Policy";

      // Create the ABAC policy
      await testSetup.keyHippo.createPolicy("Test Policy", description, policy);

      // Verify the policy was created
      const createdPolicy = await testSetup.serviceSupabase
        .schema("keyhippo_abac")
        .from("policies")
        .select("description, policy")
        .eq("name", "Test Policy")
        .single();

      console.log("Created Policy:", createdPolicy.data!.policy);

      expect(createdPolicy.data).toBeDefined();
      expect(createdPolicy.data!.description).toBe(description);
      expect(JSON.parse(createdPolicy.data!.policy)).toEqual(policy);
    });

    it("should evaluate ABAC policies for a user", async () => {
      const userId = testSetup.userId;
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      // Create the policy
      await testSetup.keyHippo.createPolicy(
        "Test Policy",
        "Test Policy Description",
        policy,
      );

      // Set the user's attribute
      await testSetup.keyHippo.setUserAttribute(
        userId,
        "department",
        "engineering",
      );

      // Evaluate the policies
      const result = await testSetup.keyHippo.evaluatePolicies(userId);

      console.log("Policy evaluation result:", result);
      expect(result).toBe(true);
    });

    it("should retrieve user attributes (ABAC)", async () => {
      const attribute = "department";
      const expectedValue = "engineering";

      // Ensure the user has the attribute set
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        attribute,
        expectedValue,
      );

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

      // Try creating the same policy again, expecting no error due to ON CONFLICT DO NOTHING
      await testSetup.keyHippo.createPolicy(policyName, description, policy);

      // Verify that only one policy exists
      const policies = await testSetup.serviceSupabase
        .schema("keyhippo_abac")
        .from("policies")
        .select("*")
        .eq("name", policyName);

      expect(policies.data?.length).toBe(1);
    });
  });
});
