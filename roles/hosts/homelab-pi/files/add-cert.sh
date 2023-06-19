#!/bin/bash

echo "Creating temp rule in iptables..."
iptables -A INPUT  -p tcp -m multiport --dports 80,443 -m comment --comment "certbot-tmp-http-rule" -j ACCEPT
certbot certonly --apache
echo "Deleting temp rule from iptables..."
iptables -D INPUT  -p tcp -m multiport --dports 80,443 -m comment --comment "certbot-tmp-http-rule" -j ACCEPT