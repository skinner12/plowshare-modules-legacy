#!/bin/bash
#
# NETU.com. module
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

MODULE_NETU_REGEXP_URL='https://\(www\.\)\?\(netu\.\(tv\|io\|ac)\)/'

MODULE_NETU_UPLOAD_OPTIONS="
ADMIN_CODE,,admin-code,s=ADMIN_CODE,Admin code (used for file deletion)
AUTH,a,auth,a=USER:PASSWORD,User account (mandatory)
COOKIES,c,cookies file
FOLDER,,folder,s=FOLDER,Folder to upload files into
LINK_PASSWORD,p,link-password,S=PASSWORD,Protect a link with a password
PRIVATE_FILE,,private,,Do not allow others to download the file"
MODULE_NETU_UPLOAD_REMOTE_SUPPORT=no

netu_upload(){
    local -r FILE=$2
    local -r DEST_FILE=$3
    local -r API_URL='https://netu.tv/api'
    local SZ TOKEN JSON JSON2 EMAIL

    if [ -z "$AUTH" ]; then
        return "$ERR_LINK_NEED_PERMISSIONS"
    else
        log_debug "KEY Present: '$AUTH'"
    fi

    # Get server upload
    GETSERVER=$(curl "${API_URL}/file/upload_server?key=$AUTH") || return
    log_debug "reponse get server: '$GETSERVER'"

    SERVERUPLOAD=$(parse_json 'upload_server' <<<"$GETSERVER")
    SERVER_ID=$(parse_json 'server_id' <<<"$GETSERVER")
    STATUS=$(parse_json 'status' <<<"$GETSERVER")
    HASH=$(parse_json 'hash' <<<"$GETSERVER")
    KEY_HASH=$(parse_json 'key_hash' <<<"$GETSERVER")
    TIME_HASH=$(parse_json 'time_hash' <<<"$GETSERVER")
    USER_ID=$(parse_json 'userid' <<<"$GETSERVER")

    log_debug "SERVER: '$SERVERUPLOAD'"
    log_debug "SERVER ID: '$SERVER_ID'"
    log_debug "Status: '$STATUS'"
    log_debug "Hash: '$HASH'"
    log_debug "Key Hash: '$KEY_HASH'"
    log_debug "Time Hash: '$TIME_HASH'"
    log_debug "User ID: '$USER_ID'"
    if [[ $STATUS != "200" ]]; then
        log_error "File NOT Uploaded"
        return $ERR_FATAL
    fi




    # curl -X POST https://ssuploader.NETU.com/upload/01
    #  -d "api_key=948324jkl3h45h"
    #  -d "@path/filename.mp4"
    #  -H "Content-Type: application/x-www-form-urlencoded"

    # https://cX.netu.tv/flv/api/actions/file_uploader.php?hash={hash}&time_hash={time_hash}&userid={userid}&key_hash={key_hash}&userid={userid}&Filedata=@yourfile&upload=1

    # Start upload
    UPLOADEDFILE=$(
        curl_with_log \
            -F "hash=$HASH" \
            -F "time_hash=$TIME_HASH" \
            -F "userid=$USER_ID" \
            -F "key_hash=$KEY_HASH" \
            -F "Filedata=@$FILE" \
            "$SERVERUPLOAD"
    ) || return

    log_debug "Response: '$UPLOADEDFILE'"

    SUCCESS=$(parse_json 'success' <<<"$UPLOADEDFILE")
    FILENAME=$(parse_json 'file_name' <<<"$UPLOADEDFILE")

    log_debug "FILENAME: '$FILENAME'"
    log_debug "Success: '$SUCCESS'"

    if [[ $SUCCESS != "yes" ]]; then
        log_error "File NOT Uploaded"
        return "$ERR_FATAL"
    fi

    # Send filename to general server
    # https://netu.tv/api/file/add?key=813cd91f3e28d2b4f7a772dcc11b36a0&name={name}&server={server}&file_name={file_name}&folder_id={folder_id}&adult={adult}&server_id={server_id}

    GENERALSERVER=$(
        curl_with_log \
            -F "name=$DEST_FILE" \
            -F "server=$SERVERUPLOAD" \
            -F "file_name=$FILENAME" \
            -F "server_id=$SERVER_ID" \
            -F "adult=yes" \
            -F "key=$AUTH" \
            "${API_URL}/file/add"
    ) || return

    log_debug "Response: '$GENERALSERVER'"

    STATUS=$(parse_json 'status' <<<"$GENERALSERVER")
    FILECODE=$(parse_json 'file_code' <<<"$GENERALSERVER")
    FILE_CODE_EMBED=$(parse_json 'file_code_embed' <<<"$GENERALSERVER")
    FOLDER_ID=$(parse_json 'folder_id' <<<"$GENERALSERVER")

    log_debug "FILENAME: '$FILENAME'"
    log_debug "Success: '$SUCCESS'"
    log_debug "File Code: '$FILECODE'"
    log_debug "Folder ID: '$FOLDER_ID'"
    log_debug "File Code Embed: '$FILE_CODE_EMBED'"


    if [[ $SUCCESS != "yes" ]]; then
        log_error "File NOT Uploaded"
        return "$ERR_FATAL"
    else
        echo "https://video.q34r.org/e/$FILE_CODE_EMBED"
    fi

}
