#!/bin/bash
#
# streamsb.com. module
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

MODULE_DOODSTREAM_REGEXP_URL='https://\(www\.\)\?\(doodstream\.\(com\|net|sx\)\)/'

MODULE_DOODSTREAM_UPLOAD_OPTIONS="
ADMIN_CODE,,admin-code,s=ADMIN_CODE,Admin code (used for file deletion)
AUTH,a,auth,a=USER:PASSWORD,User account (mandatory)
COOKIES,c,cookies file
FOLDER,,folder,s=FOLDER,Folder to upload files into
LINK_PASSWORD,p,link-password,S=PASSWORD,Protect a link with a password
PRIVATE_FILE,,private,,Do not allow others to download the file"
MODULE_DOODSTREAM_UPLOAD_REMOTE_SUPPORT=no

doodstream_upload() {
  local -r FILE=$2
  local -r API_URL='https://doodapi.com/api'
  local SZ TOKEN JSON JSON2 EMAIL

  if [ -z "$AUTH" ]; then
    return "$ERR_LINK_NEED_PERMISSIONS"
  else
    log_debug "KEY Present: '$AUTH'"
  fi

  # Get server upload
  GETSERVER=$(curl "${API_URL}/upload/server?key=$AUTH") || return
  log_debug "reponse get server: '$GETSERVER'"

  SERVERUPLOAD=$(parse_json 'result' <<<"$GETSERVER")
  STATUS=$(parse_json 'status' <<<"$GETSERVER")

  log_debug "SERVER: '$SERVERUPLOAD'"
  log_debug "Status: '$STATUS'"
  if [[ $STATUS != "200" ]]; then
    log_error "File NOT Uploaded"
    return "$ERR_FATAL"
  fi

  # curl -X POST https://moon-upload-server-01.filemoon.to/upload/01
  #  -d "api_key=948324jkl3h45h"
  #  -d "@path/filename.mp4"
  #  -H "Content-Type: application/x-www-form-urlencoded"

  # Start upload
  UPLOADEDFILE=$(
    curl_with_log \
      -F "file=@$FILE" \
      -F "api_key=$AUTH" \
      --form 'json="1"' \
      "$SERVERUPLOAD"
  ) || return

  EMBED=$(parse_json 'protected_embed' <<<"$UPLOADEDFILE")
  STATUS=$(parse_json 'status' <<<"$UPLOADEDFILE")

  log_debug "CODE: '$CODE'"
  log_debug "EMBED: '$EMBED'"
  log_debug "Status: '$STATUS'"
  if [[ $STATUS != "200" ]]; then
    log_error "File NOT Uploaded"
    return "$ERR_FATAL"
  else
    echo "$EMBED"
  fi

}
