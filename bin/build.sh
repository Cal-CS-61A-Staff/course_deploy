#!/bin/bash

set -euo pipefail

main() {
	test "$#" -eq 5 || { 1>&2 echo "Invalid number of arguments passed." && return 1; }

	local make_args=(--no-print-directory -C src)
	local buildtype="$1" branch="$2" output="$3" prtmp="$4" buildloc="$5"

	# Make sure pdflatex is accessible
	local TEXLIVE_PATH="/usr/local/texlive/2017"
	export PATH="${TEXLIVE_PATH}/bin/x86_64-linux:${PATH}"
	#export INFOPATH="${TEXLIVE_PATH}/texmf-dist/doc/info:${INFOPATH}"
	#export MANPATH="${TEXLIVE_PATH}/texmf-dist/doc/man:${MANPATH}"

	set -x

	git fetch    -q --prune origin "${branch}"
	git clean    -q -d -f -x
	git checkout -q    -f --detach origin/"${branch}"
	git clean    -q -d -f -x

	make "${make_args[@]}"     all  # NO, please do NOT attempt to simplify these lines via a loop, 'if', '&&', '||', etc.
	make "${make_args[@]}"     all  # Turns out Bash "helpefully" ignores set -e in many compound statements and keeps going, making the script claim success.
	make "${make_args[@]}" -j1 all  # Proof: try executing the following: (set -ex; false && false; echo "you probably do not expect this output")

	rm -r -f -- "${prtmp}"
	if [ -d "${output}" ]; then  # Don't move if it doesn't exist for some reason
		mv -T -- "${output}" "${prtmp}" || true  # Can still fail due to a race condition, but ultimately this doesn't matter; what matters is that the output is updated
	fi
	mv -T -- "${buildloc}" "${output}"
}

main "$@"
