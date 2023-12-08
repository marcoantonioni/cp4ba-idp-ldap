#!/bin/bash

#-------------------------------
# read installation parameters
PROPS_FILE=""
USERS_FILE=""
USERS_SECRET=false

while getopts p:u:s flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
        u) USERS_FILE=${OPTARG};;
        s) USERS_SECRET=true;;
    esac
done

#-------------------------------
# get common values
getCommonValues () {

  # get pak admin username / password
  ADMIN_USERNAME=$(oc get secret platform-auth-idp-credentials -n ${TNS} -o jsonpath='{.data.admin_username}' | base64 -d)
  ADMIN_PASSW=$(oc get secret platform-auth-idp-credentials -n ${TNS} -o jsonpath='{.data.admin_password}' | base64 -d)

  # get admin URL
  CONSOLE_HOST="https://"$(oc get route -n ${TNS} cp-console -o jsonpath="{.spec.host}")
  PAK_HOST="https://"$(oc get route -n ${TNS} cpd -o jsonpath="{.spec.host}")

  # get IAM access token
  IAM_ACCESS_TK=$(curl -sk -X POST -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
        -d "grant_type=password&username=${ADMIN_USERNAME}&password=${ADMIN_PASSW}&scope=openid" \
        ${CONSOLE_HOST}/idprovider/v1/auth/identitytoken | jq -r .access_token)

  ZEN_TK=$(curl -sk "${PAK_HOST}/v1/preauth/validateAuth" -H "username:${ADMIN_USERNAME}" -H "iam-token: ${IAM_ACCESS_TK}" | jq -r .accessToken)


  # curl -skH "Authorization: Bearer ${ZEN_TK}" "${PAK_HOST}/usermgmt/v1/users" | jq

  echo "Pak console: "${CONSOLE_HOST}
  echo "Pak cpd console: "${PAK_HOST}
  echo "Pak administrator: ${ADMIN_USERNAME} / ${ADMIN_PASSW}"

  echo ""
}

LIST_OF_USERS=""
LIST_OF_RECORDS=""

#-------------------------------
loadUsersFromSecret () {

  LIST_OF_USERS=$(oc get secrets -n ${TNS} ${LDAP_DOMAIN}-customldif -o jsonpath='{.data.ldap_user\.ldif}' | base64 -d | grep "uid:" | sed 's/uid: //g')
  echo $LIST_OF_USERS > ./out.txt
  sed 's/ /+/g' -i out.txt
  LIST_OF_USERS=$(cat out.txt)
  rm out.txt
}

#-------------------------------
loadUsersFromFile () {
  LIST_OF_USERS=$(cat $1)
  echo $LIST_OF_USERS > ./out.txt
  sed 's/ /+/g' -i out.txt
  LIST_OF_USERS=$(cat out.txt)
  rm out.txt
}

#-------------------------------
# onboard users

onboardUsers () {

  IFS="+" read -ra ALL_USERS <<< "$LIST_OF_USERS"  
  UPDATED_LIST=""

  for _USR in "${ALL_USERS[@]}";
  do
    USER_RECORD='{"username":"'${_USR}'","displayName":"'${_USR}'","email":"","authenticator":"external","user_roles":["zen_user_role"],"misc":{"realm_name":"'${LDAP_DOMAIN}'","extAttributes":{}}}'
    USER_RECORD="${USER_RECORD},"
    UPDATED_LIST=${UPDATED_LIST}${USER_RECORD}
  done
  LIST_OF_RECORDS=$( echo ${UPDATED_LIST} | sed 's/.$//g')

  if [[ ! -z "${LIST_OF_RECORDS}" ]]; then
    _DATA='['${LIST_OF_RECORDS}']'
    RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -H 'Content-Type: application/json' \
                 -d $_DATA -X POST "${PAK_HOST}/usermgmt/v1/user/bulk")

    if [[ "${RESPONSE}" == *"error"* ]]; then
      echo "ERROR onboarding users"
      echo "${RESPONSE}"
      exit
    else
      echo $(echo $RESPONSE | jq '.result | length')" Users onboarded."
    fi
  else
    echo "No users to be onboarded."
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
echo "Onboarding users from domain ["${LDAP_DOMAIN}"] for namespace ["${TNS}"]"
echo "======================================================================"
echo ""

getCommonValues
if [[ "${USERS_SECRET}" = "true" ]]; then
  loadUsersFromSecret
else
  loadUsersFromFile ${USERS_FILE}
fi
onboardUsers
