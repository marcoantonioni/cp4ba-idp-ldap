#!/bin/bash

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
    if [ $(oc get ns $1 | grep $1 | wc -l) -lt 1 ];
    then
        return 0
    fi
    return 1
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
if [[ -f "${LDAP_LDIF_NAME}" ]]; then
  log_info "Using LDIF ${LDAP_LDIF_NAME}"
else
  _CFG_PATH=$(dirname "$_CFG")
  LDAP_LDIF_NAME="${_CFG_PATH}/${LDAP_LDIF_NAME}"
  if [[ -f "${LDAP_LDIF_NAME}" ]]; then
    log_info "Using LDIF ${LDAP_LDIF_NAME}"
  else
    log_error "ERROR: file '${LDAP_LDIF_NAME}' not found."
    usage
    exit 1
  fi
fi

if [ -z "${TNS}" ]; then
    log_error "ERROR: TNS, namespace not set"
    usage
    exit 1
fi

}


echo "=== Create and test LDIF stored in Volume ==="
echo ""

checkParams

resourceExist secret serviceaccounts ${TNS}
if [ $? -eq 0 ]; then

  oc delete serviceaccounts ibm-cp4ba-anyuid
  cat << EOF | oc create -f -
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: ibm-cp4ba-anyuid
  EOF

  oc adm policy add-scc-to-user anyuid -z ibm-cp4ba-anyuid
fi

# Variables
PVC_NAME="pvc-openldap-ldif"
STORAGE_CLASS="ocs-external-storagecluster-cephfs"
STORAGE_SIZE="20Mi"
POD_BB1="ldif-tool-1"
POD_BB2="ldif-tool-2"
#MOUNT_PATH="/etc/ldap/ldif/custom"
MOUNT_PATH="/customldif"
LDIF_FILENAME="ldap_user.ldif"
LOCAL_LDIF_FILE="${1:-./data.ldif}"  # Accept ldif file path as argument, default to ./data.ldif
CTR_IMAGE="alpine:latest"

# Check if local LDIF file exists
if [ ! -f "$LOCAL_LDIF_FILE" ]; then
    echo "ERROR: Local LDIF file '$LOCAL_LDIF_FILE' not found!"
    echo "Usage: $0 [path-to-ldif-file]"
    exit 1
fi

echo "Configuration:"
echo "  PVC Name: $PVC_NAME"
echo "  Storage Size: $STORAGE_SIZE"
echo "  Storage class: $STORAGE_CLASS"
echo "  Local LDIF File: $LOCAL_LDIF_FILE"
echo "  Mount Path: $MOUNT_PATH"
echo ""

echo "Step 1: Setup..."

oc delete pod $POD_BB1
oc delete pod $POD_BB2
oc delete pvc $PVC_NAME


# Step 2: Create PVC (Persistent Volume Claim)
echo "Step 2: Creating Persistent Volume Claim (PVC)..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $STORAGE_SIZE
  storageClassName: "$STORAGE_CLASS"
EOF

echo "✓ PVC '$PVC_NAME' created successfully"
echo ""

