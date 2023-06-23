#!/bin/bash

/usr/bin/ansible-playbook snmp.yml -i hosts --vault-password-file ~/.ansible-pass --limit vps-01
/usr/bin/ansible-playbook grafana.yml -i hosts --vault-password-file ~/.ansible-pass --limit vps-01
/usr/bin/ansible-playbook influx.yml -i hosts --vault-password-file ~/.ansible-pass --limit vps-01
/usr/bin/ansible-playbook node_exporter.yml -i hosts --vault-password-file ~/.ansible-pass --limit vps-01
/usr/bin/ansible-playbook postgres-exporter.yml -i hosts --vault-password-file ~/.ansible-pass --limit vps-01
/usr/bin/ansible-playbook mysql-exporter.yml -i hosts --vault-password-file ~/.ansible-pass--limit vps-01