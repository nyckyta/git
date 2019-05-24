#include "test-tool.h"
#include "cache.h"
#include "split-index.h"
#include "ewah/ewok.h"

int cmd__dump_index(int ac, const char **av)
{
	int i;

	if (ac != 2)
		die("Need a path to a .git/index");

	do_read_index(&the_index, av[1], 1);
	printf("index version: %u\n", the_index.version);
	printf("timestamp: %u.%u\n",
	       the_index.timestamp.sec, the_index.timestamp.nsec);
	printf("#entries: %u\n", the_index.cache_nr);
	for (i = 0; i < the_index.cache_nr; i++) {
		struct cache_entry *ce = the_index.cache[i];
		printf("#%d mode: %06o hash: %s stage: %d flags: %u "
		       "ctime %u.%u mtime %u.%u dev: %u ino: %u uid: %u "
		       "gid: %u size: %u name: %s\n", i, ce->ce_mode,
		       oid_to_hex(&ce->oid), ce_stage(ce), ce->ce_flags,
		       ce->ce_stat_data.sd_ctime.sec,
		       ce->ce_stat_data.sd_ctime.nsec,
		       ce->ce_stat_data.sd_mtime.sec,
		       ce->ce_stat_data.sd_mtime.nsec,
		       ce->ce_stat_data.sd_dev, ce->ce_stat_data.sd_ino,
		       ce->ce_stat_data.sd_uid, ce->ce_stat_data.sd_gid,
		       ce->ce_stat_data.sd_size, ce->name);
	}

	printf("\n");
	printf("hash of index: %s\n", oid_to_hex(&the_index.oid));
	if (the_index.cache_tree)
		printf("has cache_tree\n");
	if (the_index.resolve_undo)
		printf("has resolve_undo\n");
	if (the_index.untracked)
		printf("has untracked\n");
	if (the_index.fsmonitor_dirty)
		printf("has fsmonitor\n");

	return 0;
}
