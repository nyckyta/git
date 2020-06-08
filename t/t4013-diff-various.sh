#!/bin/sh
#
# Copyright (c) 2006 Junio C Hamano
#

test_description='Various diff formatting options'

. ./test-lib.sh

test_expect_success setup '

	GIT_AUTHOR_DATE="2006-06-26 00:00:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:00:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&

	mkdir dir &&
	mkdir dir2 &&
	for i in 1 2 3; do echo $i; done >file0 &&
	for i in A B; do echo $i; done >dir/sub &&
	cat file0 >file2 &&
	git add file0 file2 dir/sub &&
	git commit -m Initial &&

	git branch initial &&
	git branch side &&

	GIT_AUTHOR_DATE="2006-06-26 00:01:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:01:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&

	for i in 4 5 6; do echo $i; done >>file0 &&
	for i in C D; do echo $i; done >>dir/sub &&
	rm -f file2 &&
	git update-index --remove file0 file2 dir/sub &&
	git commit -m "Second${LF}${LF}This is the second commit." &&

	GIT_AUTHOR_DATE="2006-06-26 00:02:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:02:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&

	for i in A B C; do echo $i; done >file1 &&
	git add file1 &&
	for i in E F; do echo $i; done >>dir/sub &&
	git update-index dir/sub &&
	git commit -m Third &&

	GIT_AUTHOR_DATE="2006-06-26 00:03:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:03:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&

	git checkout side &&
	for i in A B C; do echo $i; done >>file0 &&
	for i in 1 2; do echo $i; done >>dir/sub &&
	cat dir/sub >file3 &&
	git add file3 &&
	git update-index file0 dir/sub &&
	git commit -m Side &&

	GIT_AUTHOR_DATE="2006-06-26 00:04:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:04:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&

	git checkout default &&
	git pull -s ours . side &&

	GIT_AUTHOR_DATE="2006-06-26 00:05:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:05:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&

	for i in A B C; do echo $i; done >>file0 &&
	for i in 1 2; do echo $i; done >>dir/sub &&
	git update-index file0 dir/sub &&

	mkdir dir3 &&
	cp dir/sub dir3/sub &&
	test-tool chmtime +1 dir3/sub &&

	git config log.showroot false &&
	git commit --amend &&

	GIT_AUTHOR_DATE="2006-06-26 00:06:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:06:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&
	git checkout -b rearrange initial &&
	for i in B A; do echo $i; done >dir/sub &&
	git add dir/sub &&
	git commit -m "Rearranged lines in dir/sub" &&
	git checkout default &&

	GIT_AUTHOR_DATE="2006-06-26 00:06:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:06:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&
	git checkout -b mode initial &&
	git update-index --chmod=+x file0 &&
	git commit -m "update mode" &&
	git checkout -f default &&

	GIT_AUTHOR_DATE="2006-06-26 00:06:00 +0000" &&
	GIT_COMMITTER_DATE="2006-06-26 00:06:00 +0000" &&
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE &&
	git checkout -b note initial &&
	git update-index --chmod=+x file2 &&
	git commit -m "update mode (file2)" &&
	git notes add -m "note" &&
	git checkout -f default &&

	# Same merge as default, but with parents reversed. Hide it in a
	# pseudo-ref to avoid impacting tests with --all.
	commit=$(echo reverse |
		 git commit-tree -p default^2 -p default^1 default^{tree}) &&
	git update-ref REVERSE $commit &&

	git config diff.renames false &&

	git show-branch
'

: <<\EOF
! [initial] Initial
 * [default] Merge branch 'side'
  ! [rearrange] Rearranged lines in dir/sub
   ! [side] Side
----
  +  [rearrange] Rearranged lines in dir/sub
 -   [default] Merge branch 'side'
 * + [side] Side
 *   [default^] Third
 *   [default~2] Second
+*++ [initial] Initial
EOF

