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

while getopts p:s:n:w: flag
do
  case "${flag}" in
    p) PROPS_FILE=${OPTARG};;
    n) SECRET_NAMESPACE=${OPTARG};;
    s) SECRET_NAME=${OPTARG};;
    w) SECRET_NAME_WEB_UI=${OPTARG};;
  esac
done

usage () {
  echo ""
  echo "usage: $_me
    -s secret-name
    -w web-ui-secret-name
    -n target-namespace
    -p full-path-to-ldap-config-file"
}


#-------------------------------
resourceExist () {
  # $1 type
  # $2 name
  # $3 namespace
    if [ $(oc get -n $3 $1 $2 2>/dev/null 1>/dev/null | grep $2 | wc -l) -lt 1 ]; then
        return 0
    fi
    return 1
}

#-------------------------------
extractCreateSecretsTls () {
  log_info "Create secrets"
  oc get secrets -n ${SECRET_NAMESPACE} ${SECRET_NAME} -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > ./tls.cert
  oc get secrets -n ${SECRET_NAMESPACE} ${SECRET_NAME} -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > ./tls.key

  oc get secrets -n ${SECRET_NAMESPACE} ${SECRET_NAME_WEB_UI} -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > ./common-web-ui-cert.cert
  oc get secrets -n ${SECRET_NAMESPACE} ${SECRET_NAME_WEB_UI} -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > ./common-web-ui-cert.key

  resourceExist secret phpadminldap-${LDAP_DOMAIN}-root-ca ${SECRET_NAMESPACE}
  if [ $? -eq 0 ]; then
    oc create secret -n ${SECRET_NAMESPACE} tls phpadminldap-${LDAP_DOMAIN}-root-ca --cert=./tls.cert --key=./tls.key 2>/dev/null 1>/dev/null
  fi

  resourceExist secret phpadminldap-${LDAP_DOMAIN}-prereq-ext ${SECRET_NAMESPACE}
  if [ $? -eq 0 ]; then
    oc create secret -n ${SECRET_NAMESPACE} tls phpadminldap-${LDAP_DOMAIN}-prereq-ext --cert=./common-web-ui-cert.cert --key=./common-web-ui-cert.key 2>/dev/null 1>/dev/null
  fi

  rm ./tls.cert ./tls.key ./common-web-ui-cert.cert ./common-web-ui-cert.key 2>/dev/null 1>/dev/null
}

