#!/usr/bin/env bash
#
# mixdrop.co module
# Copyright (c) 2025 [Your Name]
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
# https://www.gnu.org/licenses/gpl-3.0.html
#

MODULE_MIXDROP_REGEXP_URL='https://ul\.mixdrop\.ag/.*'
MODULE_MIXDROP_DESCRIPTION="Upload files to MixDrop via Official API"
MODULE_MIXDROP_VERSION="0.4"
MODULE_MIXDROP_UPLOAD_OPTIONS="
AUTH,a,auth,s=AUTH,Credentials in the format email:apiKey (mandatory)
FOLDER,f,folder,s=FOLDER,Download folder ID (optional)"
MODULE_MIXDROP_UPLOAD_REMOTE_SUPPORT=no

# Check required utilities and Bash version
mixdrop_require() {
    plow_version_compare "$BASH_VERSION" ">= 4.0" || plow_error "MixDrop module requires Bash >= 4.0"
    command -v curl >/dev/null 2>&1 || plow_error "curl is required"
    command -v jq   >/dev/null 2>&1 || plow_error "jq is required"
}

# Upload function called by Plowshare
mixdrop_upload() {
    local file_path="$2"
    local api_url='https://ul.mixdrop.ag/api'
    local response url email key

    # Verify AUTH format
    if [[ -z "$AUTH" || "$AUTH" != *:* ]]; then
        log_error "You must pass -a in the format email:apiKey"
        return "$ERR_LINK_NEED_PERMISSIONS"
    fi

    # Split AUTH into email and key
    IFS=':' read -r email key <<< "$AUTH"

    # Perform multipart POST request
    response=$(
      curl_with_log -sSfL -X POST "$api_url" \
        -F "email=${email}" \
        -F "key=${key}" \
        -F "file=@${file_path}" \
        ${FOLDER:+-F "folder=${FOLDER}"}
    ) || return

    # Check success flag
    if ! jq -e '.success == true' <<<"$response" >/dev/null; then
        log_error "MixDrop API error: $response"
        return "$ERR_FATAL"
    fi

    # Extract direct URL
    url=$(jq -r '.result.embedurl' <<<"$response")
    if [[ -z "$url" || "$url" == "null" ]]; then
        log_error "No URL found in response: $response"
        return "$ERR_FATAL"
    fi

    echo "$url"
}