process_diffs () {
	_x04="[0-9a-f][0-9a-f][0-9a-f][0-9a-f]" &&
	_x07="$_x05[0-9a-f][0-9a-f]" &&
	sed -e "s/$OID_REGEX/$ZERO_OID/g" \
	    -e "s/From $_x40 /From $ZERO_OID /" \
	    -e "s/from $_x40)/from $ZERO_OID)/" \
	    -e "s/commit $_x40\$/commit $ZERO_OID/" \
	    -e "s/commit $_x40 (/commit $ZERO_OID (/" \
	    -e "s/$_x40 $_x40 $_x40/$ZERO_OID $ZERO_OID $ZERO_OID/" \
	    -e "s/$_x40 $_x40 /$ZERO_OID $ZERO_OID /" \
	    -e "s/^$_x40 $_x40$/$ZERO_OID $ZERO_OID/" \
	    -e "s/^$_x40 /$ZERO_OID /" \
	    -e "s/^$_x40$/$ZERO_OID/" \
	    -e "s/$_x07\.\.$_x07/fffffff..fffffff/g" \
	    -e "s/$_x07,$_x07\.\.$_x07/fffffff,fffffff..fffffff/g" \
	    -e "s/$_x07 $_x07 $_x07/fffffff fffffff fffffff/g" \
	    -e "s/$_x07 $_x07 /fffffff fffffff /g" \
	    -e "s/Merge: $_x07 $_x07/Merge: fffffff fffffff/g" \
	    -e "s/$_x07\.\.\./fffffff.../g" \
	    -e "s/ $_x04\.\.\./ ffff.../g" \
	    -e "s/ $_x04/ ffff/g" \
	    "$1"
}

V=$(git version | sed -e 's/^git version //' -e 's/\./\\./g')
while read magic cmd
do
	case "$magic" in
	'' | '#'*)
		continue ;;
	:*)
		magic=${magic#:}
		label="$magic-$cmd"
		case "$magic" in
		noellipses) ;;
		*)
			BUG "unknown magic $magic" ;;
		esac ;;
	*)
		cmd="$magic $cmd" magic=
		label="$cmd" ;;
	esac
	test=$(echo "$label" | sed -e 's|[/ ][/ ]*|_|g')
	pfx=$(printf "%04d" $test_count)
	expect="$TEST_DIRECTORY/t4013/diff.$test"
	actual="$pfx-diff.$test"

	test_expect_success "git $cmd # magic is ${magic:-(not used)}" '
		{
			echo "$ git $cmd"
			case "$magic" in
			"")
				GIT_PRINT_SHA1_ELLIPSIS=yes git $cmd ;;
			noellipses)
				git $cmd ;;
			esac |
			sed -e "s/^\\(-*\\)$V\\(-*\\)\$/\\1g-i-t--v-e-r-s-i-o-n\2/" \
			    -e "s/^\\(.*mixed; boundary=\"-*\\)$V\\(-*\\)\"\$/\\1g-i-t--v-e-r-s-i-o-n\2\"/"
			echo "\$"
		} >"$actual" &&
		if test -f "$expect"
		then
			process_diffs "$actual" >actual &&
			process_diffs "$expect" >expect &&
			case $cmd in
			*format-patch* | *-stat*)
				test_i18ncmp expect actual;;
			*)
				test_cmp expect actual;;
			esac &&
			rm -f "$actual" actual expect
		else
			# this is to help developing new tests.
			cp "$actual" "$expect"
			false
		fi
	'
done <<\EOF
diff-tree initial
diff-tree -r initial
diff-tree -r --abbrev initial
diff-tree -r --abbrev=4 initial
diff-tree --root initial
diff-tree --root --abbrev initial
:noellipses diff-tree --root --abbrev initial
diff-tree --root -r initial
diff-tree --root -r --abbrev initial
:noellipses diff-tree --root -r --abbrev initial
diff-tree --root -r --abbrev=4 initial
:noellipses diff-tree --root -r --abbrev=4 initial
diff-tree -p initial
diff-tree --root -p initial
diff-tree --patch-with-stat initial
diff-tree --root --patch-with-stat initial
diff-tree --patch-with-raw initial
diff-tree --root --patch-with-raw initial

