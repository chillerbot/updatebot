#!/bin/bash

function err() {
	printf "[-] %s\n" "$1"
}

function log() {
	printf "[*] %s\n" "$1"
}

function check_remotes() {
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
	(
		cd ../chillerbot-ux || exit 1
		if check_remotes
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
	) || exit 1
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
	log "Sleeping 24 hours"
	sleep_hours 24
done

