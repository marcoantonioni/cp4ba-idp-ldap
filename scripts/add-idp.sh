#!/bin/bash

#set -euo pipefail

_me=$(basename "$0")

#-------------------------------
# read installation parameters
PROPS_FILE=""
FORCE_INST=false
_CFG=""

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
  echo "Error, log package not found !"
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

while getopts p:c:f flag
do
    case "${flag}" in
        f) FORCE_INST=true;;
        p) PROPS_FILE=${OPTARG};;
        c) _CFG=${OPTARG};;
    esac
done

usage () {
  echo ""
  echo "usage: $_me
    -c full-path-to-environment-config-file
    -p full-path-to-ldap-config-file
    -f (optional)force-installation"
}

#-------------------------------
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
  if [ $(oc get routes -n ${TNS} $_ROUTE_NAME --no-headers 2> /dev/null | wc -l) -lt 1 ]; then
    _ROUTE_NAME="platform-id-provider"
    log_info "${_CLR_GREEN}Using console route name [${_CLR_YELLOW}${_ROUTE_NAME}${_CLR_GREEN}]${_CLR_NC}"
  fi

  waitForResourceCreated ${TNS} "secret" "platform-auth-idp-credentials" 10

  # get pak admin username / password
  ADMIN_USERNAME=$(oc get secret platform-auth-idp-credentials -n ${TNS} -o jsonpath='{.data.admin_username}' | base64 -d)
  ADMIN_PASSW=$(oc get secret platform-auth-idp-credentials -n ${TNS} -o jsonpath='{.data.admin_password}' | base64 -d)

  # get admin URL
  CONSOLE_HOST=https://$(oc get route -n ${TNS} ${_ROUTE_NAME} -o jsonpath="{.spec.host}")

  # get IAM access token
  IAM_ACCESS_TK=$(curl -sk -X POST -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
      -d "grant_type=password&username=${ADMIN_USERNAME}&password=${ADMIN_PASSW}&scope=openid" \
      ${CONSOLE_HOST}/idprovider/v1/auth/identitytoken | jq -r .access_token)

  log_info "${_CLR_GREEN}Pak console: ${_CLR_YELLOW}${CONSOLE_HOST}${_CLR_NC}"
  log_info "${_CLR_GREEN}Pak administrator: ${_CLR_YELLOW}${ADMIN_USERNAME} / ${ADMIN_PASSW}${_CLR_NC}"
  log_msg ""
}

#-------------------------------
# create file for idp configuration
createIDPConfiguration () {

if [[ -z ${IDP_NAME} ]]; then
  IDP_NAME="vuxprod"
fi

# IDP v4.x
echo '{
  "name": "'${IDP_NAME}'",
  "description": "",
  "protocol": "ldap",
  "type": "Custom",
  "idp_config": {
        "ldap_id": "'${IDP_NAME}'",
        "ldap_realm": "REALM",
        "ldap_url": "'${LDAP_URL}'",
        "ldap_host": "'${LDAP_HOST}'",
        "ldap_port": "'${LDAP_PORT}'",
        "ldap_protocol": "'${LDAP_PROTOCOL}'",
        "ldap_basedn": "'${LDAP_BASEDN}'",
        "ldap_binddn": "'${LDAP_BINDDN}'",
        "ldap_bindpassword": "'${LDAP_BINDPASSWORD}'",
        "ldap_type": "Custom",
        "ldap_ignorecase": "true",
        "ldap_userfilter": "'${LDAP_USERFILTER}'",
        "ldap_useridmap": "'${LDAP_USERIDMAP}'",
        "ldap_groupfilter": "'${LDAP_GROUPFILTER}'",
        "ldap_groupidmap": "'${LDAP_GROUPIDMAP}'",
        "ldap_groupmemberidmap": "'${LDAP_GROUPMEMBERIDMAP}'",
        "ldap_nestedsearch": "'${LDAP_NESTEDSEARCH}'",
        "ldap_pagingsearch": "'${LDAP_PAGINGSEARCH}'"
        }
}' > ./${IDP_NAME}.json

}

#-------------------------------
# Add SCIM attributes

configSCIM () {

  SCIM_DATA='{"idp_id":"'${IDP_NAME}'","idp_type":"ldap","user":{"id":"dn","userName":"uid","principalName":"uid","displayName":"cn","givenName":"cn","familyName":"sn","fullName":"cn","externalId":"dn","phoneNumbers":[{"value":"mobile","type":"mobile"},{"value":"telephoneNumber","type":"work"}],"objectClass":"person","groups":"memberOf"},"group":{"id":"dn","name":"cn","principalName":"cn","displayName":"cn","externalId":"dn","created":"createTimestamp","lastModified":"modifyTimestamp","objectClass":"groupOfNames","members":"member"}}'

  RESPONSE=$(curl -sk -X POST -H "Authorization: Bearer ${IAM_ACCESS_TK}" -H 'Content-Type: application/json' \
              -d $SCIM_DATA "${CONSOLE_HOST}/idmgmt/identity/api/v1/scim/attributemappings" | jq .)

  if [[ "${RESPONSE}" == *"error"* ]]; then
    log_error "ERROR configuring SCIM attributes for [${IDP_NAME}]"
    log_msg "${RESPONSE}"
    exit 1
  else
    log_info "${_CLR_GREEN}SCIM attributes for IDP [${_CLR_YELLOW}${IDP_NAME}${_CLR_GREEN}] configured"
  fi

}

