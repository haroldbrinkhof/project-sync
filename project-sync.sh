#!/bin/bash

PROJECT_DIRECTORY="$HOME/.project-sync";
DATA_FILE="${PROJECT_DIRECTORY}/snapshot-data";
DATA_FILE_TARGET="${PROJECT_DIRECTORY}/snapshot-data.tmp";
CURRENT_DIRECTORY=`pwd`;
RETVAL="";

# expects a string containing the error message to be passed, exits with error condition 1
error(){
	echo "$1";
	exit 1;
}

# expects no arguments, creates the necessary files and initiates a repository in the data folder
init(){
	if [[ ! -d "$PROJECT_DIRECTORY" ]]; then	
		mkdir $PROJECT_DIRECTORY &&
		cd $PROJECT_DIRECTORY &&
		git init ./ &&
		printf '%s' '{ "groups": [], "snapshots": [] }' > $DATA_FILE &&
		git add $DATA_FILE &&
		git commit -m "initial commit";
	fi
}

# expects no arguments, completely erases the data folder
expunge(){
	if [[ -d "$PROJECT_DIRECTORY" ]]; then	
		rm -rf "$PROJECT_DIRECTORY"
	fi
}

# expects groupname as argument 1, 
# for every repository except the current one registered to said groupname:
# checks out the branch/hash for the last snapshot registered,
# identified by the current branch + current directory + groupname
checkout-snapshot(){
	find-repo-on-current-path-or-above || error "no .git repository folder found on this path or in the directories above: $CURRENT_DIRECTORY"	
	CURRENT_REPO_PATH="$RETVAL";
	CURRENT_BRANCH=`git branch --show-current`;
	jq-get-last-snapshot "$1" "$CURRENT_BRANCH";
	readarray -t repos = < <(jq -c ".repositories[] | [.hash, .branch, .path]" <<<$RETVAL);
	for rep in "${repos[@]}";
	do
	
		REPO_HASH=`jq -r ".[0]" <<< "$rep" | tr -d '[:space:]'`;
		REPO_BRANCH=`jq -r ".[1]" <<< "$rep" | tr -d '[:space:]'`;
		REPO_PATH=`jq -r ".[2]" <<< "$rep" | tr -d '[:space:]'`;
		if jq-groups-contain "$1" && jq-repositories-contain "$1" "$CURRENT_REPO_PATH" && [[ "$CURRENT_BRANCH" != "$REPO_BRANCH" && "$REPO_PATH" != "$CURRENT_REPO_PATH" ]]; then
			cd "$REPO_PATH";
			[[ "$REPO_BRANCH" != "" ]] && git checkout "$REPO_BRANCH" > /dev/null;
			CURRENT_HASH=`git log --pretty='format:%H ' -1`;
			if [[ "$CURRENT_HASH" != "$REPO_HASH" ]]; then
				git checkout "$REPO_HASH" > /dev/null;
			fi

		fi
	done
	cd "$CURRENT_DIRECTORY";
}

# expects groupname as argument 1, adds groupname to data file if not yet there
# adds current repository to data file as belonging to groupname
add-project-group-and-repository(){
	find-repo-on-current-path-or-above || error "no .git repository folder found on this path or in the directories above: $CURRENT_DIRECTORY"	
	
	if ! jq-groups-contain "$1"; then
		echo "adding group $1"
		jq-add-group "$1";
	fi

	if ! jq-repositories-contain "$1" "$RETVAL"; then
		echo "adding repo $RETVAL"
		jq-add-repository "$1" "$RETVAL";
	fi

}

# expects groupname passed as argument 1, repository path passed as argument 2
# removes repository from group
remove-repository(){
	jq-groups-contain "$1" || error "group $1 does not exit"
	jq-repositories-contain "$1" "$2" || error "repository $2 does not exist on group $1"
	jq-remove-repository "$1" "$2"
}

# expects groupname as argument 1
# removes group and any repositories that might reside under it
remove-group(){
	jq-groups-contain "$1" || error "group $1 does not exit"
	jq-remove-group "$1"
}

# expects groupname as argument 1, branch as argument 2
# returns the last snapshot recorded for this group, filtered to having this branch
jq-get-last-snapshot(){
	RETVAL=`jq -c "[[.snapshots[] | select(.group == \"$1\")] | .[] | select(.repositories | select(any(.branch == \"$2\")))] | sort_by(.when) | last" "$DATA_FILE"`;
}

# expects groupname as argument 1
# adds group to data file
jq-add-group(){
	jq ".groups |= . + [{\"name\":\"$1\",\"repositories\":[]}]" "$DATA_FILE" > "$DATA_FILE_TARGET";
	sync;
	mv "$DATA_FILE_TARGET" "$DATA_FILE";
}

# expects groupname as argument 1
# returns whether group exists in data file
jq-groups-contain(){
	jq -e ".groups | any(.name == \"$1\")" "$DATA_FILE" >/dev/null;
	return $?;
}

# expects groupname as argument 1, repository path as argument 2
# returns whether group exists and has repository assigned to it in data file
jq-repositories-contain(){
	jq -e ".groups[] | select(.name == \"$1\") | .repositories | any( . == \"$2\")" "$DATA_FILE" >/dev/null;
	return $?;
}

