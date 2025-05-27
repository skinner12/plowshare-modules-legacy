#!/bin/bash
#
# rapidgator.sh - Rapidgator upload module for plowshare
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

MODULE_RAPIDGATOR_REGEXP_URL='https\?://\(www\.\)\?rapidgator\.net/'

MODULE_RAPIDGATOR_UPLOAD_OPTIONS="
AUTH,a,auth,a=USER:PASSWORD,User account
FOLDER,,folder,s=FOLDER_ID,Folder ID to upload files to
DESCRIPTION,d,description,S=DESCRIPTION,Set file description
TWOFA,,2fa,s=CODE,Two-factor authentication code
ASYNC,,async,,Asynchronous remote upload
"
MODULE_RAPIDGATOR_UPLOAD_REMOTE_SUPPORT=no
MODULE_RAPIDGATOR_PROBE_OPTIONS=""

# Static function. Proceed with login
# $1: authentication
# $2: cookie file
# $3: base URL
# $4: 2FA code (optional)
rapidgator_login() {
    local -r AUTH=$1
    local -r COOKIE_FILE=$2
    local -r BASE_URL=$3
    local -r TWOFA_CODE=$4
    local JSON TOKEN USERNAME PASSWORD LOGIN_URL

    log_debug "Rapidgator: attempting login"
    
    split_auth "$AUTH" USERNAME PASSWORD || return
    
    # URL encode credentials
    USERNAME=$(uri_encode_strict <<< "$USERNAME")
    PASSWORD=$(uri_encode_strict <<< "$PASSWORD")
    
    # Build login URL
    LOGIN_URL="$BASE_URL/api/v2/user/login?login=$USERNAME&password=$PASSWORD"
    
    # Add 2FA code if provided
    if [ -n "$TWOFA_CODE" ]; then
        LOGIN_URL="${LOGIN_URL}&code=$TWOFA_CODE"
        log_debug "Using 2FA code"
    fi
    
    # Login request with parameters in URL
    JSON=$(curl -s --fail "$LOGIN_URL") || return

    log_debug "Login response: $JSON"

    # Check for 2FA requirement
    if match '"status":401' "$JSON" && match 'code is required' "$JSON"; then
        log_error "Two-factor authentication required. Use --2fa=CODE option"
        return $ERR_LOGIN_FAILED
    fi

    # Check for errors
    if match '"status":200' "$JSON"; then
        TOKEN=$(parse_json 'token' <<< "$JSON") || return
        log_debug "Login successful, token: $TOKEN"
        echo "$TOKEN"
        return 0
    else
        log_error "Login failed: $JSON"
        return $ERR_LOGIN_FAILED
    fi
}

