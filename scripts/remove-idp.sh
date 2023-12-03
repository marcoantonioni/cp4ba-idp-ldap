#!/bin/bash

#-------------------------------
# read installation parameters
PROPS_FILE=""
FORCE_INST=false

while getopts p: flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
    esac
done

#-------------------------------
# get common values
getCommonValues () {

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

if [[ -f ${PROPS_FILE} ]];
then
    source ${PROPS_FILE}
else
    echo "ERROR: Properties file "${PROPS_FILE}" not found !!!"
    exit
fi

echo "======================================================================"
echo "Deleting IDP ["${IDP_NAME}"] for namespace ["${TNS}"]"
echo "======================================================================"
echo ""

getCommonValues
getIDPInfos
deleteIDP
getIDPInfos
showIDPList

