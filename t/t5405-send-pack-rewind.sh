#!/bin/sh

test_description='forced push to replace commit we do not have'

. ./test-lib.sh

test_expect_success setup '

	>file1 && git add file1 && test_tick &&
	git commit -m Initial &&
	git config receive.denyCurrentBranch warn &&

	mkdir another && (
		cd another &&
		git init &&
		git fetch --update-head-ok .. default:default
	) &&

	>file2 && git add file2 && test_tick &&
	git commit -m Second

'

test_expect_success 'non forced push should die not segfault' '

	(
		cd another &&
		test_must_fail git push .. default:default
	)

'

test_expect_success 'forced push should succeed' '

	(
		cd another &&
		git push .. +default:default
	)

'

test_done
