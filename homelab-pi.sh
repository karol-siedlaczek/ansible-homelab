#!/bin/bash

/usr/bin/ansible-playbook homelab-pi.yml -i hosts --vault-password-file ~/.ansible-pass
/usr/bin/ansible-playbook nagios.yml -i hosts --vault-password-file ~/.ansible-pass --limit homelab-pi
/usr/bin/ansible-playbook wireguard.yml -i hosts --vault-password-file ~/.ansible-pass --limit homelab-pi
/usr/bin/ansible-playbook snmp.yml -i hosts --vault-password-file ~/.ansible-pass --limit homelab-pi
/usr/bin/ansible-playbook node_exporter.yml -i hosts --vault-password-file ~/.ansible-pass --limit homelab-pi