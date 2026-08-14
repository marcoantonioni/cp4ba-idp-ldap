#!/bin/bash

export PVC_LDIF_STORAGE_SIZE="20Mi"
export PVC_NAME="pvc-openldap-ldif"
export STORAGE_CLASS="ocs-external-storagecluster-cephfs"
export POD_BB1="ldif-tool-1"
export POD_BB2="ldif-tool-2"
export MOUNT_PATH="/customldif"
#export LDIF_FILENAME="ldap_user.ldif"
export CTR_IMAGE="alpine:latest"

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
_NS="${TNS}"
_CFG=""

while getopts p:n:c: flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
        n) _NS=${OPTARG};;
        c) _CFG=${OPTARG};;
    esac
done

usage () {
  echo ""
  echo "usage: $_me
    -c full-path-to-environment-config-file
    -n target-namespace
    -p full-path-to-ldap-config-file"
}

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
namespaceExist () {
    if [ $(oc get ns $1 2> /dev/null | grep $1 | wc -l) -lt 1 ];
    then
        return 0
    fi
    return 1
}

#-------------------------------
createEntitlementSecrets() {

resourceExist secret pull-secret ${TNS}
if [ $? -eq 0 ]; then
  oc create secret docker-registry -n ${TNS} pull-secret \
      --docker-server=cp.icr.io \
      --docker-username=cp \
      --docker-password="${ENTITLEMENT_KEY}" 2> /dev/null 1> /dev/null

  oc secrets link -n ${TNS} default pull-secret --for=pull
fi

resourceExist secret ibm-entitlement-key ${TNS}
if [ $? -eq 0 ]; then
  oc create secret docker-registry -n ${TNS} ibm-entitlement-key \
      --docker-server=cp.icr.io \
      --docker-username=cp \
      --docker-password="${ENTITLEMENT_KEY}" 2> /dev/null 1> /dev/null
fi

}

#-------------------------------
checkParams() {

if [[ ! -z "${_CFG}" ]]; then
  if [[ -f "${_CFG}" ]]; then
    source ${_CFG}
  else
    log_error "ERROR: Configuration file "${_CFG}" not found !!!"
    usage
    exit 1
  fi
fi

if [[ -z "${PROPS_FILE}" ]]; then
  log_error "ERROR: 'PROPS_FILE' not set."
  usage
  exit 1
fi
if [[ -f "${PROPS_FILE}" ]]; then
    source ${PROPS_FILE}
else
    log_error "ERROR: Properties file "${PROPS_FILE}" not found !!!"
    usage
    exit 1
fi

if [[ -z "${LDAP_LDIF_NAME}" ]]; then
  log_error "ERROR: 'LDAP_LDIF_NAME' not set."
  usage
  exit 1
fi

if [ -z "${TNS}" ]; then
    log_error "ERROR: TNS, namespace not set"
    usage
    exit 1
fi

}

checkLDIFFile () {
  if [[ ! -f "${LDAP_LDIF_NAME}" ]]; then
    _CFG_PATH=$(dirname "$_CFG")
    LDAP_LDIF_NAME="${_CFG_PATH}/${LDAP_LDIF_NAME}"
    if [[ ! -f "${LDAP_LDIF_NAME}" ]]; then
      log_error "ERROR: file '${LDAP_LDIF_NAME}' not found."
      usage
      exit 1
    fi
  fi
}

#-------------------------------
createNamespace() {
   namespaceExist ${TNS}
   if [ $? -eq 0 ]; then
      oc new-project ${TNS} 2> /dev/null 1> /dev/null
   fi
}

#-------------------------------
createSecrets() {
  resourceExist secret ${LDAP_DOMAIN}-secret ${TNS}
  if [ $? -eq 0 ]; then
    oc create secret generic -n ${TNS} ${LDAP_DOMAIN}-secret --from-literal=LDAP_ADMIN_PASSWORD=passw0rd --from-literal=LDAP_CONFIG_PASSWORD=passw0rd 2> /dev/null 1> /dev/null
  fi

  if [[ -z "${CP4BA_INST_LDAP_USE_VOLUME}" ]] || [[ "${CP4BA_INST_LDAP_USE_VOLUME}" = "false" ]]; then
    resourceExist secret ${LDAP_DOMAIN}-customldif ${TNS}
    if [ $? -eq 0 ]; then
      oc create secret generic -n ${TNS} ${LDAP_DOMAIN}-customldif --from-file=ldap_user.ldif=${LDAP_LDIF_NAME} 2> /dev/null 1> /dev/null
    fi
  else
    oc delete secret generic -n ${TNS} ${LDAP_DOMAIN}-customldif 2> /dev/null 1> /dev/null
    oc create secret generic -n ${TNS} ${LDAP_DOMAIN}-customldif --from-literal=ldap_user.ldif='users from file' 2> /dev/null 1> /dev/null
  fi
}

