# bash completion for `zfsync` utility

# functions that start with "__zfs_" are defined by the base `zfs`
# bash completions script (so this script won't work without that one which
# should be provided by the base zfs installation)

# the following are some references for writing bash completion scripts
# https://julienharbulot.com/bash-completion.html
# https://julienharbulot.com/bash-completion-tutorial.html
# https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html

# $1 = command name
# $2 = current word being completed
# $3 = word before the word being completed
# COMP_WORDS: an array of all the words typed after the name of the program the compspec belongs to
# COMP_CWORD: the index of the word the cursor was when the tab key was pressed
# COMP_LINE: the current command line
# COMPREPLY: the variable to store completion candidates
# `compgen -W "word list" -- $cur` will split word list and filter matches for $cur

__zfsync() {
	prev="$3"
	cur="$2"
	if [ "${COMP_CWORD}" -eq 1 ]; then
		COMPREPLY=($(compgen -W "-? snapshot mirror backup server list prune rprune destroy recover configuser allowsend allowreceive version" -- "$cur"))
	else
		case "${COMP_WORDS[1]}" in
			'snapshot'|'prune')
				case "${prev}" in
					-d)
						COMPREPLY=($(compgen -W "" -- "$cur"));;
					*)
						if ! __zfs_complete_switch "r,d"; then
							COMPREPLY=($(compgen -W "$(__zfs_list_datasets)" -- "$cur"))
						fi
						;;
				esac
				;;
			'mirror'|'backup'|'rprune')
				if [ "${COMP_CWORD}" -eq 2 ]; then
					COMPREPLY=($(compgen -W "localhost $([ -f "$HOME/.ssh/config" ] && grep -P "^Host ([^*]+)$" "$HOME/.ssh/config" | sed 's/Host //')" -- "$cur"))
				else
					case "${prev}" in
						-d)
							COMPREPLY=($(compgen -W "" -- "$cur"));;
						*)
							if ! __zfs_complete_switch "r,d"; then
								COMPREPLY=($(compgen -W "$(__zfs_list_datasets)" -- "$cur"))
							fi
							;;
					esac
				fi
				;;
			'server')
				if [ "${COMP_CWORD}" -eq 2 ]; then
					COMPREPLY=($(compgen -W "$(__zfs_list_datasets)" -- "$cur"))
				fi
				;;
			'list')
				if [ "${COMP_CWORD}" -eq 2 ]; then
					COMPREPLY=($(compgen -W "localhost $([ -f "$HOME/.ssh/config" ] && grep -P "^Host ([^*]+)$" "$HOME/.ssh/config" | sed 's/Host //')" -- "$cur"))
				else
					case "${prev}" in
						-*d)
							COMPREPLY=($(compgen -W "" -- "$cur"));;
						-*t)
							__zfs_complete_multiple_options "filesystem volume snapshot all" "$cur";;
						-*o)
							__zfs_complete_multiple_options "$(__zfs_get_properties)" "$cur";;
						-*s|-*S)
							COMPREPLY=($(compgen -W "$(__zfs_get_properties)" -- "$cur"));;
						*)
							if ! __zfs_complete_switch "H,r,d,o,t,s,S"; then
								COMPREPLY=($(compgen -W "$(__zfs_match_explicit_snapshot) $(__zfs_list_datasets)" -- "$cur"))
							fi
							;;
					esac
				fi
				;;
			'destroy')
				if [ "${COMP_CWORD}" -eq 2 ]; then
					COMPREPLY=( $(compgen -W "localhost $([ -f "$HOME/.ssh/config" ] && grep -P "^Host ([^*]+)$" "$HOME/.ssh/config" | sed 's/Host //')" -- "$cur") )
				elif ! __zfs_complete_switch "d,f,n,p,R,r,v"; then
					__zfs_complete_multiple_options "$(__zfs_match_explicit_snapshot) $(__zfs_list_datasets)" $cur
				fi
				;;
			'recover')
				if [ "${COMP_CWORD}" -eq 2 ]; then
					COMPREPLY=( $(compgen -W "localhost $([ -f "$HOME/.ssh/config" ] && grep -P "^Host ([^*]+)$" "$HOME/.ssh/config" | sed 's/Host //')" -- "$cur") )
				elif ! __zfs_complete_switch "d,n,P,p,R,v,i,I"; then
					COMPREPLY=($(compgen -W "$(__zfs_match_snapshot)" -- "$cur"))
				fi
				;;
			'configuser')
				case "${COMP_CWORD}" in
					2)
						COMPREPLY=($(compgen -A user -- "$cur"));;
					3)
						compopt -o nospace # don't add space after directory completion
						COMPREPLY=($(compgen -d -S / -- "$cur"));;
				esac
				;;
			'allowsend')
				case "${COMP_CWORD}" in
					2)
						COMPREPLY=($(compgen -W "$(__zfs_list_datasets)" -- "$cur"));;
					3)
						COMPREPLY=($(compgen -A user -- "$cur"));;
				esac
				;;
			'allowreceive')
				case "${COMP_CWORD}" in
					2)
						COMPREPLY=($(compgen -W "$(__zfs_list_datasets)" -- "$cur"));;
					3)
						COMPREPLY=($(compgen -W "" -- "$cur"));;
					4)
						COMPREPLY=($(compgen -W "none" -- "$cur"));;
					5)
						COMPREPLY=($(compgen -A user -- "$cur"));;
				esac
				;;
		esac
	fi
}
complete -F __zfsync zfsync