# Upload a file to Rapidgator
# $1: cookie file
# $2: input file (with full path)
# $3: remote filename
# stdout: download link
rapidgator_upload() {
    local -r COOKIE_FILE=$1
    local -r FILE=$2
    local -r DESTFILE=$3
    local -r BASE_URL='https://rapidgator.net'
    local TOKEN UPLOAD_DATA JSON UPLOAD_URL UPLOAD_ID STATE
    local FILE_SIZE FILE_HASH DOWNLOAD_URL

    # Module requires authentication
    if [ -z "$AUTH" ]; then
        log_error "Rapidgator: authentication required"
        return $ERR_LINK_NEED_PERMISSIONS
    fi

    # Login and get token
    TOKEN=$(rapidgator_login "$AUTH" "$COOKIE_FILE" "$BASE_URL" "$TWOFA") || return
    
    # Get file size
    FILE_SIZE=$(get_filesize "$FILE") || return
    log_debug "File size: $FILE_SIZE bytes"
    
    # Calculate MD5 hash
    log_debug "Calculating MD5 hash..."
    FILE_HASH=$(md5sum "$FILE" | cut -d' ' -f1) || return
    log_debug "File hash: $FILE_HASH"

    # Build upload request URL with required parameters
    local REQUEST_URL="$BASE_URL/api/v2/file/upload?token=$TOKEN"
    REQUEST_URL="${REQUEST_URL}&name=$(uri_encode_strict <<< "$DESTFILE")"
    REQUEST_URL="${REQUEST_URL}&hash=$FILE_HASH"
    REQUEST_URL="${REQUEST_URL}&size=$FILE_SIZE"
    
    # Add folder if specified
    if [ -n "$FOLDER" ]; then
        REQUEST_URL="${REQUEST_URL}&folder_id=$FOLDER"
    fi

    # Request upload URL
    log_debug "Requesting upload URL"
    JSON=$(curl -s --fail "$REQUEST_URL") || return
    log_debug "Upload request response: $JSON"

    # Parse upload server response
    if ! match '"status":200' "$JSON"; then
        log_error "Failed to get upload URL: $JSON"
        return $ERR_FATAL
    fi

    # Check upload state
    STATE=$(parse_json 'state' <<< "$JSON") || return
    log_debug "Upload state: $STATE"
    
    # If state is 2 (Done), file already exists - instant upload
    if [ "$STATE" = "2" ]; then
        log_debug "File already exists on server (instant upload)"
        # Extract URL using grep and sed
        DOWNLOAD_URL=$(echo "$JSON" | grep -o '"url":"[^"]*"' | tail -1 | sed 's/"url":"\([^"]*\)"/\1/' | sed 's/\\//g')
        if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
            log_error "Failed to extract download URL from response"
            return $ERR_FATAL
        fi
        echo "$DOWNLOAD_URL"
        return 0
    fi
    
    # If state is 0 (Uploading), we need to upload the file
    if [ "$STATE" = "0" ]; then
        UPLOAD_URL=$(parse_json 'url' <<< "$JSON") || return
        UPLOAD_ID=$(parse_json 'upload_id' <<< "$JSON") || return
        
        log_debug "Upload URL: $UPLOAD_URL"
        log_debug "Upload ID: $UPLOAD_ID"

        # Prepare multipart upload
        local -a CURL_ARGS
        CURL_ARGS=( \
            -F "file=@$FILE" \
        )

        # Perform file upload
        log_debug "Uploading file: $DESTFILE"
        JSON=$(curl --fail -s \
            "${CURL_ARGS[@]}" \
            "$UPLOAD_URL") || return
        
        log_debug "Upload response: $JSON"

        # Check upload response
        if match '"status":200' "$JSON"; then
            STATE=$(parse_json 'state' <<< "$JSON") || STATE="1"
            
            # If state is 2 (Done), we're finished
            if match '"state":2' "$JSON"; then
                DOWNLOAD_URL=$(echo "$JSON" | grep -o '"url":"[^"]*"' | tail -1 | sed 's/"url":"\([^"]*\)"/\1/' | sed 's/\\//g')
                if [ -n "$DOWNLOAD_URL" ] && [ "$DOWNLOAD_URL" != "null" ]; then
                    log_debug "Upload successful"
                    echo "$DOWNLOAD_URL"
                    return 0
                fi
            fi
            
            # If state is 1 (Processing), wait and check status
            if [ "$STATE" = "1" ] || match '"state":"1"' "$JSON"; then
                log_debug "File is being processed, checking status..."
                
                # Wait for processing to complete (max 60 attempts, 5 seconds each = 5 minutes)
                local ATTEMPTS=0
                local MAX_ATTEMPTS=60
                
                while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
                    sleep 5
                    
                    JSON=$(curl -s --fail \
                        "$BASE_URL/api/v2/file/upload_info?token=$TOKEN&upload_id=$UPLOAD_ID") || return
                    
                    log_debug "Status check attempt $((ATTEMPTS+1)): $JSON"
                    
                    if match '"state":2' "$JSON"; then
                        # Extract file URL from the nested structure
                        local FILE_URL=$(echo "$JSON" | grep -o '"url":"[^"]*"' | tail -1 | sed 's/"url":"\([^"]*\)"/\1/' | sed 's/\\//g')
                        
                        if [ -n "$FILE_URL" ] && [ "$FILE_URL" != "null" ]; then
                            log_debug "Upload completed successfully"
                            echo "$FILE_URL"
                            return 0
                        else
                            log_error "Failed to extract URL from upload response"
                            return $ERR_FATAL
                        fi
                    fi
                    
                    # Check for failure state
                    if match '"state":3' "$JSON"; then
                        log_error "Upload failed on server side"
                        return $ERR_FATAL
                    fi
                    
                    ATTEMPTS=$((ATTEMPTS+1))
                done
                
                log_error "Upload processing timeout"
                return $ERR_FATAL
            fi
        else
            log_error "Upload request failed"
            return $ERR_FATAL
        fi
    fi

    log_error "Upload failed"
    return $ERR_FATAL
}

# Probe a download URL
# $1: cookie file (unused here)
# $2: Rapidgator url
# $3: requested capability list
# stdout: 1 capability per line
rapidgator_probe() {
    local -r COOKIE_FILE=$1
    local -r URL=$2
    local -r REQ_IN=$3
    local FILE_ID JSON FILE_NAME FILE_SIZE

    # Extract file ID from URL
    FILE_ID=$(parse . '/file/\([^/]*\)' <<< "$URL") || return

    # Use API to get file info (no auth required for basic info)
    JSON=$(curl -s --fail \
        "https://rapidgator.net/api/v2/file/info?file_id=$FILE_ID") || return

    if ! match '"status":200' "$JSON"; then
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
