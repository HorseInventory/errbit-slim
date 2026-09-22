# Notice retention deployment

Notices retain full details for the latest 100 occurrences of each Problem. Older
occurrences keep their message, fingerprint, Problem, and timestamps so counts,
matching, and occurrence history remain available.

Before enabling requests on the release that introduces `Notice.compressed`, run:

```sh
bundle exec rake errbit:prepare_notice_retention
```

The task identifies already compressed occurrences by their empty
`server_environment`, sets the compression flag on existing records, clears their
backtrace references, removes backtraces only when no occurrence references them,
and creates the notice indexes. It does not delete occurrences or change counts.

New occurrences start with `compressed: false`. Cleanup queries that indexed set,
keeps its newest 100 records, and compresses the excess. Ordering uses the timestamp
and ID so occurrences with the same timestamp have a stable order.
