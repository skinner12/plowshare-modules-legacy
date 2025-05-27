#!/bin/bash
#
# mixdrop.sh - Mixdrop upload module for plowshare
# Copyright (c) 2025 Plowshare team
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

MODULE_MIXDROP_REGEXP_URL='https\?://\(www\.\)\?\(ul\.\)\?mixdrop\.\(co\|ag\|to\)/'

MODULE_MIXDROP_UPLOAD_OPTIONS="
AUTH,a,auth,a=EMAIL:APIKEY,API credentials (mandatory)
FOLDER,f,folder,s=FOLDER_ID,Download folder ID
"
MODULE_MIXDROP_UPLOAD_REMOTE_SUPPORT=no
MODULE_MIXDROP_PROBE_OPTIONS=""

# Upload a file to Mixdrop
# $1: cookie file (unused)
# $2: input file (with full path)
# $3: remote filename
# stdout: download link
mixdrop_upload() {
    local -r COOKIE_FILE=$1
    local -r FILE=$2
    local -r DESTFILE=$3
    local -r API_URL='https://ul.mixdrop.ag/api'
    local EMAIL APIKEY RESPONSE URL FILE_SIZE
    local ERROR_MSG SUCCESS
    
    # Module requires authentication
    if [ -z "$AUTH" ]; then
        log_error "Mixdrop: authentication required (-a EMAIL:APIKEY)"
        return $ERR_LINK_NEED_PERMISSIONS
    fi
    
    # Split authentication
    if ! split_auth "$AUTH" EMAIL APIKEY; then
        log_error "Invalid auth format. Use: -a EMAIL:APIKEY"
        return $ERR_LOGIN_FAILED
    fi
    
    # Get file size for logging
    FILE_SIZE=$(get_filesize "$FILE") || return
    log_debug "File size: $FILE_SIZE bytes"
    log_debug "Uploading to Mixdrop as: $DESTFILE"
    
    # Prepare multipart upload
    local -a CURL_ARGS
    CURL_ARGS=( \
        -F "email=$EMAIL" \
        -F "key=$APIKEY" \
        -F "file=@$FILE;filename=$DESTFILE" \
    )
    
    # Add folder if specified
    if [ -n "$FOLDER" ]; then
        CURL_ARGS+=( -F "folder=$FOLDER" )
        log_debug "Uploading to folder ID: $FOLDER"
    fi
    
    # Perform upload
    log_debug "Uploading file to Mixdrop API"
    
    # Show progress bar only in verbose mode
    if [ -n "$VERBOSE" ]; then
        RESPONSE=$(curl --fail \
            "${CURL_ARGS[@]}" \
            "$API_URL") || {
            log_error "Upload request failed"
            return $ERR_FATAL
        }
    else
        RESPONSE=$(curl -s --fail \
            "${CURL_ARGS[@]}" \
            "$API_URL") || {
            log_error "Upload request failed"
            return $ERR_FATAL
        }
    fi
    
    log_debug "API Response: $RESPONSE"
    
    # Check if we have jq for JSON parsing
    if command -v jq >/dev/null 2>&1; then
        # Use jq for reliable JSON parsing
        SUCCESS=$(echo "$RESPONSE" | jq -r '.success' 2>/dev/null)
        
        if [ "$SUCCESS" = "true" ]; then
            URL=$(echo "$RESPONSE" | jq -r '.result.embedurl // .result.url' 2>/dev/null)
            
            if [ -n "$URL" ] && [ "$URL" != "null" ]; then
                log_debug "Upload successful"
                echo "$URL"
                return 0
            fi
        else
            ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message // .error // empty' 2>/dev/null)
            log_error "Upload failed: ${ERROR_MSG:-Unknown error}"
            return $ERR_FATAL
        fi
    else
        # Fallback to grep/sed if jq not available
        if match '"success"\s*:\s*true' "$RESPONSE"; then
            # Try to extract embedurl first, then url
            URL=$(echo "$RESPONSE" | grep -o '"embedurl"\s*:\s*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
            
            if [ -z "$URL" ]; then
                URL=$(echo "$RESPONSE" | grep -o '"url"\s*:\s*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
            fi
            
            if [ -n "$URL" ]; then
                log_debug "Upload successful"
                echo "$URL"
                return 0
            fi
        else
            log_error "Upload failed. Response: $RESPONSE"
            return $ERR_FATAL
        fi
    fi
    
    log_error "Failed to extract URL from response"
    return $ERR_FATAL
}

# Probe a download URL
# $1: cookie file (unused)
# $2: Mixdrop url
# $3: requested capability list
# stdout: 1 capability per line
mixdrop_probe() {
    local -r COOKIE_FILE=$1
    local -r URL=$2
    local -r REQ_IN=$3
    local FILE_ID PAGE FILE_NAME FILE_SIZE
    
    # Extract file ID from URL
    FILE_ID=$(parse . '/[ef]/\([^/?]*\)' <<< "$URL") || return
    
    log_debug "Probing file ID: $FILE_ID"
    
    # Check if file exists by fetching the page
    PAGE=$(curl -s --fail "https://mixdrop.co/f/$FILE_ID") || return $ERR_LINK_DEAD
    
    REQ_OUT=c
    
    if [[ $REQ_IN = *f* ]]; then
        FILE_NAME=$(parse_tag 'class="title"' <<< "$PAGE" 2>/dev/null) || \
            FILE_NAME=$(parse '<title>' '<title>\([^<]*\)' <<< "$PAGE" 2>/dev/null)
        
        if [ -n "$FILE_NAME" ]; then
            echo "$FILE_NAME"
            REQ_OUT="${REQ_OUT}f"
        fi
    fi
    
    if [[ $REQ_IN = *s* ]]; then
        FILE_SIZE=$(parse 'filesize' 'filesize[[:space:]]*:[[:space:]]*\([0-9]*\)' <<< "$PAGE" 2>/dev/null)
        
        if [ -n "$FILE_SIZE" ]; then
            echo "$FILE_SIZE"
            REQ_OUT="${REQ_OUT}s"
        fi
    fi
    
    echo $REQ_OUT
}
