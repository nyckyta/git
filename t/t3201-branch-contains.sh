#!/bin/sh

test_description='branch --contains <commit>, --no-contains <commit> --merged, and --no-merged'

. ./test-lib.sh

test_expect_success setup '

	>file &&
	git add file &&
	test_tick &&
	git commit -m initial &&
	git branch side &&

	echo 1 >file &&
	test_tick &&
	git commit -a -m "second on default" &&

	git checkout side &&
	echo 1 >file &&
	test_tick &&
	git commit -a -m "second on side" &&

	git merge default

'

test_expect_success 'branch --contains=default' '

	git branch --contains=default >actual &&
	{
		echo "  default" && echo "* side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --contains default' '

	git branch --contains default >actual &&
	{
		echo "  default" && echo "* side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --no-contains=default' '

	git branch --no-contains=default >actual &&
	test_must_be_empty actual

'

test_expect_success 'branch --no-contains default' '

	git branch --no-contains default >actual &&
	test_must_be_empty actual

'

test_expect_success 'branch --contains=side' '

	git branch --contains=side >actual &&
	{
		echo "* side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --no-contains=side' '

	git branch --no-contains=side >actual &&
	{
		echo "  default"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --contains with pattern implies --list' '

	git branch --contains=default default >actual &&
	{
		echo "  default"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --no-contains with pattern implies --list' '

	git branch --no-contains=default default >actual &&
	test_must_be_empty actual

'

test_expect_success 'side: branch --merged' '

	git branch --merged >actual &&
	{
		echo "  default" &&
		echo "* side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --merged with pattern implies --list' '

	git branch --merged=side default >actual &&
	{
		echo "  default"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'side: branch --no-merged' '

	git branch --no-merged >actual &&
	test_must_be_empty actual

'

test_expect_success 'default: branch --merged' '

	git checkout default &&
	git branch --merged >actual &&
	{
		echo "* default"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'default: branch --no-merged' '

	git branch --no-merged >actual &&
	{
		echo "  side"
	} >expect &&
	test_cmp expect actual

'

test_expect_success 'branch --no-merged with pattern implies --list' '

	git branch --no-merged=default default >actual &&
	test_must_be_empty actual

'

test_expect_success 'implicit --list conflicts with modification options' '

	test_must_fail git branch --contains=default -d &&
	test_must_fail git branch --contains=default -m foo &&
	test_must_fail git branch --no-contains=default -d &&
	test_must_fail git branch --no-contains=default -m foo

'

test_expect_success 'Assert that --contains only works on commits, not trees & blobs' '
	test_must_fail git branch --contains default^{tree} &&
	blob=$(git hash-object -w --stdin <<-\EOF
	Some blob
	EOF
	) &&
	test_must_fail git branch --contains $blob &&
	test_must_fail git branch --no-contains $blob
'

# We want to set up a case where the walk for the tracking info
# of one branch crosses the tip of another branch (and make sure
# that the latter walk does not mess up our flag to see if it was
# merged).
#
# Here "topic" tracks "default" with one extra commit, and "zzz" points to the
# same tip as default The name "zzz" must come alphabetically after "topic"
# as we process them in that order.
test_expect_success 'branch --merged with --verbose' '
	git branch --track topic default &&
	git branch zzz topic &&
	git checkout topic &&
	test_commit foo &&
	git branch --merged topic >actual &&
	cat >expect <<-\EOF &&
	  default
	* topic
	  zzz
	EOF
	test_cmp expect actual &&
	git branch --verbose --merged topic >actual &&
	cat >expect <<-EOF &&
	  default $(git rev-parse --short default) second on default
	* topic   $(git rev-parse --short topic ) [ahead 1] foo
	  zzz     $(git rev-parse --short zzz   ) second on default
	EOF
	test_i18ncmp expect actual
'

test_expect_success 'branch --contains combined with --no-contains' '
	git branch --contains zzz --no-contains topic >actual &&
	cat >expect <<-\EOF &&
	  default
	  side
	  zzz
	EOF
	test_cmp expect actual

'

test_done