diff-tree --pretty initial
diff-tree --pretty --root initial
diff-tree --pretty -p initial
diff-tree --pretty --stat initial
diff-tree --pretty --summary initial
diff-tree --pretty --stat --summary initial
diff-tree --pretty --root -p initial
diff-tree --pretty --root --stat initial
# improved by Timo's patch
diff-tree --pretty --root --summary initial
# improved by Timo's patch
diff-tree --pretty --root --summary -r initial
diff-tree --pretty --root --stat --summary initial
diff-tree --pretty --patch-with-stat initial
diff-tree --pretty --root --patch-with-stat initial
diff-tree --pretty --patch-with-raw initial
diff-tree --pretty --root --patch-with-raw initial

diff-tree --pretty=oneline initial
diff-tree --pretty=oneline --root initial
diff-tree --pretty=oneline -p initial
diff-tree --pretty=oneline --root -p initial
diff-tree --pretty=oneline --patch-with-stat initial
# improved by Timo's patch
diff-tree --pretty=oneline --root --patch-with-stat initial
diff-tree --pretty=oneline --patch-with-raw initial
diff-tree --pretty=oneline --root --patch-with-raw initial

diff-tree --pretty side
diff-tree --pretty -p side
diff-tree --pretty --patch-with-stat side

diff-tree initial mode
diff-tree --stat initial mode
diff-tree --summary initial mode

diff-tree default
diff-tree -p default
diff-tree -p -m default
diff-tree -c default
diff-tree -c --abbrev default
:noellipses diff-tree -c --abbrev default
diff-tree --cc default
# stat only should show the diffstat with the first parent
diff-tree -c --stat default
diff-tree --cc --stat default
diff-tree -c --stat --summary default
diff-tree --cc --stat --summary default
# stat summary should show the diffstat and summary with the first parent
diff-tree -c --stat --summary side
diff-tree --cc --stat --summary side
diff-tree --cc --shortstat default
diff-tree --cc --summary REVERSE
# improved by Timo's patch
diff-tree --cc --patch-with-stat default
# improved by Timo's patch
diff-tree --cc --patch-with-stat --summary default
# this is correct
diff-tree --cc --patch-with-stat --summary side

log default
log -p default
log --root default
log --root -p default
log --patch-with-stat default
log --root --patch-with-stat default
log --root --patch-with-stat --summary default
# improved by Timo's patch
log --root -c --patch-with-stat --summary default
# improved by Timo's patch
log --root --cc --patch-with-stat --summary default
log -p --first-parent default
log -m -p --first-parent default
log -m -p default
log -SF default
log -S F default
log -SF -p default
log -SF default --max-count=0
log -SF default --max-count=1
log -SF default --max-count=2
log -GF default
log -GF -p default
log -GF -p --pickaxe-all default
log --decorate --all
log --decorate=full --all

rev-list --parents HEAD
rev-list --children HEAD

whatchanged default
:noellipses whatchanged default
whatchanged -p default
whatchanged --root default
:noellipses whatchanged --root default
whatchanged --root -p default
whatchanged --patch-with-stat default
whatchanged --root --patch-with-stat default
whatchanged --root --patch-with-stat --summary default
# improved by Timo's patch
whatchanged --root -c --patch-with-stat --summary default
# improved by Timo's patch
whatchanged --root --cc --patch-with-stat --summary default
whatchanged -SF default
:noellipses whatchanged -SF default
whatchanged -SF -p default

log --patch-with-stat default -- dir/
whatchanged --patch-with-stat default -- dir/
log --patch-with-stat --summary default -- dir/
whatchanged --patch-with-stat --summary default -- dir/

