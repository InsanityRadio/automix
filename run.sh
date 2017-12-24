#!/bin/bash
cd "$(dirname "$0")"
while [ true ]; do
	bundle exec ruby select.rb
	sleep 5
done
