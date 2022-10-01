#!/bin/sh
status=11
while test $status -eq 11
do
  bin/lua lha.lua $@
  status=$?
done
exit $status
