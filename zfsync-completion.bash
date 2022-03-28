# bash completion
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
# `compgen -W "word list" -- $2` will split word list and fister matches for $2

_zfsync() {
	if [ "${COMP_CWORD}" -eq 1 ]; then
		COMPREPLY=( $(compgen -W "snapshot mirror backup server list destroy recover configuser allowsend allowreceive" -- "$2"))
	else
		case "${COMP_WORDS[1]}" in
			'snapshot')
				if [ "${COMP_CWORD}" -eq 2 ]; then
					COMPREPLY=( $(compgen -W "-r -d $(zfs list -Ho name)" -- "$2" ) )
				elif [ "${COMP_CWORD}" -eq 3 ] && [ "$3" = "-d" ]; then
					COMPREPLY=() # need to input an argument for depth
				else
					COMPREPLY=( $(compgen -W "$(zfs list -Ho name)" -- "$2" ) )
				fi
				;;
			'mirror')
				COMPREPLY=(mirrorarg)
				;;
			'backup')
				COMPREPLY=(backuparg)
				;;
			'server')
				COMPREPLY=(serverarg)
				;;
			'list')
				COMPREPLY=(listarg)
				;;
			'destroy')
				COMPREPLY=(destroyarg)
				;;
			'recover')
				COMPREPLY=(recoverarg)
				;;
			'configuser')
				COMPREPLY=(configuserarg)
				;;
			'allowsend')
				COMPREPLY=(allowsendarg)
				;;
			'allowreceive')
				COMPREPLY=(allowreceivearg)
				;;
		esac
	fi
}