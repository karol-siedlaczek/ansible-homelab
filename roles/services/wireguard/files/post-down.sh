#!/bin/bash

iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE