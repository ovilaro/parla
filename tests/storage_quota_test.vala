private void assert_quota (string report, int64 used, int64 limit) {
    var quota = Dc.StorageQuota.parse_connectivity_report (report);
    assert (quota.available);
    assert (quota.used_bytes == used);
    assert (quota.limit_bytes == limit);
}

private void assert_fraction (double actual, double expected) {
    double delta = actual - expected;
    if (delta < 0.0) delta = -delta;
    assert (delta < 0.000001);
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
    assert (!quota.has_limit ());
    assert_fraction (quota.used_fraction (), 0.0);
    assert (quota.summary_text () == "Server quota has not been reported yet.");
}

private void test_display_values () {
    int64 mib = (int64) 1024 * 1024;
    var quota = new Dc.StorageQuota ();
    quota.available = true;
    quota.used_bytes = 5 * mib;
    quota.limit_bytes = 20 * mib;

    assert (quota.has_limit ());
    assert (quota.left_bytes () == 15 * mib);
    assert_fraction (quota.used_fraction (), 0.25);
    assert (!quota.is_warning ());
    assert (!quota.is_error ());
    assert (Dc.StorageQuota.format_mb (mib / 2) == "0.5 MB");
    assert (quota.summary_text () == "5.0 MB used · 15.0 MB left of 20.0 MB");
}

private void test_thresholds_and_clamp () {
    var quota = new Dc.StorageQuota ();
    quota.available = true;
    quota.limit_bytes = 100;

    quota.used_bytes = 80;
    assert_fraction (quota.used_fraction (), 0.8);
    assert (quota.is_warning ());
    assert (!quota.is_error ());

    quota.used_bytes = 95;
    assert_fraction (quota.used_fraction (), 0.95);
    assert (!quota.is_warning ());
    assert (quota.is_error ());

    quota.used_bytes = 120;
    assert_fraction (quota.used_fraction (), 1.0);
    assert (quota.left_bytes () == 0);
}

public int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/storage-quota/plain", test_plain_report);
    Test.add_func ("/storage-quota/html", test_html_report);
    Test.add_func ("/storage-quota/decimal-comma", test_decimal_comma_report);
    Test.add_func ("/storage-quota/unavailable", test_unavailable_report);
    Test.add_func ("/storage-quota/display-values", test_display_values);
    Test.add_func ("/storage-quota/thresholds-and-clamp", test_thresholds_and_clamp);
    return Test.run ();
}
