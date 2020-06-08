#!/bin/sh

test_description='Test reflog interaction with detached HEAD'
. ./test-lib.sh

reset_state () {
	git checkout default &&
	cp saved_reflog .git/logs/HEAD
}

test_expect_success setup '
	test_tick &&
	git commit --allow-empty -m initial &&
	git branch side &&
	test_tick &&
	git commit --allow-empty -m second &&
	cat .git/logs/HEAD >saved_reflog
'

test_expect_success baseline '
	reset_state &&
	git rev-parse default default^ >expect &&
	git log -g --format=%H >actual &&
	test_cmp expect actual
'

test_expect_success 'switch to branch' '
	reset_state &&
	git rev-parse side default default^ >expect &&
	git checkout side &&
	git log -g --format=%H >actual &&
	test_cmp expect actual
'

test_expect_success 'detach to other' '
	reset_state &&
	git rev-parse default side default default^ >expect &&
	git checkout side &&
	git checkout default^0 &&
	git log -g --format=%H >actual &&
	test_cmp expect actual
'

test_expect_success 'detach to self' '
	reset_state &&
	git rev-parse default default default^ >expect &&
	git checkout default^0 &&
	git log -g --format=%H >actual &&
	test_cmp expect actual
'

test_expect_success 'attach to self' '
	reset_state &&
	git rev-parse default default default default^ >expect &&
	git checkout default^0 &&
	git checkout default &&
	git log -g --format=%H >actual &&
	test_cmp expect actual
'

test_expect_success 'attach to other' '
	reset_state &&
	git rev-parse side default default default^ >expect &&
	git checkout default^0 &&
	git checkout side &&
	git log -g --format=%H >actual &&
	test_cmp expect actual
'

test_done
