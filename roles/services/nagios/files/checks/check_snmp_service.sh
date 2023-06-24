#!/bin/bash

SYSTEMCTL_LIST_OID=".1.3.6.1.2.1.25.4.2.1.2"
NAGIOS_OK=0
NAGIOS_WARN=1
NAGIOS_CRIT=2
NAGIOS_UNKNOWN=3
EXIT_CODE=$NAGIOS_CRIT
SNMP_PORT="161"
AUTH_PROTOCOL="SHA"
PRIV_PROTOCOL="AES"

function HELP {
  echo "DESCRIPTION"
  echo -e "Check available memory and SWAP usage on remote host via SNMP v3 using extend script called 'meminfo'"\\n
  echo "USAGE"
  echo "  -H=HOSTNAME           Remote host address"
  echo "  -l=SNMP_USER          SNMP v3 authentication user"
  echo "  -X=SNMP_PASSWORD        SNMP v3 authentication passphrase and encryption passphrase"
  echo "  -p=SNMP_PORT          SNMP port, default is $SNMP_PORT"
  echo "  -a=AUTH_PROTOCOL      Authentication protocol, default is (MD5|SHA, default: $AUTH_PROTOCOL)"
  echo "  -x=PRIV_PROTOCOL      Priv protocol, default is (AES|DES, default: $PRIV_PROTOCOL)"
  echo "  -s=SERVICE_NAME       Service name"
  echo "  -h                    Show this help message and exit"
  exit 1
}

while getopts H:l:X:p:a:x:s:h flag
do
  case "${flag}" in
    H) HOST_ADDRESS=${OPTARG};;
    l) SNMP_USER=${OPTARG};;
    X) SNMP_PASSWORD=${OPTARG};;
    p) SNMP_PORT=${OPTARG};;
    a) AUTH_PROTOCOL=${OPTARG};;
    x) PRIV_PROTOCOL=${OPTARG};;
    s) SERVICE_NAME=${OPTARG};;
    *) HELP;;
  esac
done

walk_output=$(snmpwalk -v 3 -u ${SNMP_USER} -X ${SNMP_PASSWORD} -A ${SNMP_PASSWORD} -x ${PRIV_PROTOCOL} -a ${AUTH_PROTOCOL} -l authPriv ${HOST_ADDRESS}:${SNMP_PORT} ${SYSTEMCTL_LIST_OID} | grep -i ${SERVICE_NAME} | wc -l)

if [ $walk_output -eq 0 ]
then
	MSG="CRITICAL: ${SERVICE_NAME} service is not running!"
	EXIT_CODE=2
elif [ $walk_output -ge 1 ]
then
	MSG="OK: ${SERVICE_NAME} service is running (${walk_output} processes)"
	EXIT_CODE=0
else
	MSG="UNKNOWN: state of ${SERVICE_NAME} service is unknown. ${walk_output}"
	EXIT_CODE=3
fi

echo $MSG
exit $EXIT_CODE