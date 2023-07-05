#!/bin/bash
#
# download.com. module
# Copyright (c) 2011-2015 Plowshare team
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

MODULE_DDOWNLOAD_REGEXP_URL='http://\(www\.\)\?\(download\.\(com\|org\)\)/'

MODULE_DDOWNLOAD_DOWNLOAD_OPTIONS="
AUTH,a,auth,a=USER:PASSWORD,User account
LINK_PASSWORD,p,link-password,S=PASSWORD,Used in password-protected files"
MODULE_DDOWNLOAD_DOWNLOAD_RESUME=no
MODULE_DDOWNLOAD_DOWNLOAD_FINAL_LINK_NEEDS_COOKIE=yes
MODULE_DDOWNLOAD_DOWNLOAD_SUCCESSIVE_INTERVAL=7200

MODULE_DDOWNLOAD_UPLOAD_OPTIONS="
ADMIN_CODE,,admin-code,s=ADMIN_CODE,Admin code (used for file deletion)
AUTH,a,auth,a=USER:PASSWORD,User account (mandatory)
COOKIES,c,cookies file
FOLDER,,folder,s=FOLDER,Folder to upload files into
LINK_PASSWORD,p,link-password,S=PASSWORD,Protect a link with a password
PRIVATE_FILE,,private,,Do not allow others to download the file"
MODULE_DDOWNLOAD_UPLOAD_REMOTE_SUPPORT=no

MODULE_DDOWNLOAD_DELETE_OPTIONS="
AUTH,a,auth,a=USER:PASSWORD,User account (mandatory)"

MODULE_DDOWNLOAD_LIST_OPTIONS=""
MODULE_DDOWNLOAD_LIST_HAS_SUBFOLDERS=no

MODULE_DDOWNLOAD_PROBE_OPTIONS=""


ddownload_upload() {

    local -r FILE=$2
    local -r DEST_FILE=$3
    local -r API_URL='https://api-v2.ddownload.com/api'
    local -r MAX_SIZE=2073741823
    local PAGE SERVER FILE_ID AUTH_DATA ACCOUNT FOLDER_ID

    if [ -z "$AUTH" ]; then
      return $ERR_LINK_NEED_PERMISSIONS
    else
      log_debug "KEY Present: '$AUTH'"
    fi

    #Read page member to check if login is done well
    ACCESS=$(curl "$API_URL/account/info?key=$AUTH")
    MSG=$(parse_json 'msg' <<<"$ACCESS")

    if [[ $MSG != "OK" ]]; then
      log_error "File NOT Uploaded"
      return $ERR_FATAL
    fi

    log_debug "Successfully logged in as member "

    # Get server upload
    GETSERVER=$(curl "${API_URL}/upload/server?key=$AUTH") || return
    log_debug "reponse get server: '$GETSERVER'"

    MSG=$(parse_json 'msg' <<<"$ACCESS")

    if [[ $MSG != "OK" ]]; then
      log_error "File NOT Uploaded"
      return $ERR_FATAL
    fi

    SERVERUPLOAD=$(parse_json 'result' <<<"$GETSERVER")
    STATUS=$(parse_json 'status' <<<"$GETSERVER")
    SESSION=$(parse_json 'sess_id' <<<"$GETSERVER")

    log_debug "SERVER: '$SERVERUPLOAD'"
    log_debug "Status: '$STATUS'"
    if [[ $STATUS != "200" ]]; then
      log_error "File NOT Uploaded"
      return $ERR_FATAL
    fi
    log_debug "Session: '$SESSION'"

    # curl -X POST https://ssuploader.streamsb.com/upload/01
    #  -d "api_key=948324jkl3h45h"
    #  -d "@path/filename.mp4"
    #  -H "Content-Type: application/x-www-form-urlencoded"


    # Start upload
    UPLOADEDFILE=$(
    curl_with_log \
      -F "file=@$FILE" \
      -F "sess_id=$SESSION" \
      -F "utype=prem" \
      --form 'json="1"' \
      "$SERVERUPLOAD"
    ) || return

    CODE=$(parse_json 'file_code' <<<"$UPLOADEDFILE")
    STATUS=$(parse_json 'file_status' <<<"$UPLOADEDFILE")

    log_debug "CODE: '$CODE'"
    log_debug "Status: '$STATUS'"
    if [[ $STATUS != "OK" ]]; then
      log_error "File NOT Uploaded"
    return $ERR_FATAL
      else
    echo "https://ddownload.com/$CODE/$DEST_FILE"
    fi
}
