import Testing

/// Every suite that makes pseudoterminal pairs, run one test at a time.
///
/// The kernel hands a freed pair's number to the very next pair anyone asks
/// for, and a port whose device went away retries its path every second. So a
/// test that closes its fake device leaves behind a port that opens whatever
/// pair the next test makes, and reads that test's bytes. On the CI runner,
/// where a test can start seconds after its neighbors, that failed two tests
/// at once on 2026-10-19: `deviceGoingAwayDropsTheConnection` found its port
/// open again with nothing to say, and `drainsRawBytesIndependently` saw
/// nothing arrive in five seconds. Run one at a time, every port a test opens
/// is closed before the next test makes a pair.
@Suite(.serialized) enum Pseudoterminals {}
