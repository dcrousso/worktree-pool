# bash completion for the wt worktree pool
#
# source this from your ~/.bashrc:
#     source ~/Developer/worktrees/.pool/bin/wt-completion.bash
#
# it completes subcommands, flags, and (for release/remove/build/path) the live
# pooled worktree names and the branches checked out in them, so you can do
# `wt release <TAB>` and pick a worktree or branch without typing it out
#
# it targets macOS system bash (3.2), so it avoids the bash-completion helper library

_wt_pool_root() {
	printf '%s' "${WT_POOL_ROOT:-$HOME/Developer/worktrees}"
}

# print every pooled worktree name, one per line
_wt_names() {
	local root d
	root="$(_wt_pool_root)"
	for d in "$root"/*-*; do
		[ -d "$d" ] || continue
		printf '%s\n' "${d##*/}"
	done
}

# print the branch checked out in each pooled worktree, one per line
_wt_branches() {
	local root d b
	root="$(_wt_pool_root)"
	for d in "$root"/*-*; do
		[ -d "$d" ] || continue
		b="$(git -C "$d" branch --show-current 2>/dev/null)"
		if [ -n "$b" ]; then
			printf '%s\n' "$b"
		fi
	done
}

_wt() {
	local cur prev sub flags i seen_ddash
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD-1]}"
	sub="${COMP_WORDS[1]}"

	# the first word is the subcommand
	if [ "$COMP_CWORD" -eq 1 ]; then
		COMPREPLY=( $(compgen -W "claim release build status migrate remove path help" -- "$cur") )
		return 0
	fi

	# for build, everything after a lone -- is the command, so hand off to default completion
	if [ "$sub" = "build" ]; then
		seen_ddash=0
		i=2
		while [ "$i" -lt "$COMP_CWORD" ]; do
			if [ "${COMP_WORDS[$i]}" = "--" ]; then
				seen_ddash=1
			fi
			i=$(( i + 1 ))
		done
		if [ "$seen_ddash" -eq 1 ]; then
			return 0
		fi
	fi

	# complete an option when the current word starts with a dash
	case "$cur" in
		-*)
			flags=""
			case "$sub" in
				claim)   flags="--repo --base --branch --note --refresh" ;;
				release) flags="--repo --base --all --force --delete-branch --worktree --branch" ;;
				remove)  flags="--repo --all --force --dry-run --worktree --branch" ;;
				build)   flags="--worktree --branch --" ;;
				status)  flags="--disk --mine" ;;
				path)    flags="--repo --worktree --branch" ;;
				migrate) flags="--dry-run" ;;
			esac
			COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
			return 0
			;;
	esac

	# complete the value expected after a value-taking option
	case "$prev" in
		--branch)
			COMPREPLY=( $(compgen -W "$(_wt_branches)" -- "$cur") )
			return 0
			;;
		--worktree)
			COMPREPLY=( $(compgen -W "$(_wt_names)" -- "$cur") )
			return 0
			;;
		--repo)
			COMPREPLY=( $(compgen -d -- "$cur") )
			return 0
			;;
		--base|--note)
			return 0
			;;
	esac

	# a bare positional target: a worktree name or a checked-out branch
	case "$sub" in
		release|remove|path|build)
			COMPREPLY=( $(compgen -W "$(_wt_names; _wt_branches)" -- "$cur") )
			;;
		claim)
			COMPREPLY=( $(compgen -W "$(_wt_branches)" -- "$cur") )
			;;
	esac
	return 0
}
complete -F _wt wt