show initial
show --root initial
show side
show default
show -c default
show -m default
show --first-parent default
show --stat side
show --stat --summary side
show --patch-with-stat side
show --patch-with-raw side
:noellipses show --patch-with-raw side
show --patch-with-stat --summary side

format-patch --stdout initial..side
format-patch --stdout initial..default^
format-patch --stdout initial..default
format-patch --stdout --no-numbered initial..default
format-patch --stdout --numbered initial..default
format-patch --attach --stdout initial..side
format-patch --attach --stdout --suffix=.diff initial..side
format-patch --attach --stdout initial..default^
format-patch --attach --stdout initial..default
format-patch --inline --stdout initial..side
format-patch --inline --stdout initial..default^
format-patch --inline --stdout --numbered-files initial..default
format-patch --inline --stdout initial..default
format-patch --inline --stdout --subject-prefix=TESTCASE initial..default
config format.subjectprefix DIFFERENT_PREFIX
format-patch --inline --stdout initial..default^^
format-patch --stdout --cover-letter -n initial..default^

diff --abbrev initial..side
diff -U initial..side
diff -U1 initial..side
diff -r initial..side
diff --stat initial..side
diff -r --stat initial..side
diff initial..side
diff --patch-with-stat initial..side
diff --patch-with-raw initial..side
:noellipses diff --patch-with-raw initial..side
diff --patch-with-stat -r initial..side
diff --patch-with-raw -r initial..side
:noellipses diff --patch-with-raw -r initial..side
diff --name-status dir2 dir
diff --no-index --name-status dir2 dir
diff --no-index --name-status -- dir2 dir
diff --no-index dir dir3
diff default default^ side
# Can't use spaces...
diff --line-prefix=abc default default^ side
diff --dirstat default~1 default~2
diff --dirstat initial rearrange
diff --dirstat-by-file initial rearrange
diff --dirstat --cc default~1 default
# No-index --abbrev and --no-abbrev
diff --raw initial
:noellipses diff --raw initial
diff --raw --abbrev=4 initial
:noellipses diff --raw --abbrev=4 initial
diff --raw --no-abbrev initial
diff --no-index --raw dir2 dir
:noellipses diff --no-index --raw dir2 dir
diff --no-index --raw --abbrev=4 dir2 dir
:noellipses diff --no-index --raw --abbrev=4 dir2 dir
diff --no-index --raw --no-abbrev dir2 dir

diff-tree --pretty --root --stat --compact-summary initial
diff-tree --pretty -R --root --stat --compact-summary initial
diff-tree --pretty note
diff-tree --pretty --notes note
diff-tree --format=%N note
diff-tree --stat --compact-summary initial mode
diff-tree -R --stat --compact-summary initial mode
EOF

test_expect_success 'log -S requires an argument' '
	test_must_fail git log -S
'

test_expect_success 'diff --cached on unborn branch' '
	echo ref: refs/heads/unborn >.git/HEAD &&
	git diff --cached >result &&
	process_diffs result >actual &&
	process_diffs "$TEST_DIRECTORY/t4013/diff.diff_--cached" >expected &&
	test_cmp expected actual
'

test_expect_success 'diff --cached -- file on unborn branch' '
	git diff --cached -- file0 >result &&
	process_diffs result >actual &&
	process_diffs "$TEST_DIRECTORY/t4013/diff.diff_--cached_--_file0" >expected &&
	test_cmp expected actual
'
test_expect_success 'diff --line-prefix with spaces' '
	git diff --line-prefix="| | | " --cached -- file0 >result &&
	process_diffs result >actual &&
	process_diffs "$TEST_DIRECTORY/t4013/diff.diff_--line-prefix_--cached_--_file0" >expected &&
	test_cmp expected actual
'

test_expect_success 'diff-tree --stdin with log formatting' '
	cat >expect <<-\EOF &&
	Side
	Third
	Second
	EOF
	git rev-list default | git diff-tree --stdin --format=%s -s >actual &&
	test_cmp expect actual
'

test_done
