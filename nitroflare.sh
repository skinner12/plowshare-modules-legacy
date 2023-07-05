#!/bin/bash
#
# nitroflare.com. module
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

MODULE_NITROFLARE_REGEXP_URL='http://\(www\.\)\?\(nitroflare\.\(com\|net\)\)/'

MODULE_NITROFLARE_DOWNLOAD_OPTIONS="
AUTH,a,auth,a=USER:PASSWORD,User account
LINK_PASSWORD,p,link-password,S=PASSWORD,Used in password-protected files"
MODULE_NITROFLARE_DOWNLOAD_RESUME=no
MODULE_NITROFLARE_DOWNLOAD_FINAL_LINK_NEEDS_COOKIE=yes
MODULE_NITROFLARE_DOWNLOAD_SUCCESSIVE_INTERVAL=7200

MODULE_NITROFLARE_UPLOAD_OPTIONS="
ADMIN_CODE,,admin-code,s=ADMIN_CODE,Admin code (used for file deletion)
AUTH,a,auth,a=USER:PASSWORD,User account (mandatory)
COOKIES,c,cookies file
FOLDER,,folder,s=FOLDER,Folder to upload files into
LINK_PASSWORD,p,link-password,S=PASSWORD,Protect a link with a password
PRIVATE_FILE,,private,,Do not allow others to download the file"
MODULE_NITROFLARE_UPLOAD_REMOTE_SUPPORT=no

MODULE_NITROFLARE_DELETE_OPTIONS="
AUTH,a,auth,a=USER:PASSWORD,User account (mandatory)"

MODULE_NITROFLARE_LIST_OPTIONS=""
MODULE_NITROFLARE_LIST_HAS_SUBFOLDERS=no

MODULE_NITROFLARE_PROBE_OPTIONS=""

nitroflare_login() {
local -r AUTH=$1
local -r BASE_URL='https://nitroflare.com'
local LOGIN_DATA PAGE ERR TYPE ID NAME TOKEN_PRE TOKEN TRAFFIC_LIMIT

# Set cookie file as external
    FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    COOKIE_FILE="$FOLDER/cookies/cookie.txt"

#Get the token
TOKEN_PRE=$(curl -b "$COOKIE_FILE" "$BASE_URL/login") || return
TOKEN=$(echo "$TOKEN_PRE" | parse_form_input_by_name 'token') || return
#TOKEN=$(parse_form_input_by_name 'token' <<< "$TOKEN_PRE") || return

if [ ! "$TOKEN"  ]; then
    log_error 'No TOKEN Found.'
    return $ERR_FATAL

fi
log_notice "Token on LOGIN page: $TOKEN"
#exit 1

LOGIN_DATA="email=$USER&password=$PASSWORD&login=&token=$TOKEN"
PAGE=$(post_login "$AUTH" "$COOKIE_FILE" "$LOGIN_DATA" \
    "$BASE_URL/login") || return

# Note: Cookies "login" + "auth" get set on successful login
ERR=$(parse_json_quiet 'err' <<< "$PAGE")

if [ -n "$ERR" ]; then
    log_error "Remote error: $ERR"
    return $ERR_LOGIN_FAILED
fi

# Note: Login changes site's language according to account's preference
#nitroflare_switch_lang "$COOKIE_FILE" "$BASE_URL" || return

# Determine account type
#PAGE=$(curl -b "$COOKIE_FILE" "$BASE_URL/me") || return
#ID=$(parse 'ID:' '<em.*>\(.*\)</em>' 1 <<< "$PAGE") || return
#TYPE=$(parse 'Status:' '<em>\(.*\)</em>' 1 <<< "$PAGE") || return
#NAME=$(parse_quiet 'Alias:' '<b><b>\(.*\)</b></b>' 1 <<< "$PAGE") || return
#TRAFFIC_LIMIT=$(parse '500,00 GB' '<em>\(.*\)</em>' 1 <<< "$PAGE")

#if [ "$TYPE" = 'Free' ]; then
#    TYPE='free'
#elif [ "$TYPE" = 'Premium' ]; then
#    TYPE='premium'
#else
#    log_error 'Could not determine account type. Site updated?'
#    return $ERR_FATAL
#fi



PAGE=$(curl -b "$COOKIE_FILE" "$BASE_URL/member") || return
#PAGE=$(curl -b "$COOKIES" "$BASE_URL/member") || return
log_debug "Successfully logged in as member "

}

nitroflare_upload() {

    local -r FILE=$2
    local -r BASE_URL='https://nitroflare.com'
    local -r MAX_SIZE=2073741823
    local PAGE SERVER FILE_ID AUTH_DATA ACCOUNT FOLDER_ID
      
    if [ -z "$AUTH" ]; then
      return $ERR_LINK_NEED_PERMISSIONS
    else
      log_debug "KEY Present: '$AUTH'"
    fi


    # INFO=$(curl -b "$COOKIE_FILE" "http://nitroflare.com/plugins/fileupload/index.php") || return
    # #log_debug $INFO
    # #url:\s"([^"]+)

    # UPLOAD_SERVER=$(grep -oP 'url: "\K[^"]+' <<< "$INFO")
    # log_debug "Upload server: $UPLOAD_SERVER"

    # USERID=$(grep -oP "user: '\K[^']+" <<< "$INFO")
    # log_debug "User ID: $USERID"

    UPLOAD_SERVER=$(curl http://nitroflare.com/plugins/fileupload/getServer) || return

    log_debug "Upload server: $UPLOAD_SERVER"

    log_debug "File: $FILE"


    UPLOAD=$(curl_with_log  \
        -F "user=$AUTH" \
        -F "files=@$FILE" \
        "$UPLOAD_SERVER") || return


    log_debug "$UPLOAD"

    LINK=$(parse_json 'url' <<< "$UPLOAD" ) || return

    #Check if is uploaded
    if [ -z ${LINK+x} ];then
        log_error 'Uploaded failed?'
        return $ERR_FATAL
    fi

    #Return Upload Link
    echo "$LINK"
}
