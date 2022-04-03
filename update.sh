#!/bin/bash

arg_loop=0
arg_no_clang_tidy=0
arg_no_build=0

function err() {
	printf "[-] %s\n" "$1"
}

function wrn() {
	printf "[!] %s\n" "$1"
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

function gh_ddnet_prs() {
	gh pr list -L512 -R ddnet/ddnet | awk '{ print $1 }'
}

function merge_pull_error() {
	echo "Failed to merge https://github.com/ddnet/ddnet/pull/$pull into chillerbot"
	echo ''
	echo '```'
	echo '$ git status'
	git status
	echo '```'
	echo ''
	echo 'Conflicts:'
	# maybe using this is better and simpler
	# git --no-pager diff
	local conflict
	for conflict in $(git status | grep 'both modified:' | awk '{print $3}')
	do
		printf '```'
		if [[ "$conflict" == *".c" ]] || [[ "$conflict" == *".h" ]]
		then
			printf 'cpp'
		elif [[ "$conflict" == *".py" ]]
		then
			printf 'python'
		fi
		echo ''
		echo "$conflict"
		grep -C 10 -F '<<<<<<< HEAD' "$conflict"
		echo '```'
		echo ''
	done
}

function check_ddnet_prs() {
	local pull
	for pull in $(gh_ddnet_prs)
	do
		set -x
		git branch updatebot-test-pull-ddnet
		git branch updatebot-test-pull-chillerbot
		git checkout updatebot-test-pull-ddnet || return 0
		git fetch ddnet || return 0
		git reset --hard ddnet/master || return 0
		# if this fails its conflicing from pull to ddnet/master already so skip it
		# yea not too sure about that
		# git pull ddnet pull/"$pull"/head || { git rebase --abort || return 0; continue; }
		git checkout chillerbot || return 0
		git branch -D updatebot-test-pull-ddnet || return 0
		git fetch ddnet pull/"$pull"/head:updatebot-test-pull-ddnet || return 0
		git checkout updatebot-test-pull-chillerbot || return 0
		git reset --hard origin/chillerbot || return 0
		set +x
		git merge updatebot-test-pull-ddnet --commit --no-edit || \
			{
				wrn "Warning: pull $pull failed to merge";
				if [ "$(gh issue list --search "ddnet/pulls/$pull" -R chillerbot/chillerbot-ux)" == "" ];
				then
					notify_conflict \
						"$(merge_pull_error "$pull")" \
						"Merge conflict with ddnet/pulls/$pull";
				fi;
				git merge --abort;
				git checkout chillerbot;
			}
	done
	return 1
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
	# args:
	#  issue_body
	#  [issue_title] (default: "Merge conflict with ddnet")
	if [ ! -x "$(command -v gh)" ]
	then
		err "Error: please install gh (github-cli)"
		return
	fi
	local msg="$1"
	local title="${2:-'Merge conflict with ddnet'}"
	gh issue create \
		--title "$title" \
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
	if [ -d build ] && [ "$arg_no_build" == "0" ]
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
	if [ -d build ] && [ "$arg_no_build" == "0" ]
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
	if [ -d clang-tidy ] && [ "$arg_no_clang_tidy" == "0" ]
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
	# if check_ddnet_prs
	# then
	# 	err "Error: something went wrong while testing pullrequests"
	# 	exit 1
	# fi
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

function update_all() {
	update_ux
	if update_zx
	then
		err "Error: updating chillerbot-zx failed"
		exit 1
	fi
}

function update_loop() {
	while true
	do
		git pull
		update_all
		log "Sleeping 24 hours"
		sleep_hours 24
	done
}

function show_help() {
	cat <<-EOF
	usage: $(basename "$0") [OPTION]"
	options:
	  --help|-h		shows this help page
	  --loop|-l		keeps running and updates every 24 hours
	  --no-clang-tidy 	skip clang tidy build
	  --no-build 		skip normal build test
	EOF
}

for arg in "$@"
do
	if [ "$arg" == "-h" ] || [ "$arg" == "--help" ]
	then
		show_help
		exit 0
	elif [ "$arg" == "-l" ] || [ "$arg" == "--loop" ]
	then
		arg_loop=1
	elif [ "$arg" == "--no-clang-tidy" ]
	then
		arg_no_clang_tidy=1
	elif [ "$arg" == "--no-build" ]
	then
		arg_no_build=1
	else
		err "Error: unkown argument '$arg' see '--help'"
		exit 1
	fi
done

if [ "$arg_loop" == "1" ]
then
	update_loop
else
	update_all
fi

