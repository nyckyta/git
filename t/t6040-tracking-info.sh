#!/bin/sh

test_description='remote tracking stats'

. ./test-lib.sh

advance () {
	echo "$1" >"$1" &&
	git add "$1" &&
	test_tick &&
	git commit -m "$1"
}

test_expect_success setup '
	advance a &&
	advance b &&
	advance c &&
	git clone . test &&
	(
		cd test &&
		git checkout -b b1 origin &&
		git reset --hard HEAD^ &&
		advance d &&
		git checkout -b b2 origin &&
		git reset --hard b1 &&
		git checkout -b b3 origin &&
		git reset --hard HEAD^ &&
		git checkout -b b4 origin &&
		advance e &&
		advance f &&
		git checkout -b brokenbase origin &&
		git checkout -b b5 --track brokenbase &&
		advance g &&
		git branch -d brokenbase &&
		git checkout -b b6 origin
	) &&
	git checkout -b follower --track default &&
	advance h
'

t6040_script='s/^..\(b.\) *[0-9a-f]* \(.*\)$/\1 \2/p'
cat >expect <<\EOF
b1 [ahead 1, behind 1] d
b2 [ahead 1, behind 1] d
b3 [behind 1] b
b4 [ahead 2] f
b5 [gone] g
b6 c
EOF

test_expect_success 'branch -v' '
	(
		cd test &&
		git branch -v
	) |
	sed -n -e "$t6040_script" >actual &&
	test_i18ncmp expect actual
'

cat >expect <<\EOF
b1 [origin/default: ahead 1, behind 1] d
b2 [origin/default: ahead 1, behind 1] d
b3 [origin/default: behind 1] b
b4 [origin/default: ahead 2] f
b5 [brokenbase: gone] g
b6 [origin/default] c
EOF

test_expect_success 'branch -vv' '
	(
		cd test &&
		git branch -vv
	) |
	sed -n -e "$t6040_script" >actual &&
	test_i18ncmp expect actual
'

test_expect_success 'checkout (diverged from upstream)' '
	(
		cd test && git checkout b1
	) >actual &&
	test_i18ngrep "have 1 and 1 different" actual
'

test_expect_success 'checkout with local tracked branch' '
	git checkout default &&
	git checkout follower >actual &&
	test_i18ngrep "is ahead of" actual
'

test_expect_success 'checkout (upstream is gone)' '
	(
		cd test &&
		git checkout b5
	) >actual &&
	test_i18ngrep "is based on .*, but the upstream is gone." actual
'

test_expect_success 'checkout (up-to-date with upstream)' '
	(
		cd test && git checkout b6
	) >actual &&
	test_i18ngrep "Your branch is up to date with .origin/default" actual
'

test_expect_success 'status (diverged from upstream)' '
	(
		cd test &&
		git checkout b1 >/dev/null &&
		# reports nothing to commit
		test_must_fail git commit --dry-run
	) >actual &&
	test_i18ngrep "have 1 and 1 different" actual
'

test_expect_success 'status (upstream is gone)' '
	(
		cd test &&
		git checkout b5 >/dev/null &&
		# reports nothing to commit
		test_must_fail git commit --dry-run
	) >actual &&
	test_i18ngrep "is based on .*, but the upstream is gone." actual
'

test_expect_success 'status (up-to-date with upstream)' '
	(
		cd test &&
		git checkout b6 >/dev/null &&
		# reports nothing to commit
		test_must_fail git commit --dry-run
	) >actual &&
	test_i18ngrep "Your branch is up to date with .origin/default" actual
'

cat >expect <<\EOF
## b1...origin/default [ahead 1, behind 1]
EOF

test_expect_success 'status -s -b (diverged from upstream)' '
	(
		cd test &&
		git checkout b1 >/dev/null &&
		git status -s -b | head -1
	) >actual &&
	test_i18ncmp expect actual
'

cat >expect <<\EOF
## b1...origin/default [different]
EOF

