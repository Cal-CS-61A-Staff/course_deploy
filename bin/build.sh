#!/bin/bash

set -euo pipefail

main() {
	test "$#" -eq 5 || { 1>&2 echo "Invalid number of arguments passed." && return 1; }

	local make_args=(--no-print-directory -C src)

	# Make sure pdflatex is accessible
	local TEXLIVE_PATH="/usr/local/texlive/2017"
	export PATH="${TEXLIVE_PATH}/bin/x86_64-linux:${PATH}"
	#export INFOPATH="${TEXLIVE_PATH}/texmf-dist/doc/info:${INFOPATH}"
	#export MANPATH="${TEXLIVE_PATH}/texmf-dist/doc/man:${MANPATH}"

	set -x

	git fetch    -q --prune origin "$2"
	git clean    -q -d -f -x
	git checkout -q    -f --detach origin/"$2"
	git clean    -q -d -f -x

	make "${make_args[@]}" all && make "${make_args[@]}" all && make "${make_args[@]}" -j1 all

	rm -r -f -- "$4"
	mv -T -- "$3" "$4"
	mv -T -- "$5" "$3"
}

main "$@"
