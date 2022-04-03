#!/bin/bash

function err() {
	printf "[-] %s\n" "$1"
}

function log() {
	printf "[*] %s\n" "$1"
}

function get_cores() {
	if [ -x "$(command -v nproc)" ]
	then
		nproc
	else
		echo 1
	fi
}

function check_remotes_ux() {
	if ! git remote -v | grep -q origin
	then
		err "Error: no remote called origin"
		return 0
	fi
	if ! git remote -v | grep -q ddnet
	then
		err "Error: no remote called ddnet"
		return 0
	fi
	local ddnet_remote
	ddnet_remote="$(git remote -v | grep -E '^ddnet[[:space:]]' | awk '{ print $2 }' | tail -n1)"
	if [ "$ddnet_remote" != "https://github.com/ddnet/ddnet" ]
	then
		err "Error: invalid ddnet remote '$ddnet_remote'"
		return 0
	fi
	return 1
}

function notify_conflict() {
	if [ ! -x "$(command -v gh)" ]
	then
		err "Error: please install gh (github-cli)"
		return
	fi
	local msg="$1"
	gh issue create \
		--title "Merge conflict with ddnet" \
		--body "$msg" \
		--repo "chillerbot/chillerbot-ux"
}

function update_zx() {
	if [ ! -d ../chillerbot-zx ]
	then
		err "Error: directory not found ../chillerbot-zx"
		return
	fi
	if [ ! -d ../chillerbot-zx/.git ]
	then
		err "Error: ../chillerbot-zx is not a git repo"
		return
	fi
	log "updating chillerbot-zx .."
	pushd  ../chillerbot-zx || return 0
	if ! git remote -v | grep -q chillerbot-zx
	then
		echo "not chillerbot-zx remote"
		return 0
	fi
	if ! git remote -v | grep -q origin
	then
		err "Error: no remote called origin"
		return 0
	fi
	if ! git remote -v | grep -q ux
	then
		err "Error: no remote called ux"
		return 0
	fi
	local ux_remote
	ux_remote="$(git remote -v | grep -E '^ux[[:space:]]' | awk '{ print $2 }' | tail -n1)"
	if [ "$ux_remote" != "git@github.com:chillerbot/chillerbot-ux.git" ]
	then
		err "Error: invalid ux remote '$ddnet_remote'"
		return 0
	fi
	git fetch ux || return 0
	git checkout ux || return 0
	git reset --hard ux/chillerbot || return 0
	git submodule update || return 0
	git push || return 0
	git checkout zx || return 0
	git merge ux --commit --no-edit || return 0
	git submodule update || return 0
	if [ -d build ]
	then
		pushd build || return 0
		make -j"$(get_cores)" || return 0
		popd || return 0
	fi
	git push || return 0
	popd || return 0
	return 1
}

function update_ux() {
	if [ ! -d ../chillerbot-ux ]
	then
		err "Error: directory not found ../chillerbot-ux"
		return
	fi
	if [ ! -d ../chillerbot-ux/.git ]
	then
		err "Error: ../chillerbot-ux is not a git repo"
		return
	fi
	log "updating chillerbot-ux .."
	pushd ../chillerbot-ux || exit 1
	if check_remotes_ux
	then
		exit 1
	fi
	if [ "$(git status | tail -n1)" != "nothing to commit, working tree clean" ]
	then
		err "Error: working tree no clean"
		exit 1
	fi
	git pull || { err "Error: git pull failed"; exit 1; }
	git push || { err "Error: git push failed"; exit 1; }
	git fetch ddnet || { err "Error: git fetch failed"; exit 1; }
	git checkout master || { err "Error: git checkout failed"; exit 1; }
	git pull || { err "Error: git pull failed"; exit 1; }
	git push || { err "Error: git push failed"; exit 1; }
	git reset --hard ddnet/master || { err "Error: git reset failed"; exit 1; }
	git push || { err "Error: git push failed"; exit 1; }
	git checkout chillerbot || { err "Error: git checkout failed"; exit 1; }
	git pull || { err "Error: git pull failed"; exit 1; }
	git push || { err "Error: git push failed"; exit 1; }
	git merge master --commit --no-edit || \
		{
			err "Error: git merge failed";
			notify_conflict "merge with upstream/master failed";
			exit 1;
		}
	if [ -d build ]
	then
		pushd build || exit 1
		make -j"$(get_cores)" || \
			{
				err "Error: build failed";
				notify_conflict "build failed after merge";
				exit 1;
			}
		popd || exit 1
	fi
	if [ -d clang-tidy ]
	then
		pushd clang-tidy || exit 1
		cmake --build . --config Debug --target everything -- -k 0 || \
			{
				err "Error: clang-tidy failed";
				notify_conflict "clang-tidy failed after merge";
				exit 1;
			}
		popd || exit 1
	fi
	popd || exit 1
}


function sleep_hours() {
	local i
	local hours=$1
	for ((i=0;i<hours;i++))
	do
		sleep 1h
		printf .
	done
	echo ""
}

while true
do
	update_ux
	if update_zx
	then
		err "Error: updating chillerbot-zx failed"
		exit 1
	fi
	log "Sleeping 24 hours"
	sleep_hours 24
done

