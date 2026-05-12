#!/bin/bash

#set -euo pipefail

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
_PTNS=""
while getopts p:n: flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
        n) _PTNS=${OPTARG};;        
    esac
done

#-------------------------------
resourceExist () {
  # $1 type
  # $2 name
  # $3 namespace
    if [ $(oc get -n $3 $1 $2 2>/dev/null 1>/dev/null | grep $2 | wc -l) -lt 1 ];
    then
        return 0
    fi
    return 1
}

#-------------------------------
deleteSecretsTls () {
  log_msg "Deleting secrets"
  resourceExist secret phpadminldap-${LDAP_DOMAIN}-root-ca ${TNS}
  if [ $? -eq 1 ]; then
    oc delete secret -n ${TNS} phpadminldap-${LDAP_DOMAIN}-root-ca 2>/dev/null 1>/dev/null
  fi

  resourceExist secret phpadminldap-${LDAP_DOMAIN}-prereq-ext ${TNS}
  if [ $? -eq 1 ]; then
    oc delete secret -n ${TNS} phpadminldap-${LDAP_DOMAIN}-prereq-ext 2>/dev/null 1>/dev/null
  fi
}

deletePHPAdmin () {
  log_msg "Deleting phpadmin resources"
  resourceExist cm php-admin-${LDAP_DOMAIN}-cm ${TNS}
  if [ $? -eq 1 ]; then
    oc delete cm -n ${TNS} php-admin-${LDAP_DOMAIN}-cm 2>/dev/null 1>/dev/null
  fi
  resourceExist deployment phpldapadmin-${LDAP_DOMAIN} ${TNS}
  if [ $? -eq 1 ]; then
    oc delete deployment -n ${TNS} phpldapadmin-${LDAP_DOMAIN} 2>/dev/null 1>/dev/null
  fi
  resourceExist service php-admin-${LDAP_DOMAIN} ${TNS}
  if [ $? -eq 1 ]; then
    oc delete service -n ${TNS} php-admin-${LDAP_DOMAIN} 2>/dev/null 1>/dev/null
  fi
  resourceExist route php-admin-${LDAP_DOMAIN} ${TNS}
  if [ $? -eq 1 ]; then
    oc delete route -n ${TNS} php-admin-${LDAP_DOMAIN} 2>/dev/null 1>/dev/null
  fi
}

#===============================

if [[ -f ${PROPS_FILE} ]];
then
    source ${PROPS_FILE}
else
    log_error "ERROR Properties file '${PROPS_FILE}' not found !!!"
    exit 1
fi

if [[ -z "${TNS}" ]]; then
  TNS="${_PTNS}"
  if [[ -z "${TNS}" ]]; then
    log_error "ERROR namespace not defined, use -n"
    exit 1
  fi
fi

log_msg "${_CLR_GREEN}Deleting phpadmin from namespace '${_CLR_YELLOW}${TNS}${_CLR_GREEN}'${_CLR_NC}"

deleteSecretsTls
deletePHPAdmin
