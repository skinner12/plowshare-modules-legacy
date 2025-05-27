#!/bin/bash
#
# nitroflare.sh - Nitroflare upload module for plowshare
# Copyright (c) 2024 Plowshare team
#
# This file is part of Plowshare.
#
# Plowshare is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Plowshare is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Plowshare.  If not, see <http://www.gnu.org/licenses/>.

MODULE_NITROFLARE_REGEXP_URL='https\?://\(www\.\)\?nitroflare\.com/'

MODULE_NITROFLARE_UPLOAD_OPTIONS="
AUTH,a,auth,a=USER:PASSWORD,User account or token
FOLDER,,folder,s=FOLDER_ID,Folder ID to upload files to (premium only)
DESCRIPTION,d,description,S=DESCRIPTION,Set file description
"
MODULE_NITROFLARE_UPLOAD_REMOTE_SUPPORT=no
MODULE_NITROFLARE_PROBE_OPTIONS=""

# Static function. Detect if auth is token or username:password
# $1: authentication string
# Returns: 0 if token, 1 if username:password
nitroflare_is_token() {
    local -r AUTH=$1
    
    # Token is a 40-character hex string (SHA1)
    if [[ "$AUTH" =~ ^[a-f0-9]{40}$ ]]; then
        return 0
    fi
    
    # Check if it contains a colon (username:password format)
    if [[ "$AUTH" =~ : ]]; then
        return 1
    fi
    
    # Default to token if no colon found
    return 0
}

# Static function. Login and get user token
# $1: authentication (username:password)
# stdout: user token
nitroflare_login() {
    local -r AUTH=$1
    local USERNAME PASSWORD JSON TOKEN
    
    split_auth "$AUTH" USERNAME PASSWORD || return
    
    log_debug "Nitroflare: attempting login for user: $USERNAME"
    
    # Login request
    JSON=$(curl -s --fail \
        -d "email=$USERNAME" \
        -d "password=$PASSWORD" \
        "https://nitroflare.com/api/v2/user/login") || return
    
    # Check for errors
    if match '"result":"success"' "$JSON"; then
        TOKEN=$(parse_json 'token' <<< "$JSON") || return
        log_debug "Login successful, token: $TOKEN"
        echo "$TOKEN"
        return 0
    else
        local ERROR_MSG=$(parse_json 'message' <<< "$JSON" 2>/dev/null)
        log_error "Login failed: ${ERROR_MSG:-Unknown error}"
        return $ERR_LOGIN_FAILED
    fi
}

# Upload a file to Nitroflare
# $1: cookie file (unused)
# $2: input file (with full path)
# $3: remote filename
# stdout: download link
nitroflare_upload() {
    local -r COOKIE_FILE=$1
    local -r FILE=$2
    local -r DESTFILE=$3
    local USER_TOKEN SERVER_URL JSON DOWNLOAD_URL
    local FILE_SIZE
    
    # Module requires authentication
    if [ -z "$AUTH" ]; then
        log_error "Nitroflare: authentication required"
        return $ERR_LINK_NEED_PERMISSIONS
    fi
    
    # Check if AUTH is a token or username:password
    if nitroflare_is_token "$AUTH"; then
        USER_TOKEN="$AUTH"
        log_debug "Using provided token: $USER_TOKEN"
    else
        # Login to get token
        USER_TOKEN=$(nitroflare_login "$AUTH") || return
    fi
    
    # Get file size for logging
    FILE_SIZE=$(get_filesize "$FILE") || return
    log_debug "File size: $FILE_SIZE bytes"
    
    # Get upload server
    log_debug "Getting upload server"
    SERVER_URL=$(curl -s --fail \
        "http://nitroflare.com/plugins/fileupload/getServer") || {
        log_error "Failed to get upload server"
        return $ERR_FATAL
    }
    
    # Remove quotes if present
    SERVER_URL=$(echo "$SERVER_URL" | tr -d '"')
    log_debug "Upload server: $SERVER_URL"
    
    # Validate server URL
    if ! match '^https\?://' "$SERVER_URL"; then
        log_error "Invalid server URL received: $SERVER_URL"
        return $ERR_FATAL
    fi
    
    # Prepare multipart upload
    local -a CURL_ARGS
    CURL_ARGS=( \
        -F "user=$USER_TOKEN" \
        -F "files=@$FILE;filename=$DESTFILE" \
    )
    
    # Add folder if specified (premium feature)
    if [ -n "$FOLDER" ]; then
        CURL_ARGS+=( -F "folder=$FOLDER" )
        log_debug "Uploading to folder: $FOLDER"
    fi
    
    # Add description if specified
    if [ -n "$DESCRIPTION" ]; then
        CURL_ARGS+=( -F "description=$DESCRIPTION" )
    fi
    
    # Perform file upload
    log_debug "Uploading file: $DESTFILE"
    JSON=$(curl -s --fail \
        "${CURL_ARGS[@]}" \
        "$SERVER_URL") || {
        log_error "Upload request failed"
        return $ERR_FATAL
    }
    
    log_debug "Upload response: $JSON"
    
    # Parse response - Nitroflare returns a files array on success
    if match '"files":\[' "$JSON" && match '"url":' "$JSON"; then
        # Extract URL from the files array
        DOWNLOAD_URL=$(echo "$JSON" | grep -o '"url":"[^"]*"' | head -1 | sed 's/"url":"\([^"]*\)"/\1/' | sed 's/\\//g')
        
        if [ -n "$DOWNLOAD_URL" ]; then
            log_debug "Upload successful"
            echo "$DOWNLOAD_URL"
            return 0
        else
            log_error "Could not extract download URL from response"
            return $ERR_FATAL
        fi
    elif match '"result":"error"' "$JSON"; then
        local ERROR_MSG=$(parse_json 'message' <<< "$JSON" 2>/dev/null)
        log_error "Upload failed: ${ERROR_MSG:-Unknown error}"
        return $ERR_FATAL
    else
        log_error "Unexpected response format"
        log_error "Response: $JSON"
        return $ERR_FATAL
    fi
}

# Probe a download URL
# $1: cookie file (unused)
# $2: Nitroflare url
# $3: requested capability list
# stdout: 1 capability per line
nitroflare_probe() {
    local -r COOKIE_FILE=$1
    local -r URL=$2
    local -r REQ_IN=$3
    local FILE_ID JSON FILE_NAME FILE_SIZE
    
    # Extract file ID from URL
    FILE_ID=$(parse . '/view/\([A-Z0-9]\+\)' <<< "$URL") || \
        FILE_ID=$(parse . '/watch/\([A-Z0-9]\+\)' <<< "$URL") || return
    
    # Get file info (no auth required for basic info)
    JSON=$(curl -s --fail \
        "https://nitroflare.com/api/v2/file/info?file=$FILE_ID") || return
    
    if ! match '"result":"success"' "$JSON"; then
        return $ERR_LINK_DEAD
    fi
    
    REQ_OUT=c
    
    if [[ $REQ_IN = *f* ]]; then
        FILE_NAME=$(parse_json 'name' <<< "$JSON") && \
            echo "$FILE_NAME" && REQ_OUT="${REQ_OUT}f"
    fi
    
    if [[ $REQ_IN = *s* ]]; then
        FILE_SIZE=$(parse_json 'size' <<< "$JSON") && \
            echo "$FILE_SIZE" && REQ_OUT="${REQ_OUT}s"
    fi
    
    echo $REQ_OUT
}