# expects groupname as argument 1, repository path as argument 2
# add repository to group in data file
jq-add-repository(){
	jq ".groups |= map(select(.name == \"$1\") |= {\"name\":.name, \"repositories\": (.repositories + [\"$2\"])} )" "$DATA_FILE" > "$DATA_FILE_TARGET";
	sync;
	mv "$DATA_FILE_TARGET" "$DATA_FILE";
}

# expects groupname as argument 1, repository path as argument 2
# remove repository from group in data file
jq-remove-repository(){
	jq ".groups |= map(select(.name == \"$1\") |= del(.repositories[] | select(. == \"$2\")))" "$DATA_FILE" > "$DATA_FILE_TARGET";
	sync;
	mv "$DATA_FILE_TARGET" "$DATA_FILE";
}

# expects groupname as argument 1
# remove group from data file
jq-remove-group(){
	jq ".groups |= map(del(select(.name == \"$1\")))" "$DATA_FILE" > "$DATA_FILE_TARGET";
	sync;
	mv "$DATA_FILE_TARGET" "$DATA_FILE";
}

# expects groupname as argument 1
# returns list of repository paths assigned to single group
jq-list-repositories(){
readarray -t RETVAL < <(jq -c ".groups[] | select(.name == \"$1\") | .repositories[]" "$DATA_FILE")
}


# expects groupname as argument 1
# add snapshot (git checkout state ) of all repositories belonging to group to data file
jq-add-snapshot(){
	CUR_DIR=`pwd`;
	REPOSITORY_LINES="";
	
	jq-list-repositories "$1";

	if [[ "${#RETVAL[@]}" -gt 0 ]]; then
		for i in "${RETVAL[@]}"
		do
			TARGET=`echo "$i" | sed 's/["\r\n]//g'`;
			cd "$TARGET";
			HASH=`git log --pretty='format:%H ' -1`;
			BRANCH=`git branch --show-current`;

			INTERIM="$INTERIM {\"path\":\"$TARGET\",\"hash\":\"$HASH\", \"branch\":\"$BRANCH\"},"
		done
		
		INTERIM=`echo "$INTERIM" | sed 's/,$//'`;
		WHEN=`date --iso-8601='seconds'`
		FINAL="{\"when\":\"$WHEN\", \"group\":\"$1\", \"repositories\":[$INTERIM] }";
		jq ".snapshots |= . + [$FINAL]" "$DATA_FILE" > "$DATA_FILE_TARGET";
		sync;
		mv "$DATA_FILE_TARGET" "$DATA_FILE";

		cd "$PROJECT_DIRECTORY";
		git add "$DATA_FILE" > /dev/null;
		git commit -m "snapshot: group $1" > /dev/null;
	fi

	cd "$CUR_DIR";

}

# expects no arguments to be passed
# returns the directory where a .git directory resides (the current one or above, closer towards /)
find-repo-on-current-path-or-above(){
	PREVIOUS=`pwd`;
	OUTCOME=1;
	if [[ -d ".git" ]]; then
		RETVAL=`pwd`;
		OUTCOME=0;
	else
		cd ..;
		if [[ `pwd` != "$PREVIOUS" ]]; then
			find-repo-on-current-path-or-above;
		else
			OUTCOME=1;
			RETVAL="";
		fi
	fi

	cd "$PREVIOUS";
	return $OUTCOME;
}

if [[ "$#" -eq 0 || "$1" == "help" || "$1" == "--help" ]]; then
	echo "";
	echo "usage:";
	echo "------";
	echo "$0 <command> [<argument>..]";
	echo "";
	echo "commands:";
	echo "---------";
	echo "init: install data folder";
	echo "expunge: remove data folder";
	echo "add-project-group <groupname>: add current repository to group";
	echo "remove-repository <groupname> <repository path>: remove repository from group";
	echo "remove-group <groupname>: remove group (and repositories linked to t)";
	echo "list-repositories <groupname>: list repositories linked to group";
	echo "add-snapshot <groupname>: save git state snapshot of all repositories linked to group";
	echo "checkout-snapshot <groupname>: checkout the git state found in last snapshot for the repositories other than this current one and based on current one."
	echo "help: displays this command overview (as does --help or no command at all)";
	exit;
fi

if [[ "$1" = "init" ]]; then
	init;
fi

if [[ "$1" = "expunge" ]]; then
	expunge;
	cd "$CURRENT_DIRECTORY";
	exit 0;
fi

if [[ "$1" = "add-project-group" ]]; then
	add-project-group-and-repository "$2";
fi

if [[ "$1" = "remove-repository" ]]; then
	remove-repository "$2" "$3";
fi

if [[ "$1" = "remove-group" ]]; then
	remove-group "$2";
fi

if [[ "$1" = "list-repositories" ]]; then
	jq-list-repositories "$2";
	for repo in "${RETVAL[@]}";
	do
		echo "$repo" | sed 's/"//g';
	done
fi

if [[ "$1" = "add-snapshot" ]]; then
	jq-add-snapshot "$2";
fi

if [[ "$1" = "checkout-snapshot" ]]; then
	checkout-snapshot "$2";
fi

if jq-groups-contain "$2" && [[ ! -z "$(git status --untracked-files=no --porcelain)" ]]; then 
	cd "$PROJECT_DIRECTORY";
	git commit -a -m "changes to group $2" > /dev/null;
fi


cd "$CURRENT_DIRECTORY"



