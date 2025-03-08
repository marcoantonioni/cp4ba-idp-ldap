#!/bin/bash

#-------------------------------
# read installation parameters
PROPS_FILE=""
FORCE_INST=false

while getopts p:f flag
do
    case "${flag}" in
        f) FORCE_INST=true;;
        p) PROPS_FILE=${OPTARG};;
    esac
done

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

  echo -n "Wait for resource '$3' in namespace '$1' created"
  while [ true ]
  do
      resourceExist $1 $2 $3
      if [ $? -eq 0 ]; then
          echo -n "."
          sleep $4
      else
          echo ""
          break
      fi
  done
}

#-------------------------------
# get common values
getCommonValues () {

  waitForResourceCreated ${TNS} "secret" "platform-auth-idp-credentials" 10

  # get pak admin username / password
  ADMIN_USERNAME=$(oc get secret platform-auth-idp-credentials -n ${TNS} -o jsonpath='{.data.admin_username}' | base64 -d)
  ADMIN_PASSW=$(oc get secret platform-auth-idp-credentials -n ${TNS} -o jsonpath='{.data.admin_password}' | base64 -d)

  # get admin URL
  CONSOLE_HOST=https://$(oc get route -n ${TNS} cp-console -o jsonpath="{.spec.host}")

  # get IAM access token
  IAM_ACCESS_TK=$(curl -sk -X POST -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
      -d "grant_type=password&username=${ADMIN_USERNAME}&password=${ADMIN_PASSW}&scope=openid" \
      ${CONSOLE_HOST}/idprovider/v1/auth/identitytoken | jq -r .access_token)

  echo "Pak console: "${CONSOLE_HOST}
  echo "Pak administrator: ${ADMIN_USERNAME} / ${ADMIN_PASSW}"
  echo ""
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
    echo "ERROR configuring SCIM attributes for [${IDP_NAME}]"
    echo "${RESPONSE}"
    exit
  else
    echo "SCIM attributes for IDP [${IDP_NAME}] configured"
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
      echo -e "ERROR configuring [${IDP_NAME}], already configured, use -f to force a new installation"
    else
      echo -e "ERROR configuring [${IDP_NAME}]\n${RESPONSE}"

      cat ./${IDP_NAME}.json

    fi
    exit
  else
    configSCIM
    echo "IDP [${IDP_NAME}] configured"    
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
    echo "IDP "${IDP_NAME}" not found in namespace "${TNS}
  else
    RESPONSE=$(curl -sk -X DELETE "${CONSOLE_HOST}/idprovider/v3/auth/idsource/"${IDP_UID} -H "Authorization: Bearer ${IAM_ACCESS_TK}")
    if [[ "${RESPONSE}" == *"success"* ]]; then
      echo "Deleted IDP "${IDP_NAME}" / "${IDP_UID}
    else
      echo "ERROR deleting ${IDP_NAME}"
      echo ${RESPONSE} | jq .
      exit
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
      echo -e "ERROR configuring [${IDP_NAME}], already configured, use -f to force a new installation"
      exit
    else
      deleteIDP
    fi
  fi
}

#-------------------------------

if [[ -f ${PROPS_FILE} ]];
then
    source ${PROPS_FILE}
else
    echo "ERROR: Properties file "${PROPS_FILE}" not found !!!"
    exit
fi

echo "======================================================================"
echo "Configuring IDP ["${IDP_NAME}"] for namespace ["${TNS}"]"
echo "======================================================================"
echo ""

getCommonValues
getIDPInfos
verifyIDPAlreadyPresent
createIdp
getIDPInfos
showIDPList

