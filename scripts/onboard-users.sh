#!/bin/bash

#-------------------------------
# read installation parameters
PROPS_FILE=""
LDAP_FILE=""
USERS_FILE=""
USERS_SECRET=false
OPERATION_MODE=""
_TNS=""
_LIST_ROLES=false

while getopts p:l:n:u:o:sr flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
        l) LDAP_FILE=${OPTARG};;
        n) _TNS=${OPTARG};;
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
  waitForResourceCreated ${TNS} "route" "cpd" 10

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

  echo "Pak console: "${CONSOLE_HOST}
  echo "Pak cpd console: "${PAK_HOST}
  echo "Pak administrator: ${ADMIN_USERNAME} / ${ADMIN_PASSW}"
}

LIST_OF_USERS=""
LIST_OF_RECORDS=""

#-------------------------------
loadUsersFromSecret () {
  echo "Loading users from secret '${LDAP_DOMAIN}-customldif'"
  resourceExist ${TNS} "secret" ${LDAP_DOMAIN}-customldif
  if [ $? -eq 1 ]; then
    LIST_OF_USERS=$(oc get secrets -n ${TNS} ${LDAP_DOMAIN}-customldif -o jsonpath='{.data.ldap_user\.ldif}' | base64 -d | grep "uid:" | sed 's/uid: //g')
    # because sed -i & Darwin...
    _FNAME="/tmp/pak-onboard-users-$USER-$RANDOM"
    _FNAME2="${_FNAME}-transformed"
    echo $LIST_OF_USERS > ${_FNAME}
    #sed 's/ /+/g' -i ${_FNAME}
    cat ${_FNAME} | sed 's/ /+/g' > ${_FNAME2}    
    LIST_OF_USERS=$(cat ${_FNAME2})
    rm ${_FNAME} 2>/dev/null
    rm ${_FNAME2} 2>/dev/null
  else
    echo "ERROR: secret '${LDAP_DOMAIN}-customldif' not found in namespace '${TNS}'"
    exit 1
  fi
}

#-------------------------------
loadUsersFromFile () {
  echo "Loading users from file '$1'"

  if [[ -f $1 ]];
  then
    _FNAME="/tmp/pak-onboard-users-$USER-$RANDOM"
    LIST_OF_USERS=$(cat $1)
    # because sed -i & Darwin...
    _FNAME="/tmp/pak-onboard-users-$USER-$RANDOM"
    _FNAME2="${_FNAME}-transformed"
    echo $LIST_OF_USERS > ${_FNAME}
    #sed 's/ /+/g' -i ${_FNAME}
    cat ${_FNAME} | sed 's/ /+/g' > ${_FNAME2}    
    LIST_OF_USERS=$(cat ${_FNAME2})
    rm ${_FNAME} 2>/dev/null
    rm ${_FNAME2} 2>/dev/null
  else
      echo "ERROR: Users file "$1" not found !!!"
      exit 1
  fi

}

#-------------------------------
# onboard users add

onboardUsersAdd () {

  IFS="+" read -ra ALL_USERS <<< "$LIST_OF_USERS"  
  tot_users=${#ALL_USERS[@]}
  UPDATED_LIST=""

  _ADMINS=()
  if [[ ! -z "${LDAP_ADMINS}" ]]; then
    IFS=',' read -a _ADMINS <<< "${LDAP_ADMINS}"
  fi

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
  done
  LIST_OF_RECORDS=$( echo ${UPDATED_LIST} | sed 's/.$//g')

  if [[ ! -z "${LIST_OF_RECORDS}" ]]; then
    echo "Adding $tot_users users..."

    _DATA='['${LIST_OF_RECORDS}']'
    RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -H 'Content-Type: application/json' \
                 -d $_DATA -X POST "${PAK_HOST}/usermgmt/v1/user/bulk")
    if [[ "${RESPONSE}" == *"error"* ]]; then
      echo "ERROR adding users"
      echo "${RESPONSE}"
      exit 1
    else
      RES=$(echo $RESPONSE | jq ._messageCode_ | sed 's/"//g')
      if [[ "${RES}" = "Success" ]]; then
        echo $(echo $RESPONSE | jq '.result | length')" Users operated in mode 'add'"
      else
        MSG=$(echo $RESPONSE | jq .message | sed 's/"//g')
        echo "ERROR: "${RES}" - "${MSG}
        echo $RESPONSE
      fi
    fi

    #_ALL_USERS=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -X GET "${PAK_HOST}/usermgmt/v1/usermgmt/users?include_profile_picture=true&offset=0&limit=500&sort_order=DESC&sort_by=created_timestamp&include_users_count=true")  
    #echo $_ALL_USERS | jq .

  else
    echo "No users to add."
  fi
}


#-------------------------------
# onboard users remove

onboardUsersRemove () {
  IFS="+" read -ra ALL_USERS <<< "$LIST_OF_USERS"

  tot_users=${#ALL_USERS[@]}

  if [[ $tot_users -gt 0 ]]; then
    echo "Removing $tot_users users..."

    for _USR in "${ALL_USERS[@]}";
    do
      RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' \
                  -X DELETE "${PAK_HOST}/usermgmt/v1/user/${_USR}")
      if [[ "${RESPONSE}" == *"exception"* ]]; then
        echo "ERROR removing user '${_USR}' message: "$(echo "${RESPONSE}" | jq .exception)
        tot_users=$((tot_users-1))      
      fi

    done
    echo "$tot_users Users operated in mode 'remove'"

  else
    echo "No users to remove."
  fi

}

#-------------------------------

if [[ -f ${PROPS_FILE} ]];
then
    source ${PROPS_FILE}
else
    echo "ERROR: Configuration properties file "${PROPS_FILE}" not found !!!"
    exit 1
fi

#if [[ -f ${LDAP_FILE} ]];
#then
#    source ${LDAP_FILE}
#else
#    echo "ERROR: LDAP properties file "${LDAP_FILE}" not found !!!"
#    exit 1
#fi

if [[ "${_TNS}" != "" ]]; then
  TNS="${_TNS}"
fi


echo "=============================================================="
echo "Onboard users from domain ["${LDAP_DOMAIN}"] for namespace ["${TNS}"]"
echo "=============================================================="

if [[ "${_LIST_ROLES}" = "true" ]]; then
  getCommonValues
  echo ""
  echo "Roles:"
  RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -H 'Content-Type: application/json' \
              "${PAK_HOST}/usermgmt/v1/roles")
  echo $RESPONSE | jq .

  echo ""
  echo "Groups:"
  RESPONSE=$(curl -sk -H "Authorization: Bearer ${ZEN_TK}" -H 'accept: application/json' -H 'Content-Type: application/json' \
              "${PAK_HOST}/usermgmt/v2/groups")
  echo $RESPONSE | jq .

  exit
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
  echo "ERROR, set operation mode using -o [add|remove|remove-and-add]"
  exit 1
fi
