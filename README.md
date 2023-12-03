# cp4ba-idp-ldap

Utilities for LDAP and IDP configuration in Cloud Pak with Foundational services v4.x

## Contents

Folders

<b>configs</b> folder contains .properties and .ldif files used for configuration procedures

<b>scripts</b> folder contains .sh bash scripts


## Configuration files

### For LDAP configuration 

Use a .properties file with the following variables
```
# target namespace (use your own)
TNS=cp4ba

# LDAP vars (domain name, domain extension, full domain string, path to .ldif file)
LDAP_DOMAIN=domain1
LDAP_DOMAIN_EXT=net
LDAP_FULL_DOMAIN="dc=${LDAP_DOMAIN},dc=${LDAP_DOMAIN_EXT}"
LDAP_LDIF_NAME="./configs/_cfg1-ldap-domain.ldif"

# wait check interval
WAIT_SECS=10

# Cloud Pak entitlement key (export CP4BA_AUTO_ENTITLEMENT_KEY in your shell before run the installation script)
ENTITLEMENT_KEY=${CP4BA_AUTO_ENTITLEMENT_KEY}
```


### For IDP configuration 

Use a .properties file with the following variables
```
# target namespace (use your own)
TNS=cp4ba

# IDP name (in Pak 'Access Control' console)
IDP_NAME=domain1

# LDAP vars (domain name, domain extension, full domain string, path to .ldif file)

# Full URL of LDAP service
LDAP_URL="ldap://"${IDP_NAME}"-ldap."${TNS}".svc.cluster.local:389"
LDAP_HOST=${IDP_NAME}"-ldap."${TNS}".svc.cluster.local"
LDAP_PORT=389
LDAP_PROTOCOL="ldap"
                 
# LDAP base DN
LDAP_BASEDN="dc=${IDP_NAME},dc=net"

# LDAP admin user
LDAP_BINDDN="cn=admin,${LDAP_BASEDN}"

# Password must be base64 value, use echo "passw0rd" -n | base64, eg: passw0rd --> cGFzc3cwcmQ=
LDAP_BINDPASSWORD="..."

# OpenLDAP type values (change values as needed)
LDAP_TYPE="Custom"
LDAP_USERFILTER="(&(cn=%v)(objectclass=person))" 
LDAP_GROUPFILTER="(&(cn=%v)(objectclass=groupOfNames))"
LDAP_USERIDMAP="*:uid"
LDAP_GROUPIDMAP="*:cn"
LDAP_GROUPMEMBERIDMAP="memberof:member"

# SCIM attributes
LDAP_PAGINGSEARCH="false"
LDAP_NESTEDSEARCH="false"
LDAP_PAGING_SIZE="1000" 

```


## LDAP installation and configuration
```
# install openldap deployment and wait for pod ready
./scripts/add-ldap.sh -p ./configs/_cfg1-ldap-domain.properties

# install phpadmin tool, use TLS cert from secret 'icp4adeploy-root-ca' in namespace 'cp4ba'
./scripts/add-phpadmin.sh -p ./configs/_cfg1-ldap-domain.properties -s icp4adeploy-root-ca -w common-web-ui-cert -n cp4ba

```

## IDP installation and configuration
```
./scripts/add-idp.sh -p ./configs/_cfg1-idp.properties -f
```


## LDAP deletion
```
# remove phpadmin tool
./scripts/remove-phpadmin.sh -p ./configs/_cfg1-ldap-domain.properties

# remove openldap deployment
./scripts/remove-ldap.sh -p ./configs/_cfg1-ldap-domain.properties

```

## IDP deletion
```
./scripts/remove-idp.sh -p ./configs/_cfg1-idp.properties -f
```

