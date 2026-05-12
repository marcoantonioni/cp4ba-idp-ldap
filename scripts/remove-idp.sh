#!/bin/bash

#set -euo pipefail

_me=$(basename "$0")

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

#-------------------------------
# read installation parameters
PROPS_FILE=""
FORCE_INST=false
_PTNS=""
while getopts p:n: flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
        n) _PTNS=${OPTARG};;
    esac
done

#-------------------------------
# get common values
getCommonValues () {
  _ROUTE_NAME="cp-console"
  if [ $(oc get routes -n ${TNS} $_ROUTE_NAME --no-headers 2> /dev/null | wc -l) -lt 1 ]; then
    _ROUTE_NAME="platform-id-provider"
    log_info "${_CLR_GREEN}Using console route name [${_CLR_YELLOW}${_ROUTE_NAME}${_CLR_GREEN}]${_CLR_NC}"
  fi

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
}

getUID () {
  echo ${IDP_LIST} | jq -c .idp[] | while read i; do
    _NAME=$(echo $i | jq .name | sed 's/"//g')
    if [ "${_NAME}" = "${IDP_NAME}" ]; then
      _UID=$(echo $i | jq .uid | sed 's/"//g')
      log_info "${_UID}"
      return
    fi
  done
}

#-------------------------------
deleteIDP () {
  IDP_UID=$(getUID)

  if [[ -z "${IDP_UID}" ]]; then
    log_warning "IDP '${IDP_NAME}' not found in namespace '${TNS}'"
  else
    RESPONSE=$(curl -sk -X DELETE "${CONSOLE_HOST}/idprovider/v3/auth/idsource/"${IDP_UID} -H "Authorization: Bearer ${IAM_ACCESS_TK}")
    if [[ "${RESPONSE}" == *"success"* ]]; then
      log_info "${_CLR_GREEN}Deleted IDP '${_CLR_YELLOW}${IDP_NAME}${_CLR_GREEN}' / '${_CLR_YELLOW}${IDP_UID}${_CLR_GREEN}'${_CLR_NC}"
    else
      log_error "ERROR deleting '${IDP_NAME}'"
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
  log_msg "IDP list: "
  log_msg ${IDP_NAMES}
}

#-------------------------------

if [[ -f ${PROPS_FILE} ]]; then
    source ${PROPS_FILE}
else
    log_error "ERROR Properties file '${PROPS_FILE}' not found."
    exit 1
fi
if [[ -z "${TNS}" ]]; then
  TNS="${_PTNS}"
  if [[ -z "${TNS}" ]]; then
    log_error "ERROR Namespace not set, use -n !!!"
    exit 1
  fi
fi

log_msg "======================================================================"
log_msg "${_CLR_GREEN}Deleting IDP '${_CLR_YELLOW}${IDP_NAME}${_CLR_GREEN}' for namespace '${_CLR_YELLOW}${TNS}${_CLR_GREEN}'${_CLR_NC}"
log_msg "======================================================================"

getCommonValues
getIDPInfos
deleteIDP
getIDPInfos
showIDPList

