#!/bin/sh
#
# Copyright (c) 2007 Junio C Hamano

test_description='git checkout to switch between branches with symlink<->dir'

. ./test-lib.sh

test_expect_success setup '

	mkdir frotz &&
	echo hello >frotz/filfre &&
	git add frotz/filfre &&
	test_tick &&
	git commit -m "default has file frotz/filfre" &&

	git branch side &&

	echo goodbye >nitfol &&
	git add nitfol &&
	test_tick &&
	git commit -m "default adds file nitfol" &&

	git checkout side &&

	git rm --cached frotz/filfre &&
	mv frotz xyzzy &&
	test_ln_s_add xyzzy frotz &&
	git add xyzzy/filfre &&
	test_tick &&
	git commit -m "side moves frotz/ to xyzzy/ and adds frotz->xyzzy/"

'

test_expect_success 'switch from symlink to dir' '

	git checkout default

'

test_expect_success 'Remove temporary directories & switch to default' '
	rm -fr frotz xyzzy nitfol &&
	git checkout -f default
'

test_expect_success 'switch from dir to symlink' '

	git checkout side

'

test_done
