#!/bin/bash

ifconfig mvneta0 inet 192.168.100.200 netmask 255.255.255.0
route add default 192.168.100.1
