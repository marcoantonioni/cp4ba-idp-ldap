#!/bin/bash

#set -euo pipefail


#-------------------------------
# read installation parameters
PROPS_FILE=""
LDAP_FILE=""
USERS_FILE=""
USERS_SECRET=false
OPERATION_MODE=""
_TNS=""
_ENVTNS=""
_LIST_ROLES=false

#--------------------------------------------------------
_CLR_RED="\033[0;31m"   #'0;31' is Red's ANSI color code
_CLR_GREEN="\033[0;32m"   #'0;32' is Green's ANSI color code
_CLR_YELLOW="\033[1;33m"   #'1;32' is Yellow's ANSI color code
_CLR_BLUE="\033[0;34m"   #'0;34' is Blue's ANSI color code
_CLR_NC="\033[0m"

#----------------------------------------------------
_SCRIPT_PATH="${BASH_SOURCE}"
while [ -L "${_SCRIPT_PATH}" ]; do
  _SCRIPT_DIR="$(cd -P "$(dirname "${_SCRIPT_PATH}")" >/dev/null 2>&1 && pwd)"
  _SCRIPT_PATH="$(readlink "${_SCRIPT_PATH}")"
  [[ ${_SCRIPT_PATH} != /* ]] && _SCRIPT_PATH="${_SCRIPT_DIR}/${_SCRIPT_PATH}"
done
_SCRIPT_PATH="$(readlink -f "${_SCRIPT_PATH}")"
_SCRIPT_DIR="$(cd -P "$(dirname -- "${_SCRIPT_PATH}")" >/dev/null 2>&1 && pwd)"

#----------------------------------------------------
if [[ ! -f "$_SCRIPT_DIR/../../cp4ba-logger/scripts/logger.sh" ]]; then
  echo "ERROR log package not found !"
  echo "Clone it alongside with other cp4ba-..."
  echo "use the command: git clone https://github.com/marcoantonioni/cp4ba-logger"
  exit 1
fi
source $_SCRIPT_DIR/../../cp4ba-logger/scripts/logger.sh
if [[ -z "${CP4BA_LOGGING_ENABLED}" ]]; then 
  export CP4BA_LOGGING_ENABLED=true
fi
if [[ -z "${CP4BA_LOG_LEVEL}" ]]; then 
  export CP4BA_LOG_LEVEL="INFO"
fi
if [[ -z "${CP4BA_LOG_TO_CONSOLE}" ]]; then 
  export CP4BA_LOG_TO_CONSOLE=true
fi
if [[ -z "${CP4BA_LOG_TO_FILE}" ]]; then 
  export CP4BA_LOG_TO_FILE=false
fi
if [[ -z "${CP4BA_LOG_FILE}" ]]; then 
  export CP4BA_LOG_FILE=""
fi
if [[ -z "${CP4BA_LOG_MAX_SIZE}" ]]; then 
  export CP4BA_LOG_MAX_SIZE=$((10 * 1024 * 1024))
fi
if [[ -z "${CP4BA_LOG_BACKUP_COUNT}" ]]; then 
  export CP4BA_LOG_BACKUP_COUNT=5
fi

#--------------------------------------------------------
_INST_TMP_FOLDER="/tmp"
setTemporaryFolder () {
  _OK=0
  _ERR_MSG_FOLDER="is a folder"
  _ERR_MSG_PERMISSIONS=""
  if [[ ! -z "${CP4BA_INST_TMP_FOLDER}" ]]; then
    if [[ -d "${CP4BA_INST_TMP_FOLDER}" ]]; then
      if [[ -r "${CP4BA_INST_TMP_FOLDER}" ]] && [[ -w "${CP4BA_INST_TMP_FOLDER}" ]]; then 
        _OK=1
      else
        _ERR_MSG_PERMISSIONS=", you have not rights to read and/or write"
        _OK=-1
      fi
    else
      _ERR_MSG_FOLDER="is NOT a folder"
    fi

    if [[ $_OK -lt 1 ]]; then
      log_error "${_CLR_RED}[✗] ERROR '${_CLR_YELLOW}${CP4BA_INST_TMP_FOLDER}${_CLR_RED}' is not a valid temporary folder, check if it is a folder or if you have write permissions !${_CLR_NC}"
      log_error "${_CLR_RED}'${_CLR_YELLOW}${CP4BA_INST_TMP_FOLDER}${_CLR_RED}' ${_ERR_MSG_FOLDER}${_ERR_MSG_PERMISSIONS}${_CLR_NC}"
      exit 1
    fi
    export _INST_TMP_FOLDER="${CP4BA_INST_TMP_FOLDER}"
  fi
  log_info "${_CLR_GREEN}Running with temporary folder '${_CLR_YELLOW}${_INST_TMP_FOLDER}${_CLR_GREEN}'${_CLR_NC}"

}

while getopts p:l:n:u:o:e:sr flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
        l) LDAP_FILE=${OPTARG};;
        n) _TNS=${OPTARG};;
        e) _ENVTNS=${OPTARG};;
        u) USERS_FILE=${OPTARG};;
        o) OPERATION_MODE=${OPTARG};;
        s) USERS_SECRET=true;;
        r) _LIST_ROLES=true;;
    esac
done

resourceExist () {
#    echo "namespace name: $1"
#    echo "resource type: $2"
#    echo "resource name: $3"
  if [ $(oc get $2 -n $1 $3 2> /dev/null | grep $3 | wc -l) -lt 1 ];
  then
      return 0
  fi
  return 1
}

#-------------------------------
waitForResourceCreated () {
#    echo "namespace name: $1"
#    echo "resource type: $2"
#    echo "resource name: $3"
#    echo "time to wait: $4"

  log_info "${_CLR_GREEN}Wait for resource '${_CLR_YELLOW}$3${_CLR_GREEN}' in namespace '${_CLR_YELLOW}$1${_CLR_GREEN}' to be created${_CLR_NC}"
  while true 
  do
      resourceExist $1 $2 $3
      if [ $? -eq 0 ]; then
          sleep $4
      else
          break
      fi
  done
}

#-------------------------------
# get common values
getCommonValues () {
  _ROUTE_NAME="cp-console"
  if [ $(oc get routes -n ${_ENVTNS} $_ROUTE_NAME --no-headers 2> /dev/null | wc -l) -lt 1 ]; then
    _ROUTE_NAME="platform-id-provider"
    log_info "${_CLR_GREEN}Using console route name '${_CLR_YELLOW}${_ROUTE_NAME}${_CLR_GREEN}'${_CLR_NC}"
  fi

  waitForResourceCreated ${_ENVTNS} "secret" "platform-auth-idp-credentials" 10
  waitForResourceCreated ${_ENVTNS} "route" "cpd" 10

  # get pak admin username / password
  ADMIN_USERNAME=$(oc get secret platform-auth-idp-credentials -n ${_ENVTNS} -o jsonpath='{.data.admin_username}' | base64 -d)
  ADMIN_PASSW=$(oc get secret platform-auth-idp-credentials -n ${_ENVTNS} -o jsonpath='{.data.admin_password}' | base64 -d)

  # get admin URL
  CONSOLE_HOST="https://"$(oc get route -n ${_ENVTNS} ${_ROUTE_NAME} -o jsonpath="{.spec.host}")
  PAK_HOST="https://"$(oc get route -n ${_ENVTNS} cpd -o jsonpath="{.spec.host}")

  # get IAM access token
  IAM_ACCESS_TK=$(curl -sk -X POST -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
        -d "grant_type=password&username=${ADMIN_USERNAME}&password=${ADMIN_PASSW}&scope=openid" \
        ${CONSOLE_HOST}/idprovider/v1/auth/identitytoken | jq -r .access_token)

  ZEN_TK=$(curl -sk "${PAK_HOST}/v1/preauth/validateAuth" -H "username:${ADMIN_USERNAME}" -H "iam-token: ${IAM_ACCESS_TK}" | jq -r .accessToken)

  log_info "${_CLR_GREEN}Pak console: '${_CLR_YELLOW}${CONSOLE_HOST}${_CLR_GREEN}'${_CLR_NC}"
  log_info "${_CLR_GREEN}Pak cpd console: '${_CLR_YELLOW}${PAK_HOST}${_CLR_GREEN}'${_CLR_NC}"
  log_info "${_CLR_GREEN}Pak administrator: ${_CLR_YELLOW}${ADMIN_USERNAME}${_CLR_GREEN} / ${_CLR_YELLOW}${ADMIN_PASSW}${_CLR_NC}"
}

LIST_OF_USERS=""
LIST_OF_RECORDS=""

#-------------------------------
loadUsersFromSecret () {
  log_info "${_CLR_GREEN}Loading users from secret '${_CLR_YELLOW}${LDAP_DOMAIN}-customldif${_CLR_GREEN}'${_CLR_NC}"
  resourceExist ${TNS} "secret" ${LDAP_DOMAIN}-customldif
  if [ $? -eq 1 ]; then
    LIST_OF_USERS=$(oc get secrets -n ${TNS} ${LDAP_DOMAIN}-customldif -o jsonpath='{.data.ldap_user\.ldif}' | base64 -d | grep "uid:" | sed 's/uid: //g')
    # because sed -i & Darwin...
    _FNAME="${_INST_TMP_FOLDER}/pak-onboard-users-$USER-$RANDOM"
    _FNAME2="${_FNAME}-transformed"
    echo $LIST_OF_USERS > ${_FNAME}
    #sed 's/ /+/g' -i ${_FNAME}
    cat ${_FNAME} | sed 's/ /+/g' > ${_FNAME2}    
    LIST_OF_USERS=$(cat ${_FNAME2})
    rm ${_FNAME} 2>/dev/null
    rm ${_FNAME2} 2>/dev/null
  else
    log_error "ERROR secret '${LDAP_DOMAIN}-customldif' not found in namespace '${TNS}'"
    exit 1
  fi
}

#-------------------------------
loadUsersFromFile () {
  log_info "${_CLR_GREEN}Loading users from file '${_CLR_YELLOW}$1${_CLR_GREEN}'${_CLR_NC}"

  if [[ -f $1 ]]; then

    IFS=$'\n'
    LIST_OF_USERS=($(cat ${USERS_FILE} | sed 's/\r//g'))

    # _FNAME="${_INST_TMP_FOLDER}/pak-onboard-users-$USER-$RANDOM"
    # LIST_OF_USERS=$(cat $1)
    # # because sed -i & Darwin...
    # _FNAME="${_INST_TMP_FOLDER}/pak-onboard-users-$USER-$RANDOM"
    # _FNAME2="${_FNAME}-transformed"
    # echo $LIST_OF_USERS > ${_FNAME}
    # #sed 's/ /+/g' -i ${_FNAME}
    # cat ${_FNAME} | sed 's/ /+/g' > ${_FNAME2}    
    # LIST_OF_USERS=$(cat ${_FNAME2})
    # rm ${_FNAME} 2>/dev/null
    # rm ${_FNAME2} 2>/dev/null
  else
      log_error "ERROR Users file '$1' not found !!!"
      exit 1
  fi

}

#-------------------------------
# onboard users add

onboardUsersAdd () {

  ALL_USERS=()
  if [[ "${USERS_SECRET}" = "true" ]]; then
    IFS="+" read -ra ALL_USERS <<< "$LIST_OF_USERS"  
  else
    for user in "${LIST_OF_USERS[@]}"; do
      ALL_USERS+=("$user")
      #echo "adding: $user"
    done
  fi

  tot_users=${#ALL_USERS[@]}

  log_info "Adding $tot_users users..."

  UPDATED_LIST=""

  _ADMINS=()
  if [[ ! -z "${LDAP_ADMINS}" ]]; then
    IFS=',' read -a _ADMINS <<< "${LDAP_ADMINS}"
  fi
  
  _usersChunk=50
  counter=0
  for _USR in "${ALL_USERS[@]}";
  do
  
    isAdmin=0
    for admin in "${_ADMINS[@]}"; do
      admin=$(echo $admin | tr -d ' ')
      if [[ "$admin" = "$_USR" ]]; then
        isAdmin=1
      fi
    done
    if [ $isAdmin -eq 1 ]; then
      USER_RECORD='{"username":"'${_USR}'","displayName":"'${_USR}'","email":"'${_USR}'@'${LDAP_DOMAIN}'.'${LDAP_DOMAIN_EXT}'","authenticator":"external","user_roles":["iaf-automation-admin","zen_administrator_role","iaf-automation-analyst","iaf-automation-developer","iaf-automation-operator","zen_user_role"],"misc":{"realm_name":"'${LDAP_DOMAIN}'","extAttributes":{}}}'
      USER_RECORD="${USER_RECORD},"
      UPDATED_LIST=${UPDATED_LIST}${USER_RECORD}
    else
      USER_RECORD='{"username":"'${_USR}'","displayName":"'${_USR}'","email":"'${_USR}'@'${LDAP_DOMAIN}'.'${LDAP_DOMAIN_EXT}'","authenticator":"external","user_roles":["zen_user_role"],"misc":{"realm_name":"'${LDAP_DOMAIN}'","extAttributes":{}}}'
      USER_RECORD="${USER_RECORD},"
      UPDATED_LIST=${UPDATED_LIST}${USER_RECORD}
    fi
    counter=$((counter + 1))

    if [[ $counter -ge $_usersChunk ]]; then
      LIST_OF_RECORDS=$( echo ${UPDATED_LIST} | sed 's/.$//g')

      if [[ ! -z "${LIST_OF_RECORDS}" ]]; then
        log_info "${_CLR_GREEN}Adding chunk of '${_CLR_YELLOW}$counter${_CLR_GREEN}' users...${_CLR_NC}"

        _DATA='['${LIST_OF_RECORDS}']'

        #echo -e $_DATA | jq .

        RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -H 'Content-Type: application/json' \
                    -d $_DATA -X POST "${PAK_HOST}/usermgmt/v1/user/bulk")

        if [[ "${RESPONSE}" == *"error"* ]]; then
          log_error "ERROR adding users"
          echo "${RESPONSE}"
        else
          RES=$(echo $RESPONSE | jq ._messageCode_ | sed 's/"//g')
          if [[ "${RES}" != "Success" ]]; then
            _MSG=$(echo $RESPONSE | jq .message | sed 's/"//g')
            echo "ERROR CODE [${RES}] - ERROR MSG [${_MSG}]"
            echo "ERROR PAYLOAD: ${RESPONSE}"
          fi
        fi
      fi
      UPDATED_LIST=""
      counter=0

    fi
  done

  if [[ $counter -gt 0 ]]; then
    LIST_OF_RECORDS=$( echo ${UPDATED_LIST} | sed 's/.$//g')

    if [[ ! -z "${LIST_OF_RECORDS}" ]]; then
      log_info "${_CLR_GREEN}Adding last chunk of '${_CLR_YELLOW}$counter${_CLR_GREEN}' users...${_CLR_NC}"

      _DATA='['${LIST_OF_RECORDS}']'
      RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -H 'Content-Type: application/json' \
                  -d $_DATA -X POST "${PAK_HOST}/usermgmt/v1/user/bulk")

      if [[ "${RESPONSE}" == *"error"* ]]; then
        log_error "ERROR adding users"
        echo "${RESPONSE}"
        exit 1
      else
        RES=$(echo $RESPONSE | jq ._messageCode_ | sed 's/"//g')
        if [[ "${RES}" = "Success" ]]; then
          #_MSG="${_CLR_GREEN}'${_CLR_YELLOW}"$(echo $RESPONSE | jq '.result | length')"${_CLR_GREEN}' Users operated in mode '${_CLR_YELLOW}add${_CLR_GREEN}'${_CLR_NC}"          
          #log_info "$_MSG"
          
          log_info "${_CLR_GREEN}'${_CLR_YELLOW}${tot_users}${_CLR_GREEN}' Users operated in mode '${_CLR_YELLOW}add${_CLR_GREEN}'${_CLR_NC}"          
        else
          _MSG=$(echo $RESPONSE | jq .message | sed 's/"//g')
          echo "ERROR CODE [${RES}] - ERROR MSG [${_MSG}]"
          echo "ERROR PAYLOAD: ${RESPONSE}"
        fi
      fi
    fi
  fi
}


#-------------------------------
# onboard users remove

onboardUsersRemove () {

  ALL_USERS=()
  if [[ "${USERS_SECRET}" = "true" ]]; then
    IFS="+" read -ra ALL_USERS <<< "$LIST_OF_USERS"  
  else
    for user in "${LIST_OF_USERS[@]}"; do
      ALL_USERS+=("$user")
      #echo "removing: $user"
    done
  fi

  tot_users=${#ALL_USERS[@]}

  if [[ $tot_users -gt 0 ]]; then
    log_info "Removing $tot_users users..."

    for _USR in "${ALL_USERS[@]}";
    do
      if [[ "$_USR" != "cp4admin" && "$_USR" != "banadmin" && "$_USR" != "p8admin" ]]; then
        RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' \
                    -X DELETE "${PAK_HOST}/usermgmt/v1/user/${_USR}")
        if [[ "${RESPONSE}" == *"exception"* ]]; then
          _MSG="ERROR removing user '${_USR}' message: "$(echo "${RESPONSE}" | jq .exception)
          log_error "$_MSG"
        else
          log_info "Removed user $_USR"
        fi
      else
        log_info "Skip admin user $_USR"
      fi
    done
    log_info "$tot_users Users operated in mode 'remove'"
  else
    log_warning "No users to remove."
  fi

}

#-------------------------------

if [[ -f ${PROPS_FILE} ]];
then
    source ${PROPS_FILE}
else
    log_error "ERROR Configuration properties file '${PROPS_FILE}' not found !!!"
    exit 1
fi

#if [[ -f ${LDAP_FILE} ]];
#then
#    source ${LDAP_FILE}
#else
#    echo "ERROR LDAP properties file "${LDAP_FILE}" not found !!!"
#    exit 1
#fi

if [[ "${_TNS}" != "" ]]; then
  TNS="${_TNS}"
fi

if [[ -z "${_ENVTNS}" ]]; then
  log_error "${_CLR_RED}ERROR namespace for environment not set, use -e !${_CLR_GREEN}"
  exit 1
fi

log_msg "=============================================================="
log_info "${_CLR_GREEN}Onboard users from domain '${_CLR_YELLOW}${LDAP_DOMAIN}${_CLR_GREEN}' for namespace '${_CLR_YELLOW}${_ENVTNS}${_CLR_GREEN}'${_CLR_NC}"

setTemporaryFolder

if [[ "${_LIST_ROLES}" = "true" ]]; then
  getCommonValues
  log_msg ""
  log_info "Roles:"
  RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -H 'Content-Type: application/json' \
              "${PAK_HOST}/usermgmt/v1/roles")
  echo $RESPONSE | jq .

  log_msg ""
  log_info "Groups:"
  RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -H 'Content-Type: application/json' \
              "${PAK_HOST}/usermgmt/v2/groups")
  echo $RESPONSE | jq .

  exit 0
fi

if [[ "${OPERATION_MODE}" = "add" ]] || [[ "${OPERATION_MODE}" = "remove" ]] || [[ "${OPERATION_MODE}" = "remove-and-add" ]]; then
  getCommonValues
  if [[ "${USERS_SECRET}" = "true" ]]; then
    loadUsersFromSecret
  else
    loadUsersFromFile ${USERS_FILE}
  fi

  _OPERATION="POST"
  if [[ "${OPERATION_MODE}" = "add" ]]; then
    onboardUsersAdd
  fi 
  if [[ "${OPERATION_MODE}" = "remove" ]]; then
    onboardUsersRemove
  fi 
  if [[ "${OPERATION_MODE}" = "remove-and-add" ]]; then
    onboardUsersRemove
    onboardUsersAdd
  fi 
  exit 0
else
  log_error "${_CLR_RED}ERROR set operation mode using -o [add|remove|remove-and-add]${_CLR_NC}"
  exit 1
fi
