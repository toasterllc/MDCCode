#!/bin/bash
while true ; do
    line=$(ssh -p 2222 127.0.0.1 'read line </dev/ttyACM0 ; echo $line')
    say "$line"
done
