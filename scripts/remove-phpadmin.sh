#!/bin/bash

#-------------------------------
# read installation parameters
PROPS_FILE=""

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
deleteSecretsTls () {
  resourceExist secret phpadminldap-${LDAP_DOMAIN}-root-ca ${TNS}
  if [ $? -eq 1 ]; then
    oc delete secret -n ${TNS} phpadminldap-${LDAP_DOMAIN}-root-ca
  fi

  resourceExist secret phpadminldap-${LDAP_DOMAIN}-prereq-ext ${TNS}
  if [ $? -eq 1 ]; then
    oc delete secret -n ${TNS} phpadminldap-${LDAP_DOMAIN}-prereq-ext
  fi
}

deletePHPAdmin () {
  resourceExist cm php-admin-${LDAP_DOMAIN}-cm ${TNS}
  if [ $? -eq 1 ]; then
    oc delete cm -n ${TNS} php-admin-${LDAP_DOMAIN}-cm
  fi
  resourceExist deployment phpldapadmin-${LDAP_DOMAIN} ${TNS}
  if [ $? -eq 1 ]; then
    oc delete deployment -n ${TNS} phpldapadmin-${LDAP_DOMAIN}
  fi
  resourceExist service php-admin-${LDAP_DOMAIN} ${TNS}
  if [ $? -eq 1 ]; then
    oc delete service -n ${TNS} php-admin-${LDAP_DOMAIN}
  fi
  resourceExist route php-admin-${LDAP_DOMAIN} ${TNS}
  if [ $? -eq 1 ]; then
    oc delete route -n ${TNS} php-admin-${LDAP_DOMAIN}
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

echo "Deleting phpadmin from namespace "${TNS}

deleteSecretsTls
deletePHPAdmin
