import { KeyHippo } from "../src/index";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

export interface TestSetup {
  keyHippo: KeyHippo;
  userId: string;
  supabase: SupabaseClient; // Anonymous client for test operations
  serviceSupabase: SupabaseClient; // Service client for setup operations
  adminGroupId: string;
  userGroupId: string;
  adminRoleId: string;
  userRoleId: string;
}

export async function setupTest(): Promise<TestSetup> {
  // 1. Initialize the Service Client (bypasses RLS)
  const serviceSupabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
  );

  // 2. Initialize the Anonymous Client
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
  );

  // 3. Sign in anonymously with the Anonymous Client
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error || !data.user) {
    throw new Error("Error signing in anonymously");
  }

  const userId = data.user.id;

  // 4. Initialize KeyHippo with the Anonymous Client
  const keyHippo = new KeyHippo(supabase, console);

  // 5. Use the Service Client to fetch existing groups
  const { data: groups, error: groupsError } = await serviceSupabase
    .schema("keyhippo_rbac")
    .from("groups")
    .select("id, name");

  if (groupsError) {
    throw new Error(`Error fetching groups: ${groupsError.message}`);
  }

  // 6. Define required groups
  const requiredGroups = ["Admin Group", "User Group"];
  const existingGroupNames = groups.map((group) => group.name);
  const missingGroups = requiredGroups.filter(
    (groupName) => !existingGroupNames.includes(groupName),
  );

  // 7. Create missing groups or get existing group info
  for (const groupName of requiredGroups) {
    let group = groups.find((g) => g.name === groupName);
    if (!group) {
      const { data: newGroup, error: insertGroupError } = await serviceSupabase
        .schema("keyhippo_rbac")
        .from("groups")
        .insert({ name: groupName })
        .select("id, name");

      if (insertGroupError && insertGroupError.code !== "23505") {
        // Handle duplicate key error gracefully
        throw new Error(
          `Error creating group "${groupName}": ${insertGroupError.message}`,
        );
      }

      if (newGroup) {
        group = newGroup[0];
        groups.push(group);
      } else {
        // If the group wasn't created because it already exists, fetch it again
        const { data: fetchedGroup, error: fetchError } = await serviceSupabase
          .schema("keyhippo_rbac")
          .from("groups")
          .select("id, name")
          .eq("name", groupName)
          .single();

        if (fetchError) {
          throw new Error(
            `Error fetching group "${groupName}": ${fetchError.message}`,
          );
        }

        group = fetchedGroup;
        groups.push(group);
      }
    }
  }

  // 8. Assign group IDs
  const adminGroup = groups.find((group) => group.name === "Admin Group");
  const userGroup = groups.find((group) => group.name === "User Group");

  if (!adminGroup || !userGroup) {
    throw new Error("Required groups (Admin Group and User Group) not found");
  }

  // 9. Fetch existing roles
  const { data: roles, error: rolesError } = await serviceSupabase
    .schema("keyhippo_rbac")
    .from("roles")
    .select("id, name, group_id");
  if (rolesError) {
    throw new Error(`Error fetching roles: ${rolesError.message}`);
  }

  // 10. Define required roles
  const requiredRoles = [
    { name: "Admin", groupId: adminGroup.id },
    { name: "User", groupId: userGroup.id },
  ];
  const existingRoles = roles.map((role) => ({
    name: role.name,
    groupId: role.group_id,
  }));
  const missingRoles = requiredRoles.filter(
    (requiredRole) =>
      !existingRoles.some(
        (existingRole) =>
          existingRole.name === requiredRole.name &&
          existingRole.groupId === requiredRole.groupId,
      ),
  );

  // 11. Create missing roles or get existing role info
  for (const requiredRole of requiredRoles) {
    let role = roles.find(
      (r) =>
        r.name === requiredRole.name && r.group_id === requiredRole.groupId,
    );

    if (!role) {
      const { data: newRole, error: insertRoleError } = await serviceSupabase
        .schema("keyhippo_rbac")
        .from("roles")
        .insert({ name: requiredRole.name, group_id: requiredRole.groupId })
        .select("id, name, group_id");

      if (insertRoleError && insertRoleError.code !== "23505") {
        // Handle duplicate key error gracefully
        throw new Error(
          `Error creating role "${requiredRole.name}": ${insertRoleError.message}`,
        );
      }

      if (newRole) {
        role = newRole[0];
        roles.push(role);
      } else {
        // If the role wasn't created because it already exists, fetch it again
        const { data: fetchedRole, error: fetchError } = await serviceSupabase
          .schema("keyhippo_rbac")
          .from("roles")
          .select("id, name, group_id")
          .eq("name", requiredRole.name)
          .eq("group_id", requiredRole.groupId)
          .single();

        if (fetchError) {
          throw new Error(
            `Error fetching role "${requiredRole.name}": ${fetchError.message}`,
          );
        }

        role = fetchedRole;
        roles.push(role);
      }
    }
  }

  // 12. Assign role IDs
  const adminRole = roles.find(
    (role) => role.name === "Admin" && role.group_id === adminGroup.id,
  );
  const userRole = roles.find(
    (role) => role.name === "User" && role.group_id === userGroup.id,
  );
  if (!adminRole || !userRole) {
    throw new Error("Required roles (Admin and User) not found");
  }

  return {
    keyHippo,
    userId,
    supabase, // Anonymous client
    serviceSupabase, // Service client
    adminGroupId: adminGroup.id,
    userGroupId: userGroup.id,
    adminRoleId: adminRole.id,
    userRoleId: userRole.id,
  };
}
