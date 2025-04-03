# cp4ba-idp-ldap

Utilities for IBM Cloud Pak® for Business Automation

<i>Last update: 2025-04-03</i>

This repository contains a series of examples and tools for creating and configuring a containerized LDAP server and configuring federated IDP in a IBM Cloud Pak deployed using Foundational services v4.x

## Change Log

2025-03-08: Fixed createIDPConfiguration (ldap_groupidmap)
2024-01-29: Changed 'sed -i' command for compatibility with Darwin platform

<b>**WARNING**</b>:

++++++++++++++++++++++++++++++++++++++++++++++++
<br>
<i>
This software and the configurations contained in the repository MUST be considered as examples for educational purposes.
<br>
An LDAP deployed within the cluster is used, the OpenLDAP image is provided by the IBM registry 'cp.icr.io'.
<br>
Do not use in a production environment without making your own necessary modifications.
</i>
<br>
++++++++++++++++++++++++++++++++++++++++++++++++


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
LDAP_WAIT_SECS=10

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
LDAP_GROUPFILTER="(&(cn=%v)(|(objectclass=groupOfNames)(objectclass=groupOfUniqueNames)(objectclass=groupOfURLs)))"
LDAP_USERIDMAP="*:uid"
LDAP_GROUPIDMAP="*:cn"
LDAP_GROUPMEMBERIDMAP="memberof:member"

# SCIM attributes
LDAP_PAGINGSEARCH="false"
LDAP_NESTEDSEARCH="false"
LDAP_PAGING_SIZE="1000" 

```


## LDAP installation and configuration commands


<b>WARNING</b>: before run any command please update configuration files with your values


```
# install openldap deployment and wait for pod ready
./scripts/add-ldap.sh -p ./configs/_cfg1-ldap-domain.properties

./scripts/add-ldap.sh -p ./configs/_cfg-production-ldap-domain.properties

# [optional] install phpadmin tool, use TLS cert from secret 'icp4adeploy-root-ca' in namespace 'cp4ba'

./scripts/add-phpadmin.sh -p ./configs/_cfg1-ldap-domain.properties -s common-web-ui-cert -w common-web-ui-cert -n cp4ba

./scripts/add-phpadmin.sh -p ./configs/_cfg-production-ldap-domain.properties -s common-web-ui-cert -w common-web-ui-cert -n cp4ba-federated-wfps

# NO ./scripts/add-phpadmin.sh -p ./configs/_cfg1-ldap-domain.properties -s icp4adeploy-root-ca -w common-web-ui-cert -n cp4ba

```

## IDP installation and configuration commands
Remember to restart the BAW server to also see the "Groups" carried by the new IDP.
```
./scripts/add-idp.sh -p ./configs/_cfg1-idp.properties
```

## Users onboarding into Pak environment commands
```
# add users (list from ldif secret)
./scripts/onboard-users.sh -p ./configs/_cfg1-ldap-domain.properties -o add -s

# add users (list from file)
./scripts/onboard-users.sh -p ./configs/_cfg1-ldap-domain.properties -o add -u ../configs/file-of-users


# remove users from ldif secret
./scripts/onboard-users.sh -p ./configs/_cfg1-ldap-domain.properties -o remove -s

# remove users from users file
./scripts/onboard-users.sh -p ./configs/_cfg1-ldap-domain.properties -o remove -u ../configs/file-of-users
```

## List Roles and Groups

```
./scripts/onboard-users.sh -p ./configs/_cfg1-ldap-domain.properties -r
```

## LDAP deletion commands
```
# remove phpadmin tool
./scripts/remove-phpadmin.sh -p ./configs/_cfg1-ldap-domain.properties

# remove openldap deployment
./scripts/remove-ldap.sh -p ./configs/_cfg1-ldap-domain.properties

```

## IDP deletion commands
```
./scripts/remove-idp.sh -p ./configs/_cfg1-idp.properties
```

## References

[IDP provider and LDAP configuration in IBM Cloud Pak foundational services 4.2](https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.2?topic=apis-identity-provider#ldap-configuring)

[Identity Provider APIs 4.3](https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.3?topic=apis-identity-provider)
