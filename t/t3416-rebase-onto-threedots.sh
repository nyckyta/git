#!/bin/sh

test_description='git rebase --onto A...B'

. ./test-lib.sh
. "$TEST_DIRECTORY/lib-rebase.sh"

# Rebase only the tip commit of "topic" on merge base between "default"
# and "topic".  Cannot do this for "side" with "default" because there
# is no single merge base.
#
#
#	    F---G topic                             G'
#	   /                                       /
# A---B---C---D---E default      -->       A---B---C---D---E
#      \   \ /
#	\   x
#	 \ / \
#	  H---I---J---K side

test_expect_success setup '
	test_commit A &&
	test_commit B &&
	git branch side &&
	test_commit C &&
	git branch topic &&
	git checkout side &&
	test_commit H &&
	git checkout default &&
	test_tick &&
	git merge H &&
	git tag D &&
	test_commit E &&
	git checkout topic &&
	test_commit F &&
	test_commit G &&
	git checkout side &&
	test_tick &&
	git merge C &&
	git tag I &&
	test_commit J &&
	test_commit K
'

test_expect_success 'rebase --onto default...topic' '
	git reset --hard &&
	git checkout topic &&
	git reset --hard G &&

	git rebase --onto default...topic F &&
	git rev-parse HEAD^1 >actual &&
	git rev-parse C^0 >expect &&
	test_cmp expect actual
'

test_expect_success 'rebase --onto default...' '
	git reset --hard &&
	git checkout topic &&
	git reset --hard G &&

	git rebase --onto default... F &&
	git rev-parse HEAD^1 >actual &&
	git rev-parse C^0 >expect &&
	test_cmp expect actual
'

test_expect_success 'rebase --onto default...side' '
	git reset --hard &&
	git checkout side &&
	git reset --hard K &&

	test_must_fail git rebase --onto default...side J
'

test_expect_success 'rebase -i --onto default...topic' '
	git reset --hard &&
	git checkout topic &&
	git reset --hard G &&
	set_fake_editor &&
	EXPECT_COUNT=1 git rebase -i --onto default...topic F &&
	git rev-parse HEAD^1 >actual &&
	git rev-parse C^0 >expect &&
	test_cmp expect actual
'

test_expect_success 'rebase -i --onto default...' '
	git reset --hard &&
	git checkout topic &&
	git reset --hard G &&
	set_fake_editor &&
	EXPECT_COUNT=1 git rebase -i --onto default... F &&
	git rev-parse HEAD^1 >actual &&
	git rev-parse C^0 >expect &&
	test_cmp expect actual
'

test_expect_success 'rebase -i --onto default...side' '
	git reset --hard &&
	git checkout side &&
	git reset --hard K &&

	set_fake_editor &&
	test_must_fail git rebase -i --onto default...side J
'

test_expect_success 'rebase --keep-base --onto incompatible' '
	test_must_fail git rebase --keep-base --onto default...
'

test_expect_success 'rebase --keep-base --root incompatible' '
	test_must_fail git rebase --keep-base --root
'

test_expect_success 'rebase --keep-base default from topic' '
	git reset --hard &&
	git checkout topic &&
	git reset --hard G &&

	git rebase --keep-base default &&
	git rev-parse C >base.expect &&
	git merge-base default HEAD >base.actual &&
	test_cmp base.expect base.actual &&

	git rev-parse HEAD~2 >actual &&
	git rev-parse C^0 >expect &&
	test_cmp expect actual
'

test_expect_success 'rebase --keep-base default from side' '
	git reset --hard &&
	git checkout side &&
	git reset --hard K &&

	test_must_fail git rebase --keep-base default
'

test_expect_success 'rebase -i --keep-base default from topic' '
	git reset --hard &&
	git checkout topic &&
	git reset --hard G &&

	set_fake_editor &&
	EXPECT_COUNT=2 git rebase -i --keep-base default &&
	git rev-parse C >base.expect &&
	git merge-base default HEAD >base.actual &&
	test_cmp base.expect base.actual &&

	git rev-parse HEAD~2 >actual &&
	git rev-parse C^0 >expect &&
	test_cmp expect actual
'

test_expect_success 'rebase -i --keep-base default from side' '
	git reset --hard &&
	git checkout side &&
	git reset --hard K &&

	set_fake_editor &&
	test_must_fail git rebase -i --keep-base default
'

test_done