deployPHPAdmin () {
  log_info "Deploy phpldapadmin"
#-------------------------------------
# set image name and tag
PHPLDAPADMIN_IMAGE="cp.icr.io/cp/cp4a/demo/phpldapadmin"
PHPLDAPADMIN_TAG="0.9.0.1"

resourceExist cm php-admin-${LDAP_DOMAIN}-cm ${SECRET_NAMESPACE}
if [ $? -eq 0 ]; then

#-------------------------------------
# 
cat <<EOF | oc apply -n ${SECRET_NAMESPACE} -f - 2>/dev/null 1>/dev/null
kind: ConfigMap
apiVersion: v1
metadata:
  name: php-admin-${LDAP_DOMAIN}-cm
  namespace: ${SECRET_NAMESPACE}
  labels:
    app: phpldapadmin
    chart: phpldapadmin-0.1.3
    heritage: Tiller
    release: phpldapadmin
data:
  PHPLDAPADMIN_HTTPS: 'true'
  PHPLDAPADMIN_HTTPS_CA_CRT_FILENAME: ca.crt
  PHPLDAPADMIN_HTTPS_CRT_FILENAME: tls.crt
  PHPLDAPADMIN_HTTPS_KEY_FILENAME: tls.key
  PHPLDAPADMIN_LDAP_HOSTS: ${LDAP_DOMAIN}-ldap
EOF

fi

#-------------------------------------
# 

resourceExist deployment phpldapadmin-${LDAP_DOMAIN} ${SECRET_NAMESPACE}
if [ $? -eq 0 ]; then

cat <<EOF | oc apply -n ${SECRET_NAMESPACE} -f - 2>/dev/null 1>/dev/null
kind: Deployment
apiVersion: apps/v1
metadata:
  name: phpldapadmin-${LDAP_DOMAIN}
  namespace: ${SECRET_NAMESPACE}
  labels:
    app: phpldapadmin-${LDAP_DOMAIN}
    chart: phpldapadmin-0.1.3
    heritage: Tiller
    release: phpldapadmin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phpldapadmin-${LDAP_DOMAIN}
      release: phpldapadmin
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: phpldapadmin-${LDAP_DOMAIN}
        release: phpldapadmin
    spec:
      restartPolicy: Always
      initContainers:
        - name: phpldapadmin-init-certs
          image: '${PHPLDAPADMIN_IMAGE}:${PHPLDAPADMIN_TAG}'
          command:
            - /bin/sh
            - '-ec'
            - |
              cp /rootca/tls.crt /certs/ca.crt
              cp /tlssecret/* /certs
          resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
          volumeMounts:
            - name: phpldapadmin-certs
              mountPath: /certs
            - name: rootcasecret
              mountPath: /rootca
            - name: tlssecret
              mountPath: /tlssecret
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: IfNotPresent
      serviceAccountName: ibm-cp4ba-anyuid
      terminationGracePeriodSeconds: 30
      securityContext: {}
      containers:
        - resources:
            limits:
              cpu: 500m
              memory: 512Mi
            requests:
              cpu: 100m
              memory: 256Mi
          terminationMessagePath: /dev/termination-log
          name: phpldapadmin
          ports:
            - name: https-port
              containerPort: 443
              protocol: TCP
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: phpldapadmin-certs
              mountPath: /container/service/phpldapadmin/assets/apache2/certs
          terminationMessagePolicy: File
          envFrom:
            - configMapRef:
                name: php-admin-${LDAP_DOMAIN}-cm
          image: '${PHPLDAPADMIN_IMAGE}:${PHPLDAPADMIN_TAG}'
          args:
            - '--copy-service'
      serviceAccount: ibm-cp4ba-anyuid
      volumes:
        - name: phpldapadmin-certs
          emptyDir: {}
        - name: rootcasecret
          secret:
            secretName: phpadminldap-${LDAP_DOMAIN}-root-ca
            defaultMode: 420
        - name: tlssecret
          secret:
            secretName: phpadminldap-${LDAP_DOMAIN}-prereq-ext
            defaultMode: 420
      dnsPolicy: ClusterFirst
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
EOF

fi

#-------------------------------------
# 

resourceExist service php-admin-${LDAP_DOMAIN} ${SECRET_NAMESPACE}
if [ $? -eq 0 ]; then

cat <<EOF | oc apply -n ${SECRET_NAMESPACE} -f - 2>/dev/null 1>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: php-admin-${LDAP_DOMAIN}
  namespace: ${SECRET_NAMESPACE}
spec:
  selector:
    app: phpldapadmin-${LDAP_DOMAIN}
  ports:
    - protocol: TCP
      port: 443
      targetPort: 443
EOF

fi 

resourceExist route php-admin-${LDAP_DOMAIN} ${SECRET_NAMESPACE}
if [ $? -eq 0 ]; then

# create temp route
oc expose service -n ${SECRET_NAMESPACE} php-admin-${LDAP_DOMAIN} 2>/dev/null 1>/dev/null

#-------------------------------------
# Build php-admin route
URL=$(oc get route -n ${SECRET_NAMESPACE} php-admin-${LDAP_DOMAIN} -o jsonpath='{.spec.host}')
readarray -d . -t URLARR <<< "$URL"
PARTS=""
for (( n=0; n < ${#URLARR[*]}; n++))
do
  if [[ $n -eq 0 ]]; then
    PARTS="php-admin-${LDAP_DOMAIN}-"${SECRET_NAMESPACE}
  else
    PARTS=$PARTS".${URLARR[n]}"
  fi 
done

export PHP_FQDN=$(echo -en "$PARTS")

oc delete route -n ${SECRET_NAMESPACE} php-admin-${LDAP_DOMAIN} 2>/dev/null 1>/dev/null

#-------------------------------------
# 
cat <<EOF | oc apply -n ${SECRET_NAMESPACE} -f - 2>/dev/null 1>/dev/null
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: php-admin-${LDAP_DOMAIN}
  namespace: ${SECRET_NAMESPACE}
spec:
  host: >-
    ${PHP_FQDN}
  to:
    kind: Service
    name: php-admin-${LDAP_DOMAIN}
    weight: 100
  port:
    targetPort: 443
  tls:
    termination: passthrough
    insecureEdgeTerminationPolicy: None
  wildcardPolicy: None
EOF

fi

}

log_msg "=============================================================="
log_info "Installing LDAP PHPAdmin"
log_info "${_CLR_GREEN}Namespace '${_CLR_YELLOW}${SECRET_NAMESPACE}${_CLR_GREEN}'${_CLR_NC}"
if [[ -z "${PROPS_FILE}" ]]; then
  log_error "ERROR: variable 'PROPS_FILE' not defined"
  exit 1
fi
if [[ -f ${PROPS_FILE} ]];
then
  source ${PROPS_FILE}
else
  log_error "ERROR: Properties file '${PROPS_FILE}' not found !!!"
  exit 1
fi

extractCreateSecretsTls
deployPHPAdmin

PHPADMIN_USER="cn=admin,${LDAP_FULL_DOMAIN}"
PHPADMIN_PASSWORD=$(oc -n ${SECRET_NAMESPACE} get secret ${LDAP_DOMAIN}-secret -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d)

log_info "Installation completed"

log_info "${_CLR_GREEN}php-admin host: '${_CLR_YELLOW}https://${PHP_FQDN}${_CLR_GREEN}'${_CLR_NC}"
log_info "${_CLR_GREEN}php-admin user '${_CLR_YELLOW}${PHPADMIN_USER}${_CLR_GREEN}' password '${_CLR_YELLOW}${PHPADMIN_PASSWORD}${_CLR_GREEN}'${_CLR_NC}"
