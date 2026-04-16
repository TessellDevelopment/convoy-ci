#!/usr/bin/env bash

function set_env(){
	set -a
	source .env
	set +a
}

function run(){
	set_env
	echo ${1}
    go run ${1}
}

function run_hot(){
	set_env
	npx nodemon \
	--watch "./internal/**" \
	--watch "./cmd/**" \
	--watch "./pkg/**" \
	--ext "go,json" \
	--signal SIGTERM \
	--exec "go run ${1}"
}

function test_formatting(){
	test -z $(gofmt -l .)
}

$*
