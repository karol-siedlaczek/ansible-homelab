#!/bin/bash

iptables -t nat -I POSTROUTING -o eth0 -j MASQUERADE