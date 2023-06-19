#!/bin/bash

/usr/bin/ansible-playbook homelab-pi.yml -i hosts --ask-vault-pass
/usr/bin/ansible-playbook nagios.yml -i hosts --ask-vault-pass --limit homelab-pi
/usr/bin/ansible-playbook snmp.yml -i hosts --ask-vault-pass --limit homelab-pi
/usr/bin/ansible-playbook node_exporter.yml -i hosts --ask-vault-pass --limit homelab-pi