#!/bin/sh
cd `dirname $0`
cd app
go run . $@
