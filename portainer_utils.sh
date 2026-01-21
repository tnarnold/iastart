#!/bin/bash

# Utility script to deploy stacks via Portainer API
# Requires: curl, jq

PORTAINER_API_URL="https://127.0.0.1:9443/api"

check_deps() {
    if ! command -v jq &> /dev/null; then
        echo "[INFO] Installing jq..."
        apt-get update -qq && apt-get install -y -qq jq
    fi
}

authenticate() {
    local username=$1
    local password=$2
    
    echo "[INFO] Authenticating with Portainer..."
    
    # Wait for API to be ready
    local max_retries=30
    local count=0
    while ! curl -k -s --fail "$PORTAINER_API_URL/status" > /dev/null; do
        sleep 2
        count=$((count+1))
        if [ $count -ge $max_retries ]; then
            echo "[ERROR] Portainer API not available at $PORTAINER_API_URL"
            return 1
        fi
    done

    AUTH_RESPONSE=$(curl -k -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"$username\",\"Password\":\"$password\"}")

    JWT=$(echo "$AUTH_RESPONSE" | jq -r .jwt)

    if [ "$JWT" == "null" ] || [ -z "$JWT" ]; then
        echo "[ERROR] Authentication failed."
        echo "Response: $AUTH_RESPONSE"
        return 1
    fi
    
    echo "[OK] Authenticated successfully."
}

ensure_local_endpoint() {
    # Debug: Check JWT
    if [ -z "$JWT" ]; then
        echo "[DEBUG] JWT is empty in ensure_local_endpoint!" >&2
    fi

    # Check if any endpoint exists
    local response
    response=$(curl -k -s -H "Authorization: Bearer $JWT" "$PORTAINER_API_URL/endpoints")
    
    # Check for empty response or empty array using jq
    local count
    count=$(echo "$response" | jq '. | length')

    # echo "[DEBUG] Endpoints count: $count" >&2

    if [ "$count" == "0" ] || [ -z "$response" ]; then
        echo "[INFO] No environments found (count=$count). Creating 'local' environment..." >&2
        
        # Create local endpoint (Type 1 = Docker)
        # Using form-data as required by some Portainer versions to avoid "Invalid environment name"
        
        local create_response
        create_response=$(curl -k -s -X POST "$PORTAINER_API_URL/endpoints" \
            -H "Authorization: Bearer $JWT" \
            -F "Name=local" \
            -F "URL=unix:///var/run/docker.sock" \
            -F "PublicURL=local" \
            -F "EndpointCreationType=1")
            
        local new_id
        new_id=$(echo "$create_response" | jq -r .Id)
        
        if [ "$new_id" != "null" ] && [ -n "$new_id" ]; then
            echo "[OK] Created 'local' environment (ID: $new_id)" >&2
        else
            echo "[ERROR] Failed to create environment. Response: $create_response" >&2
            return 1
        fi
    fi
}

get_endpoint_id() {
    # Ensure at least one endpoint exists
    ensure_local_endpoint

    # Fetch endpoints again
    local response
    response=$(curl -k -s -H "Authorization: Bearer $JWT" "$PORTAINER_API_URL/endpoints")
    
    # Extract first endpoint ID
    local id
    id=$(echo "$response" | jq -r '.[0].Id // empty')
    
    if [ -z "$id" ] || [ "$id" == "null" ]; then
        # Print error to stderr so it's not captured as the ID
        echo "[ERROR] No endpoints found after check. Response: $response" >&2
        return 1
    fi
    echo "$id"
}

deploy_stack() {
    local stack_name=$1
    local stack_file=$2
    
    if [ -z "$JWT" ]; then
        echo "[ERROR] Not authenticated."
        return 1
    fi
    
    if [ ! -f "$stack_file" ]; then
        echo "[ERROR] Stack file not found: $stack_file"
        return 1
    fi

    # Capture output of get_endpoint_id. If it fails, output went to stderr.
    local endpoint_id
    endpoint_id=$(get_endpoint_id)
    if [ $? -ne 0 ] || [ -z "$endpoint_id" ]; then
        echo "[ERROR] Could not retrieve Endpoint ID."
        return 1
    fi

    # Read file content
    local stack_content
    stack_content=$(cat "$stack_file")
    
    # Check if stack exists
    local existing_stack
    existing_stack=$(curl -k -s -H "Authorization: Bearer $JWT" "$PORTAINER_API_URL/stacks" | jq -r ".[] | select(.Name == \"$stack_name\")")
    local stack_id
    stack_id=$(echo "$existing_stack" | jq -r .Id)

    if [ ! -z "$stack_id" ] && [ "$stack_id" != "null" ]; then
        echo "[INFO] Updating existing stack: $stack_name (ID: $stack_id)"
        
        jq -n --arg content "$stack_content" \
           '{stackFileContent: $content, prune: true}' > /tmp/stack_payload.json

        local http_code
        http_code=$(curl -k -s -o /dev/null -w "%{http_code}" -X PUT \
            "$PORTAINER_API_URL/stacks/$stack_id?endpointId=$endpoint_id" \
            -H "Authorization: Bearer $JWT" \
            -H "Content-Type: application/json" \
            -d @/tmp/stack_payload.json)
            
        if [ "$http_code" -eq 200 ]; then
            echo "[OK] Stack $stack_name updated."
        else
            echo "[ERROR] Failed to update stack $stack_name. HTTP Code: $http_code"
            # Debug: show response body
             curl -k -X PUT \
            "$PORTAINER_API_URL/stacks/$stack_id?endpointId=$endpoint_id" \
            -H "Authorization: Bearer $JWT" \
            -H "Content-Type: application/json" \
            -d @/tmp/stack_payload.json
            echo
            return 1
        fi

    else
        echo "[INFO] Creating new stack: $stack_name"

        # Get Swarm ID
        local swarm_id
        swarm_id=$(docker info --format '{{.Swarm.Cluster.ID}}')
        
        if [ -z "$swarm_id" ]; then
             echo "[ERROR] Could not retrieve Swarm ID. Ensure you are on a Swarm Manager."
             return 1
        fi
        
        jq -n --arg name "$stack_name" --arg content "$stack_content" --arg swarm_id "$swarm_id" \
           '{name: $name, stackFileContent: $content, swarmID: $swarm_id, env: []}' > /tmp/stack_payload.json

        local http_code
        http_code=$(curl -k -s -o /dev/null -w "%{http_code}" -X POST \
            "$PORTAINER_API_URL/stacks/create/swarm/string?endpointId=$endpoint_id" \
            -H "Authorization: Bearer $JWT" \
            -H "Content-Type: application/json" \
            -d @/tmp/stack_payload.json)
        
        # Check if http_code is valid integer
        if [[ ! "$http_code" =~ ^[0-9]+$ ]]; then
             echo "[ERROR] Curl returned invalid HTTP code: '$http_code'"
             return 1
        fi

        if [ "$http_code" -eq 200 ]; then
            echo "[OK] Stack $stack_name created."
        else
            echo "[ERROR] Failed to create stack $stack_name. HTTP Code: $http_code"
            # Debug output
            echo "Debug response body:"
            curl -k -X POST \
            "$PORTAINER_API_URL/stacks/create/swarm/string?endpointId=$endpoint_id" \
            -H "Authorization: Bearer $JWT" \
            -H "Content-Type: application/json" \
            -d @/tmp/stack_payload.json
            echo
            return 1
        fi
    fi
}
