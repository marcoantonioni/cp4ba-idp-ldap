#!/bin/bash

#-------------------------------
# read installation parameters
PROPS_FILE="./ldap.properties"

while getopts p: flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
    esac
done

#-------------------------------
resourceExist () {
  # $1 type
  # $2 name
  # $3 namespace
    if [ $(oc get -n $3 $1 $2 2> /dev/null | grep $2 | wc -l) -lt 1 ];
    then
        return 0
    fi
    return 1
}

#-------------------------------
deleteSecrets() {
  resourceExist secret TNS} ${LDAP_DOMAIN}-secret ${TNS}
  if [ $? -eq 1 ]; then
    oc delete secret -n ${TNS} ${LDAP_DOMAIN}-secret
  fi
  resourceExist secret ${LDAP_DOMAIN}-customldif ${TNS}
  if [ $? -eq 1 ]; then
    oc delete secret -n ${TNS} ${LDAP_DOMAIN}-customldif
  fi
}

#-------------------------------
deleteCfgMap() {
  resourceExist cm ${LDAP_DOMAIN}-env ${TNS}
  if [ $? -eq 1 ]; then
    oc delete cm -n ${TNS} ${LDAP_DOMAIN}-env
  fi
}

#-------------------------------
deleteDeployment() {
  resourceExist deployment ${LDAP_DOMAIN}-ldap ${TNS}
  if [ $? -eq 1 ]; then
    oc delete deployment -n ${TNS} ${LDAP_DOMAIN}-ldap
  fi
  resourceExist service ${LDAP_DOMAIN}-ldap ${TNS}
  if [ $? -eq 1 ]; then
    oc delete service -n ${TNS} ${LDAP_DOMAIN}-ldap
  fi
}

#===============================

if [[ -f ${PROPS_FILE} ]];
then
    source ${PROPS_FILE}
else
    echo "ERROR: Properties file "${PROPS_FILE}" not found !!!"
    exit
fi

echo "Deleting LDAP from namespace "${TNS}

deleteSecrets

deleteCfgMap

deleteDeployment
