#!/bin/bash

# Variables for source and destination subscriptions and tenants
SOURCE_SUBSCRIPTION="source-subscription-id"
SOURCE_TENANT_ID="source-tenant-id"
DESTINATION_SUBSCRIPTION="destination-subscription-id"
DESTINATION_TENANT_ID="destination-tenant-id"

# Log in to the source account and set the subscription
echo "Logging into source subscription: $SOURCE_SUBSCRIPTION"
az login --tenant "$SOURCE_TENANT_ID"
az account set --subscription "$SOURCE_SUBSCRIPTION"

# Step 1: List all active users from the source tenant
echo "Fetching active users from source subscription..."
az ad user list --query '[?accountEnabled==`true`].{displayName: displayName, userPrincipalName: userPrincipalName, objectId: objectId}' -o json > users.json

# Step 2: List all RBAC role assignments from the source subscription
echo "Fetching RBAC role assignments from source subscription..."
az role assignment list --all --query '[].{PrincipalId: principalId, RoleName: roleDefinitionName, Scope: scope}' -o json > role_assignments.json

# Log in to the destination account and set the subscription
echo "Logging into destination subscription: $DESTINATION_SUBSCRIPTION"
az login --tenant "$DESTINATION_TENANT_ID"
az account set --subscription "$DESTINATION_SUBSCRIPTION"

# Step 3: Create users in the destination tenant
echo "Creating users in destination tenant..."
cat users.json | jq -c '.[]' | while read user; do
    displayName=$(echo "$user" | jq -r '.displayName')
    userPrincipalName=$(echo "$user" | jq -r '.userPrincipalName')
    objectId=$(echo "$user" | jq -r '.objectId')

    # Check if the user already exists in the destination tenant
    existing_user=$(az ad user show --id "$userPrincipalName" --query 'objectId' -o tsv 2>/dev/null)
    
    if [ -z "$existing_user" ]; then
        # Create the user in the destination tenant
        echo "Creating user: $displayName ($userPrincipalName)"
        az ad user create --display-name "$displayName" --user-principal-name "$userPrincipalName" --password "TempPass@1234" --force-change-password-next-sign-in true
    else
        echo "User $userPrincipalName already exists in destination."
    fi
done

# Step 4: Assign RBAC roles to the created users in the destination subscription
echo "Assigning RBAC roles to users in destination subscription..."
cat role_assignments.json | jq -c '.[]' | while read role; do
    principalId=$(echo "$role" | jq -r '.PrincipalId')
    roleName=$(echo "$role" | jq -r '.RoleName')
    scope=$(echo "$role" | jq -r '.Scope')

    # Check if the user exists in the destination tenant by userPrincipalName
    userPrincipalName=$(az ad user show --id "$principalId" --query 'userPrincipalName' -o tsv 2>/dev/null)

    if [ -n "$userPrincipalName" ]; then
        echo "Assigning role $roleName at scope $scope to user $userPrincipalName"
        az role assignment create --assignee "$userPrincipalName" --role "$roleName" --scope "$scope"
    else
        echo "User with principal ID $principalId not found in destination. Skipping role assignment."
    fi
done

echo "Migration of users and RBAC roles completed."
