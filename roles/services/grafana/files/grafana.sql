CREATE DATABASE grafana;

CREATE USER `grafana_user`@`<host>` IDENTIFIED BY '<some_pass>';
GRANT USAGE ON *.* TO `grafana_user`@`<host>`;
GRANT ALL PRIVILEGES ON `grafana`.* TO `grafana_user`@`<host>`;