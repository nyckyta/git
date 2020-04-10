#!/bin/sh
#
# Copyright (c) 2020 Google LLC
#

test_description='reftable basics'

. ./test-lib.sh

test_expect_success 'basic operation of reftable storage' '
	rm -rf .git &&
	git init --ref-storage=reftable &&
	mv .git/hooks .git/hooks-disabled &&
	test_commit file &&
	test_write_lines HEAD refs/heads/master refs/tags/file >expect &&
	git show-ref &&
	git show-ref | cut -f2 -d" " > actual &&
	test_cmp actual expect &&
	for count in $(test_seq 1 10)
	do
		test_commit "number $count" file.t $count number-$count ||
		return 1
	done &&
	git gc &&
	ls -1 .git/reftable >table-files &&
	test_line_count = 2 table-files &&
	git reflog refs/heads/master >output &&
	test_line_count = 11 output &&
	grep "commit (initial): first post" output &&
	grep "commit: number 10" output
'

test_done
