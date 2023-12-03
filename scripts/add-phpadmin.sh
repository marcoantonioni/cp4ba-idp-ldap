#!/bin/bash

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
extractCreateSecretsTls () {

  oc get secrets -n ${SECRET_NAMESPACE} ${SECRET_NAME} -o jsonpath='{.data.tls\.crt}' | base64 -d > ./tls.cert
  oc get secrets -n ${SECRET_NAMESPACE} ${SECRET_NAME} -o jsonpath='{.data.tls\.key}' | base64 -d > ./tls.key

  oc get secrets -n ${SECRET_NAMESPACE} ${SECRET_NAME_WEB_UI} -o jsonpath='{.data.tls\.crt}' | base64 -d > ./common-web-ui-cert.cert
  oc get secrets -n ${SECRET_NAMESPACE} ${SECRET_NAME_WEB_UI} -o jsonpath='{.data.tls\.key}' | base64 -d > ./common-web-ui-cert.key

  resourceExist secret phpadminldap-${LDAP_DOMAIN}-root-ca ${TNS}
  if [ $? -eq 0 ]; then
    oc create secret -n ${TNS} tls phpadminldap-${LDAP_DOMAIN}-root-ca --cert=./tls.cert --key=./tls.key
  fi

  resourceExist secret phpadminldap-${LDAP_DOMAIN}-prereq-ext ${TNS}
  if [ $? -eq 0 ]; then
    oc create secret -n ${TNS} tls phpadminldap-${LDAP_DOMAIN}-prereq-ext --cert=./common-web-ui-cert.cert --key=./common-web-ui-cert.key
  fi

  rm ./tls.cert ./tls.key ./common-web-ui-cert.cert ./common-web-ui-cert.key
}

deployPHPAdmin () {
#-------------------------------------
# set image name and tag
PHPLDAPADMIN_IMAGE="cp.icr.io/cp/cp4a/demo/phpldapadmin"
PHPLDAPADMIN_TAG="0.9.0.1"

resourceExist cm php-admin-${LDAP_DOMAIN}-cm ${TNS}
if [ $? -eq 0 ]; then

#-------------------------------------
# 
cat <<EOF | oc apply -n ${TNS} -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: php-admin-${LDAP_DOMAIN}-cm
  namespace: ${TNS}
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

resourceExist deployment phpldapadmin-${LDAP_DOMAIN} ${TNS}
if [ $? -eq 0 ]; then

cat <<EOF | oc apply -n ${TNS} -f -
kind: Deployment
apiVersion: apps/v1
metadata:
  name: phpldapadmin-${LDAP_DOMAIN}
  namespace: ${TNS}
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

resourceExist service php-admin-${LDAP_DOMAIN} ${TNS}
if [ $? -eq 0 ]; then

cat <<EOF | oc apply -n ${TNS} -f -
apiVersion: v1
kind: Service
metadata:
  name: php-admin-${LDAP_DOMAIN}
  namespace: ${TNS}
spec:
  selector:
    app: phpldapadmin-${LDAP_DOMAIN}
  ports:
    - protocol: TCP
      port: 443
      targetPort: 443
EOF

fi 

resourceExist route php-admin-${LDAP_DOMAIN} ${TNS}
if [ $? -eq 0 ]; then

# create temp route
oc expose service -n ${TNS} php-admin-${LDAP_DOMAIN}

#-------------------------------------
# Build php-admin route
URL=$(oc get route -n ${TNS} php-admin-${LDAP_DOMAIN} -o jsonpath='{.spec.host}')
readarray -d . -t URLARR <<< "$URL"
PARTS=""
for (( n=0; n < ${#URLARR[*]}; n++))
do
  if [[ $n -eq 0 ]]; then
    PARTS="php-admin-${LDAP_DOMAIN}-"${TNS}
  else
    PARTS=$PARTS".${URLARR[n]}"
  fi 
done

export PHP_FQDN=$PARTS
echo "php-admin host: https://"${PHP_FQDN}

# delete temp route
oc delete route -n ${TNS} php-admin-${LDAP_DOMAIN}

#-------------------------------------
# 
cat <<EOF | oc apply -n ${TNS} -f -
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: php-admin-${LDAP_DOMAIN}
  namespace: ${TNS}
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

#===============================

if [[ -f ${PROPS_FILE} ]];
then
    source ${PROPS_FILE}
else
    echo "ERROR: Properties file "${PROPS_FILE}" not found !!!"
    exit
fi

extractCreateSecretsTls
deployPHPAdmin

PHPADMIN_USER="cn=admin,${LDAP_FULL_DOMAIN}"
PHPADMIN_PASSWORD=$(oc -n ${TNS} get secret ${LDAP_DOMAIN}-secret -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d)

echo "php-admin user[${PHPADMIN_USER}] password[${PHPADMIN_PASSWORD}]"