#-------------------------------
# create new IDP
createIdp () {

  createIDPConfiguration

  # set new IDP configuration
  RESPONSE=$(curl -sk -X POST "${CONSOLE_HOST}/idprovider/v3/auth/idsource" \
              -H "Authorization: Bearer ${IAM_ACCESS_TK}" -H 'Content-Type: application/json' -d @./${IDP_NAME}.json | jq .)

  if [[ "${RESPONSE}" == *"error"* ]]; then
    if [[ "${RESPONSE}" == *"Already exists"* ]]; then
      log_error "ERROR configuring [${IDP_NAME}], already configured, use -f to force a new installation"
    else
      log_error "ERROR configuring [${IDP_NAME}]"
      log_msg "${RESPONSE}"

      cat ./${IDP_NAME}.json

    fi
    exit 1
  else
    configSCIM
    log_info "${_CLR_GREEN}IDP [${_CLR_YELLOW}${IDP_NAME}${_CLR_GREEN}] configured.${_CLR_NC}"    
  fi

  rm ./${IDP_NAME}.json 
}

getUID () {
  echo ${IDP_LIST} | jq -c .idp[] | while read i; do
    _NAME=$(echo $i | jq .name | sed 's/"//g')
    if [ "${_NAME}" = "${IDP_NAME}" ]; then
      _UID=$(echo $i | jq .uid | sed 's/"//g')
      echo "${_UID}"
      return
    fi
  done
}

#-------------------------------
deleteIDP () {
  IDP_UID=$(getUID)

  if [[ -z "${IDP_UID}" ]]; then
    log_warning "IDP '${IDP_NAME}' not found in namespace ${TNS}"
  else
    RESPONSE=$(curl -sk -X DELETE "${CONSOLE_HOST}/idprovider/v3/auth/idsource/"${IDP_UID} -H "Authorization: Bearer ${IAM_ACCESS_TK}")
    if [[ "${RESPONSE}" == *"success"* ]]; then
      log_info "Deleted IDP "${IDP_NAME}" / "${IDP_UID}
    else
      log_error "ERROR deleting ${IDP_NAME}"
      echo ${RESPONSE} | jq .
      exit 1
    fi
  fi
}

#-------------------------------
# get list of configured IDP
getIDPInfos () {
  IDP_LIST=$(curl -sk -X GET "${CONSOLE_HOST}/idprovider/v3/auth/idsource" -H "Authorization: Bearer ${IAM_ACCESS_TK}")
  IDP_NAMES=$(echo ${IDP_LIST} | jq .idp[].name | sed 's/"//g')
}

#-------------------------------
# get list of configured IDP
showIDPList () {
  echo ""
  echo -n "IDP list: "
  echo ${IDP_NAMES}
}

#-------------------------------
# check if IDP already configured
verifyIDPAlreadyPresent () {
  if [[ "${IDP_NAMES}" == *"${IDP_NAME}"* ]]; then
    if [ "${FORCE_INST}" = false ]; then    
      log_error "ERROR configuring [${IDP_NAME}], already configured, use -f to force a new installation"
      exit 1
    else
      deleteIDP
    fi
  fi
}

#-------------------------------
checkParams() {

if [[ ! -z "${_CFG}" ]]; then
  if [[ -f "${_CFG}" ]]; then
    source ${_CFG}
  else
    log_error "ERROR: Configuration file "${_CFG}" not found !!!"
    usage
    exit 1
  fi
else
  log_error "ERROR: Configuration file -c not set !!!"
  usage
  exit 1
fi

if [[ -z "${PROPS_FILE}" ]]; then
  log_error "ERROR: 'PROPS_FILE' not set."
  usage
  exit 1
fi
if [[ -f "${PROPS_FILE}" ]]; then
    source ${PROPS_FILE}
else
    log_error "ERROR: Properties file "${PROPS_FILE}" not found !!!"
    usage
    exit 1
fi

if [ -z "${TNS}" ]; then
    log_error "ERROR: namespace not set"
    usage
    exit 1
fi

}
#-------------------------------

checkParams

log_msg "======================================================================"
log_msg "Configuring IDP"
log_msg "======================================================================"
log_msg ""

log_info "${_CLR_GREEN}IDP name [${_CLR_YELLOW}${IDP_NAME}${_CLR_GREEN}] namespace [${_CLR_YELLOW}${TNS}${_CLR_GREEN}]${_CLR_NC}"

getCommonValues
getIDPInfos
verifyIDPAlreadyPresent
createIdp
getIDPInfos
showIDPList
log_warning "===>> !!! Remember to restart the BAW server to also see the 'Groups' carried by the new IDP."