#-------------------------------
createServiceAccountAndCfgMap() {

resourceExist sa ibm-cp4ba-anyuid ${TNS}
if [ $? -eq 0 ]; then

cat << EOF | oc create -n ${TNS} -f - 2> /dev/null 1> /dev/null
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ibm-cp4ba-anyuid
imagePullSecrets:
- name: 'ibm-entitlement-key'
EOF

oc adm policy add-scc-to-user anyuid -z ibm-cp4ba-anyuid -n ${TNS} 2> /dev/null 1> /dev/null

fi

resourceExist cm ${LDAP_DOMAIN}-env ${TNS}
if [ $? -eq 0 ]; then

cat << EOF | oc create -n ${TNS} -f - 2> /dev/null 1> /dev/null
kind: ConfigMap
apiVersion: v1
metadata:
  name: ${LDAP_DOMAIN}-env
data:
  LDAP_BACKEND: mdb
  LDAP_DOMAIN: ${LDAP_DOMAIN}.${LDAP_DOMAIN_EXT}
  LDAP_ORGANISATION: ${LDAP_DOMAIN} Inc.
  LDAP_REMOVE_CONFIG_AFTER_SETUP: 'true'
  LDAP_TLS: 'false'
  LDAP_TLS_ENFORCE: 'false'
EOF

fi

}