# Wait for PVC to be bound
echo "Waiting for PVC to be bound..."
timeout=60
counter=0
while [ $counter -lt $timeout ]; do
    status=$(oc get pvc $PVC_NAME -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$status" == "Bound" ]; then
        echo "✓ PVC is bound"
        break
    fi
    sleep 2
    counter=$((counter + 2))
done

if [ "$status" != "Bound" ]; then
    echo "ERROR: PVC did not bind within $timeout seconds"
    exit 1
fi
echo ""

# Step 3: Create pod bb1 and mount PVC
echo "Step 3: Creating pod '$POD_BB1' with PVC mounted..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_BB1
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
    #securityContext:
    #  runAsUser: 0
    #  runAsGroup: 0
    #  #fsGroup: 0
    #  allowPrivilegeEscalation: true
    command: ['/bin/sh', '-c', 'sleep infinity']
  volumes:
  - name: ldif-storage
    persistentVolumeClaim:
      claimName: $PVC_NAME
EOF

echo "✓ Pod '$POD_BB1' created successfully"
echo ""

# Wait for pod bb1 to be ready
echo "Waiting for pod '$POD_BB1' to be ready..."
oc wait --for=condition=Ready pod/$POD_BB1 --timeout=120s
echo "✓ Pod '$POD_BB1' is ready"
echo ""

# Step 4: Copy local LDIF file to PVC via pod bb1
echo "Step 4: Copying local LDIF file to PVC via pod '$POD_BB1'..."
oc exec $POD_BB1 -- mkdir -p $MOUNT_PATH
#oc exec $POD_BB1 -- ls -al $MOUNT_PATH
#oc exec $POD_BB1 -- whoami 
oc cp "$LOCAL_LDIF_FILE" $POD_BB1:$MOUNT_PATH/$LDIF_FILENAME
echo "✓ LDIF file copied to PVC"
echo ""

# Verify file was copied
echo "Verifying file in pod '$POD_BB1'..."
oc exec $POD_BB1 -- ls -la $MOUNT_PATH
echo ""

# Step 5: Delete pod bb1
echo "Step 5: Deleting pod '$POD_BB1'..."
oc delete pod $POD_BB1
echo "✓ Pod '$POD_BB1' deleted successfully"
echo ""

# Wait for pod to be fully deleted
echo "Waiting for pod '$POD_BB1' to be fully deleted..."
timeout=60
counter=0
while [ $counter -lt $timeout ]; do
    if ! oc get pod $POD_BB1 &>/dev/null; then
        echo "✓ Pod '$POD_BB1' fully deleted"
        break
    fi
    sleep 2
    counter=$((counter + 2))
done
echo ""

# Step 6: Create pod bb2 and mount PVC
echo "Step 6: Creating pod '$POD_BB2' with PVC mounted..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_BB2
spec:
  serviceAccountName: ibm-cp4ba-anyuid
  serviceAccount: ibm-cp4ba-anyuid
  securityContext:
    runAsUser: 0
    runAsGroup: 0
    fsGroup: 0
  containers:
  - name: $POD_BB2
    image: $CTR_IMAGE
    volumeMounts:
    - name: ldif-storage
      mountPath: $MOUNT_PATH
    #securityContext:
    #  runAsUser: 0
    #  runAsGroup: 0
    #  #fsGroup: 0
    #  allowPrivilegeEscalation: true
    command: ['/bin/sh', '-c', 'sleep infinity']
  volumes:
  - name: ldif-storage
    persistentVolumeClaim:
      claimName: $PVC_NAME
EOF

echo "✓ Pod '$POD_BB2' created successfully"
echo ""

# Wait for pod bb2 to be ready
echo "Waiting for pod '$POD_BB2' to be ready..."
oc wait --for=condition=Ready pod/$POD_BB2 --timeout=120s
echo "✓ Pod '$POD_BB2' is ready"
echo ""

# Step 7: Execute remote shell to bb2 and cat LDIF file
echo "Step 7: List LDIF file from PVC via pod '$POD_BB2'..."
echo "----------------------------------------"
oc exec $POD_BB2 -- ls -al $MOUNT_PATH/$LDIF_FILENAME
echo "----------------------------------------"
echo ""

echo "=== Script completed successfully ==="
echo ""
echo "Summary:"
echo "  ✓ PVC '$PVC_NAME' created and bound"
echo "  ✓ LDIF file copied to PVC via pod '$POD_BB1'"
echo "  ✓ Pod '$POD_BB1' deleted"
echo "  ✓ LDIF file verified in PVC via pod '$POD_BB2'"
echo ""
echo "Show file content:"
echo "  oc exec $POD_BB2 -- cat $MOUNT_PATH/$LDIF_FILENAME"
echo "Cleanup commands (run manually if needed):"
echo "  oc delete pod $POD_BB2"
echo "  oc delete pvc $PVC_NAME"
echo ""