test_expect_success 'status -s -b --no-ahead-behind (diverged from upstream)' '
	(
		cd test &&
		git checkout b1 >/dev/null &&
		git status -s -b --no-ahead-behind | head -1
	) >actual &&
	test_i18ncmp expect actual
'

cat >expect <<\EOF
## b1...origin/default [different]
EOF

test_expect_success 'status.aheadbehind=false status -s -b (diverged from upstream)' '
	(
		cd test &&
		git checkout b1 >/dev/null &&
		git -c status.aheadbehind=false status -s -b | head -1
	) >actual &&
	test_i18ncmp expect actual
'

cat >expect <<\EOF
On branch b1
Your branch and 'origin/default' have diverged,
and have 1 and 1 different commits each, respectively.
EOF

test_expect_success 'status --long --branch' '
	(
		cd test &&
		git checkout b1 >/dev/null &&
		git status --long -b | head -3
	) >actual &&
	test_i18ncmp expect actual
'

test_expect_success 'status --long --branch' '
	(
		cd test &&
		git checkout b1 >/dev/null &&
		git -c status.aheadbehind=true status --long -b | head -3
	) >actual &&
	test_i18ncmp expect actual
'

cat >expect <<\EOF
On branch b1
Your branch and 'origin/default' refer to different commits.
EOF

test_expect_success 'status --long --branch --no-ahead-behind' '
	(
		cd test &&
		git checkout b1 >/dev/null &&
		git status --long -b --no-ahead-behind | head -2
	) >actual &&
	test_i18ncmp expect actual
'

test_expect_success 'status.aheadbehind=false status --long --branch' '
	(
		cd test &&
		git checkout b1 >/dev/null &&
		git -c status.aheadbehind=false status --long -b | head -2
	) >actual &&
	test_i18ncmp expect actual
'

cat >expect <<\EOF
## b5...brokenbase [gone]
EOF

test_expect_success 'status -s -b (upstream is gone)' '
	(
		cd test &&
		git checkout b5 >/dev/null &&
		git status -s -b | head -1
	) >actual &&
	test_i18ncmp expect actual
'

cat >expect <<\EOF
## b6...origin/default
EOF

test_expect_success 'status -s -b (up-to-date with upstream)' '
	(
		cd test &&
		git checkout b6 >/dev/null &&
		git status -s -b | head -1
	) >actual &&
	test_i18ncmp expect actual
'

test_expect_success 'fail to track lightweight tags' '
	git checkout default &&
	git tag light &&
	test_must_fail git branch --track lighttrack light >actual &&
	test_i18ngrep ! "set up to track" actual &&
	test_must_fail git checkout lighttrack
'

test_expect_success 'fail to track annotated tags' '
	git checkout default &&
	git tag -m heavy heavy &&
	test_must_fail git branch --track heavytrack heavy >actual &&
	test_i18ngrep ! "set up to track" actual &&
	test_must_fail git checkout heavytrack
'

test_expect_success '--set-upstream-to does not change branch' '
	git branch from-default default &&
	git branch --set-upstream-to default from-default &&
	git branch from-master2 default &&
	test_must_fail git config branch.from-master2.merge > actual &&
	git rev-list from-master2 &&
	git update-ref refs/heads/from-master2 from-master2^ &&
	git rev-parse from-master2 >expect2 &&
	git branch --set-upstream-to default from-master2 &&
	git config branch.from-default.merge > actual &&
	git rev-parse from-master2 >actual2 &&
	grep -q "^refs/heads/default$" actual &&
	cmp expect2 actual2
'

test_expect_success '--set-upstream-to @{-1}' '
	git checkout follower &&
	git checkout from-master2 &&
	git config branch.from-master2.merge > expect2 &&
	git branch --set-upstream-to @{-1} from-default &&
	git config branch.from-default.merge > actual &&
	git config branch.from-master2.merge > actual2 &&
	git branch --set-upstream-to follower from-default &&
	git config branch.from-default.merge > expect &&
	test_cmp expect2 actual2 &&
	test_cmp expect actual
'

test_done
