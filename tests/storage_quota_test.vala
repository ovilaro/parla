private void assert_quota (string report, int64 used, int64 limit) {
    var quota = Dc.StorageQuota.parse_connectivity_report (report);
    assert (quota.available);
    assert (quota.used_bytes == used);
    assert (quota.limit_bytes == limit);
}

private void test_plain_report () {
    assert_quota (
        "Quota: 5 MiB of 20 MiB used",
        (int64) 5 * 1024 * 1024,
        (int64) 20 * 1024 * 1024);
}

private void test_html_report () {
    assert_quota (
        "<p>Server quota</p><strong>12.5&nbsp;MiB</strong> of <span>100 MiB</span> used",
        (int64) (12.5 * 1024.0 * 1024.0),
        (int64) 100 * 1024 * 1024);
}

private void test_decimal_comma_report () {
    assert_quota (
        "<td>1,5 GiB</td><td>of</td><td>2 GiB used</td>",
        (int64) (1.5 * 1024.0 * 1024.0 * 1024.0),
        (int64) 2 * 1024 * 1024 * 1024);
}

private void test_unavailable_report () {
    var quota = Dc.StorageQuota.parse_connectivity_report (
        "<p>No quota reported by this server.</p>");
    assert (!quota.available);
    assert (quota.used_bytes == 0);
    assert (quota.limit_bytes == 0);
}

public int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/storage-quota/plain", test_plain_report);
    Test.add_func ("/storage-quota/html", test_html_report);
    Test.add_func ("/storage-quota/decimal-comma", test_decimal_comma_report);
    Test.add_func ("/storage-quota/unavailable", test_unavailable_report);
    return Test.run ();
}