#-------------------------------
createDeployment() {

  oc delete deployment -n ${TNS} ${LDAP_DOMAIN}-ldap 2>/dev/null 1>/dev/null
  timeout=300
  counter=0
  while [ $counter -lt $timeout ]; do
    if ! oc get deployment -n ${TNS} ${LDAP_DOMAIN}-ldap &>/dev/null; then
        break
    fi
    sleep 2
    counter=$((counter + 2))
  done

  log_info "${_CLR_GREEN}Creating deployment '${_CLR_YELLOW}${LDAP_DOMAIN}-ldap${_CLR_GREEN}' using LDIF configuration via secret '${_CLR_YELLOW}${LDAP_DOMAIN}-customldif${_CLR_GREEN}'${_CLR_NC}"

cat << EOF | oc create -f - 2> /dev/null 1> /dev/null
kind: Deployment
apiVersion: apps/v1
metadata:
  name: ${LDAP_DOMAIN}-ldap
  namespace: ${TNS}
  labels:
    app: ${LDAP_DOMAIN}-ldap
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${LDAP_DOMAIN}-ldap
  template:
    metadata:
      labels:
        app: ${LDAP_DOMAIN}-ldap
    spec:
      restartPolicy: Always
      initContainers:
        - name: openldap-init-ldif
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
          command:
            - sh
            - '-c'
            - cp /customldif/* /ldifworkingdir
          resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
          volumeMounts:
            - name: customldif
              mountPath: /customldif/ldap_user.ldif
              subPath: ldap_user.ldif
            - name: ldifworkingdir
              mountPath: /ldifworkingdir
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: IfNotPresent
        - resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
          terminationMessagePath: /dev/termination-log
          name: folder-prepare-container
          command:
            - /bin/bash
            - '-ecx'
            - >
              rm -rf /etc-folder/* && cp -rp /etc/* /etc-folder || true && rm
              -rf /var-lib-folder/* && cp -rp /var/lib/* /var-lib-folder || true
              && (rm -rf /usr-folder/* && cp -rp /usr/sbin/* /usr-folder && rm
              -rf /var-cache-folder/* && cp -rp /var/cache/debconf/*
              /var-cache-folder || true) && rm -rf /container-run-folder/* && cp
              -rp /container/* /container-run-folder || true
          securityContext:
            capabilities:
              drop:
                - ALL
            privileged: false
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: usr-folder-pvc
              mountPath: usr-folder
            - name: var-cache-folder-pvc
              mountPath: var-cache-folder
            - name: container-run-folder-pvc
              mountPath: container-run-folder
            - name: etc-ldap-folder-pvc
              mountPath: etc-folder
            - name: var-lib-folder-pvc
              mountPath: var-lib-folder
          terminationMessagePolicy: File
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
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
          readinessProbe:
            tcpSocket:
              port: ldap-port
            initialDelaySeconds: 20
            timeoutSeconds: 1
            periodSeconds: 10
            successThreshold: 1
            failureThreshold: 10
          terminationMessagePath: /dev/termination-log
          name: ${LDAP_DOMAIN}-ldap
          livenessProbe:
            tcpSocket:
              port: ldap-port
            initialDelaySeconds: 20
            timeoutSeconds: 1
            periodSeconds: 10
            successThreshold: 1
            failureThreshold: 10
          ports:
            - name: ldap-port
              containerPort: 389
              protocol: TCP
            - name: ssl-ldap-port
              containerPort: 636
              protocol: TCP
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: data
              mountPath: /var/lib/ldap
              subPath: data
            - name: data
              mountPath: /etc/ldap/slapd.d
              subPath: config-data
            - name: ldifworkingdir
              mountPath: /container/service/slapd/assets/config/bootstrap/ldif/custom
            - name: etc-ldap-folder-pvc
              mountPath: /etc
            - name: temp-pvc
              mountPath: /tmp
            - name: usr-folder-pvc
              mountPath: /usr/sbin
            - name: var-backup-folder-pvc
              mountPath: /var/backups/slapd-2.4.57+dfsg-3~bpo10+1
            - name: var-lib-folder-pvc
              mountPath: /var/lib
            - name: var-cache-folder-pvc
              mountPath: /var/cache/debconf
            - name: container-run-folder-pvc
              mountPath: /container
          terminationMessagePolicy: File
          envFrom:
            - configMapRef:
                name: ${LDAP_DOMAIN}-env
            - secretRef:
                name: ${LDAP_DOMAIN}-secret
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
          args:
            - '--copy-service'
      serviceAccount: ibm-cp4ba-anyuid
      volumes:
        - name: customldif
          secret:
            secretName: ${LDAP_DOMAIN}-customldif
            defaultMode: 420
        - name: ldifworkingdir
          emptyDir: {}
        - name: certs
          emptyDir:
            medium: Memory
        - name: data
          emptyDir: {}
        - name: etc-ldap-folder-pvc
          emptyDir: {}
        - name: temp-pvc
          emptyDir: {}
        - name: usr-folder-pvc
          emptyDir: {}
        - name: var-backup-folder-pvc
          emptyDir: {}
        - name: var-cache-folder-pvc
          emptyDir: {}
        - name: var-lib-folder-pvc
          emptyDir: {}
        - name: container-run-folder-pvc
          emptyDir: {}
EOF

  oc expose deployment -n ${TNS} ${LDAP_DOMAIN}-ldap 2> /dev/null 1> /dev/null
}

createPVCForLDIF () {
  log_info "${_CLR_GREEN}Creating Persistent Volume Claim '${_CLR_YELLOW}${PVC_NAME}${_CLR_GREEN}'"

  oc delete pvc -n ${TNS} ${PVC_NAME} 2>/dev/null 1>/dev/null
  timeout=300
  counter=0
  while [ $counter -lt $timeout ]; do
    if ! oc get pvc -n ${TNS} ${PVC_NAME} &>/dev/null; then
        break
    fi
    sleep 2
    counter=$((counter + 2))
  done

cat <<EOF | oc apply -f - 2>/dev/null 1>/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${TNS}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${PVC_LDIF_STORAGE_SIZE}
  storageClassName: ${STORAGE_CLASS}
EOF

  #log_info "Waiting for PVC to be bound..."
  timeout=300
  counter=0
  while [ $counter -lt $timeout ]; do
    status=$(oc get pvc -n ${TNS} ${PVC_NAME} -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$status" == "Bound" ]; then
      break
    fi
    sleep 2
    counter=$((counter + 2))
  done

  if [ "$status" != "Bound" ]; then
    log_error "ERROR: PVC did not bind within $timeout seconds"
    exit 1
  fi

}

loadLDIFToPVC () {
  log_info "${_CLR_GREEN}Loading LDIF file in PVC '${_CLR_YELLOW}${PVC_NAME}${_CLR_GREEN}'"

cat <<EOF | oc apply -f - 2>/dev/null 1>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $POD_BB1
  namespace: ${TNS}
spec:
  serviceAccountName: ibm-cp4ba-anyuid
  serviceAccount: ibm-cp4ba-anyuid
  securityContext:
    runAsUser: 0
    runAsGroup: 0
    fsGroup: 0
  containers:
  - name: $POD_BB1
    image: $CTR_IMAGE
    volumeMounts:
    - name: ldif-storage
      mountPath: $MOUNT_PATH
    command: ['/bin/sh', '-c', 'sleep infinity']
  volumes:
  - name: ldif-storage
    persistentVolumeClaim:
      claimName: ${PVC_NAME}
EOF

  oc wait --for=condition=Ready -n ${TNS} pod/$POD_BB1 --timeout=300s 2>/dev/null 1>/dev/null

  oc exec -n ${TNS} $POD_BB1 -- mkdir -p $MOUNT_PATH 2>/dev/null 1>/dev/null
  oc cp ${LDAP_LDIF_NAME} -n ${TNS} ${POD_BB1}:${MOUNT_PATH}/ldap_user.ldif 2>/dev/null 1>/dev/null
  oc delete pod -n ${TNS} $POD_BB1 2>/dev/null 1>/dev/null
  #timeout=300
  #counter=0
  #while [ $counter -lt $timeout ]; do
  #  if ! oc get pod -n ${TNS} $POD_BB1 &>/dev/null; then
  #      break
  #  fi
  #  sleep 2
  #  counter=$((counter + 2))
  #done
#
  #if oc get pod -n ${TNS} $POD_BB1 &>/dev/null; then
  #  log_warning "${_CLR_GREEN}Pod '${_CLR_YELLOW}${POD_BB1}${_CLR_GREEN}' not deleted."
  #fi
}

setupLDIF () {
  createPVCForLDIF
  loadLDIFToPVC
}

createDeploymentVolume () {

  oc delete deployment -n ${TNS} ${LDAP_DOMAIN}-ldap 2>/dev/null 1>/dev/null
  timeout=300
  counter=0
  while [ $counter -lt $timeout ]; do
    if ! oc get deployment -n ${TNS} ${LDAP_DOMAIN}-ldap &>/dev/null; then
        break
    fi
    sleep 2
    counter=$((counter + 2))
  done

  setupLDIF

  log_info "${_CLR_GREEN}Creating deployment '${_CLR_YELLOW}${LDAP_DOMAIN}-ldap${_CLR_GREEN}' using LDIF configuration via PVC '${_CLR_YELLOW}${PVC_NAME}${_CLR_GREEN}'${_CLR_NC}"

cat << EOF | oc create -f - 2> /dev/null 1> /dev/null
kind: Deployment
apiVersion: apps/v1
metadata:
  name: ${LDAP_DOMAIN}-ldap
  namespace: ${TNS}
  labels:
    app: ${LDAP_DOMAIN}-ldap
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${LDAP_DOMAIN}-ldap
  template:
    metadata:
      labels:
        app: ${LDAP_DOMAIN}-ldap
    spec:
      restartPolicy: Always
      initContainers:
        - name: openldap-init-ldif
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
          command:
            - sh
            - '-c'
            - cp /customldif/* /ldifworkingdir
          resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
          volumeMounts:
            - name: customldif
              mountPath: /customldif/ldap_user.ldif
              subPath: ldap_user.ldif
            - name: ldifworkingdir
              mountPath: /ldifworkingdir
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: IfNotPresent
        - resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
          terminationMessagePath: /dev/termination-log
          name: folder-prepare-container
          command:
            - /bin/bash
            - '-ecx'
            - >
              rm -rf /etc-folder/* && cp -rp /etc/* /etc-folder || true && rm
              -rf /var-lib-folder/* && cp -rp /var/lib/* /var-lib-folder || true
              && (rm -rf /usr-folder/* && cp -rp /usr/sbin/* /usr-folder && rm
              -rf /var-cache-folder/* && cp -rp /var/cache/debconf/*
              /var-cache-folder || true) && rm -rf /container-run-folder/* && cp
              -rp /container/* /container-run-folder || true
          securityContext:
            capabilities:
              drop:
                - ALL
            privileged: false
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: usr-folder-pvc
              mountPath: usr-folder
            - name: var-cache-folder-pvc
              mountPath: var-cache-folder
            - name: container-run-folder-pvc
              mountPath: container-run-folder
            - name: etc-ldap-folder-pvc
              mountPath: etc-folder
            - name: var-lib-folder-pvc
              mountPath: var-lib-folder
          terminationMessagePolicy: File
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
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
          readinessProbe:
            tcpSocket:
              port: ldap-port
            initialDelaySeconds: 20
            timeoutSeconds: 1
            periodSeconds: 10
            successThreshold: 1
            failureThreshold: 10
          terminationMessagePath: /dev/termination-log
          name: ${LDAP_DOMAIN}-ldap
          livenessProbe:
            tcpSocket:
              port: ldap-port
            initialDelaySeconds: 20
            timeoutSeconds: 1
            periodSeconds: 10
            successThreshold: 1
            failureThreshold: 10
          ports:
            - name: ldap-port
              containerPort: 389
              protocol: TCP
            - name: ssl-ldap-port
              containerPort: 636
              protocol: TCP
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: data
              mountPath: /var/lib/ldap
              subPath: data
            - name: data
              mountPath: /etc/ldap/slapd.d
              subPath: config-data
            - name: ldifworkingdir
              mountPath: /container/service/slapd/assets/config/bootstrap/ldif/custom
            - name: etc-ldap-folder-pvc
              mountPath: /etc
            - name: temp-pvc
              mountPath: /tmp
            - name: usr-folder-pvc
              mountPath: /usr/sbin
            - name: var-backup-folder-pvc
              mountPath: /var/backups/slapd-2.4.57+dfsg-3~bpo10+1
            - name: var-lib-folder-pvc
              mountPath: /var/lib
            - name: var-cache-folder-pvc
              mountPath: /var/cache/debconf
            - name: container-run-folder-pvc
              mountPath: /container
          terminationMessagePolicy: File
          envFrom:
            - configMapRef:
                name: ${LDAP_DOMAIN}-env
            - secretRef:
                name: ${LDAP_DOMAIN}-secret
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
          args:
            - '--copy-service'
      serviceAccount: ibm-cp4ba-anyuid
      volumes:
        - name: customldif
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
        - name: ldifworkingdir
          emptyDir: {}
        - name: certs
          emptyDir:
            medium: Memory
        - name: data
          emptyDir: {}
        - name: etc-ldap-folder-pvc
          emptyDir: {}
        - name: temp-pvc
          emptyDir: {}
        - name: usr-folder-pvc
          emptyDir: {}
        - name: var-backup-folder-pvc
          emptyDir: {}
        - name: var-cache-folder-pvc
          emptyDir: {}
        - name: var-lib-folder-pvc
          emptyDir: {}
        - name: container-run-folder-pvc
          emptyDir: {}
EOF

oc expose deployment -n ${TNS} ${LDAP_DOMAIN}-ldap 2> /dev/null 1> /dev/null

}

#-------------------------------
waitForDeploymentReady () {
#    echo "namespace name: $1"
#    echo "resource name: $2"
#    echo "time to wait: $3"

  _seconds=0
  while true 
  do
    REPLICAS=$(oc get deployment -n $1 $2 -o jsonpath="{.status.replicas}")
    READY_REPLICAS=$(oc get deployment -n $1 $2 -o jsonpath="{.status.readyReplicas}")
    if [ "${REPLICAS}" = "${READY_REPLICAS}" ]; then
      # log_info "Resource '$2' in namespace '$1' is ready"
      break
    else
      ((_seconds=_seconds+1))
      # echo -e -n "Wait for resource '$2' in namespace '$1' to be READY [$_seconds]\033[0K\r"
      sleep 1
    fi
  done
}

#===============================

log_msg "=============================================================="
log_info "${_CLR_GREEN}Installing LDAP${_CLR_NC}"

checkParams
checkLDIFFile

log_info "${_CLR_GREEN}Target namespace '${_CLR_YELLOW}${TNS}${_CLR_GREEN}'${_CLR_NC}"
log_info "${_CLR_GREEN}Using LDIF file '${_CLR_YELLOW}${LDAP_LDIF_NAME}${_CLR_GREEN}'"

createNamespace

createEntitlementSecrets

createSecrets

createServiceAccountAndCfgMap

# 20260605
if [[ -z "${CP4BA_INST_LDAP_USE_VOLUME}" ]] || [[ "${CP4BA_INST_LDAP_USE_VOLUME}" = "false" ]]; then
  createDeployment
else
  createDeploymentVolume
fi

waitForDeploymentReady ${TNS} ${LDAP_DOMAIN}-ldap ${LDAP_WAIT_SECS}


LDAP_SVC_NAME=$(oc get services -n ${TNS} | grep ${LDAP_DOMAIN}-ldap | awk '{print $1}')
log_info "Your LDAP service url is '${_CLR_YELLOW}"${LDAP_SVC_NAME}.${TNS}.svc.cluster.local${_CLR_NC}"'"
# log_info "LDAP service ports"
# oc get service -n ${TNS} ${LDAP_SVC_NAME} -o yaml | grep port:

log_debug "Full addresses"
log_debug "  ${_CLR_YELLOW}ldap://${LDAP_SVC_NAME}.${TNS}.svc.cluster.local:389${_CLR_NC}"
log_debug "  ${_CLR_YELLOW}ldaps://${LDAP_SVC_NAME}.${TNS}.svc.cluster.local:636${_CLR_NC}"
log_info "LDAP installed."