#!/bin/sh
echo "--------------------------------------"
echo "Derrubando wlan..."
echo "--------------------------------------"
ifdown wlan0
echo "--------------------------------------"
echo "Aguardando um pouco..."
sleep 2
echo "Subindo wlan..."
echo "--------------------------------------"
ifup wlan0
