using Dc;

int failures = 0;

void check_eq (string got, string expected, string what) {
    if (got != expected) {
        stderr.printf ("FAIL: %s\n  expected: %s\n  got:      %s\n",
                       what, expected, got);
        failures++;
    }
}

int main () {
    check_eq (
        LinkCleaner.clean_url ("https://www.youtube.com/watch?v=abc123&si=XyZ_track&feature=share"),
        "https://www.youtube.com/watch?v=abc123",
        "youtube keeps video id, drops si/feature");

    check_eq (
        LinkCleaner.clean_url ("https://youtu.be/abc123?si=XyZ&t=42"),
        "https://youtu.be/abc123?t=42",
        "youtu.be keeps timestamp");

    check_eq (
        LinkCleaner.clean_url ("https://x.com/user/status/123?s=20&t=AbCdEf"),
        "https://x.com/user/status/123",
        "x.com share params dropped");

    check_eq (
        LinkCleaner.clean_url ("https://twitter.com/user/status/123?ref_src=twsrc%5Etfw"),
        "https://twitter.com/user/status/123",
        "twitter ref_src dropped");

    check_eq (
        LinkCleaner.clean_url ("https://www.instagram.com/p/Cxyz/?igsh=MTQ4&img_index=2"),
        "https://www.instagram.com/p/Cxyz/?img_index=2",
        "instagram keeps carousel index, drops igsh");

    check_eq (
        LinkCleaner.clean_url ("https://www.facebook.com/story.php?story_fbid=1&id=2&mibextid=Nif5oz"),
        "https://www.facebook.com/story.php?story_fbid=1&id=2",
        "facebook keeps content ids, drops mibextid");

    check_eq (
        LinkCleaner.clean_url ("https://www.facebook.com/photo?fbid=1&__cft__[0]=AZW&__tn__=%2CO"),
        "https://www.facebook.com/photo?fbid=1",
        "facebook double-underscore params dropped");

    check_eq (
        LinkCleaner.clean_url ("https://www.linkedin.com/posts/foo_bar-activity-123?trk=public_profile&trackingId=abc%3D%3D"),
        "https://www.linkedin.com/posts/foo_bar-activity-123",
        "linkedin trk/trackingId dropped");

    check_eq (
        LinkCleaner.clean_url ("https://www.tiktok.com/@user/video/123?_t=8abc&_r=1&is_from_webapp=1"),
        "https://www.tiktok.com/@user/video/123",
        "tiktok share params dropped");

    check_eq (
        LinkCleaner.clean_url ("https://www.reddit.com/r/gnome/comments/abc/foo/?share_id=xyz&context=3"),
        "https://www.reddit.com/r/gnome/comments/abc/foo/?context=3",
        "reddit keeps comment context, drops share_id");

    check_eq (
        LinkCleaner.clean_url ("https://open.spotify.com/track/abc?si=xyz"),
        "https://open.spotify.com/track/abc",
        "spotify si dropped");

    check_eq (
        LinkCleaner.clean_url ("https://www.amazon.com/dp/B08N5WRWNW/ref=sr_1_3?tag=aff-20&qid=1700000000&sr=8-3&th=1"),
        "https://www.amazon.com/dp/B08N5WRWNW?th=1",
        "amazon ref path and affiliate params dropped, keeps variant");

    check_eq (
        LinkCleaner.clean_url ("https://example.com/page?utm_source=nl&utm_medium=email&id=7"),
        "https://example.com/page?id=7",
        "utm_* dropped on any site");

    check_eq (
        LinkCleaner.clean_url ("https://example.com/?fbclid=IwAR123&gclid=abc"),
        "https://example.com/",
        "global click ids dropped on any site");

    check_eq (
        LinkCleaner.clean_url ("https://example.com/watch?si=notyoutube&v=1"),
        "https://example.com/watch?si=notyoutube&v=1",
        "site-specific params untouched on other hosts");

    check_eq (
        LinkCleaner.clean_url ("https://example.com/a?x=1#frag"),
        "https://example.com/a?x=1#frag",
        "fragment preserved");

    check_eq (
        LinkCleaner.clean_url ("https://example.com/a?utm_source=x#frag"),
        "https://example.com/a#frag",
        "empty query removed, fragment preserved");

    check_eq (
        LinkCleaner.clean_text ("look https://youtu.be/abc?si=x and https://x.com/a/status/1?s=20 wow"),
        "look https://youtu.be/abc and https://x.com/a/status/1 wow",
        "multiple urls inside text");

    check_eq (
        LinkCleaner.clean_text ("(see https://youtu.be/abc?si=x)"),
        "(see https://youtu.be/abc)",
        "trailing parenthesis not part of url");

    check_eq (
        LinkCleaner.clean_text ("https://en.wikipedia.org/wiki/Foo_(bar)?utm_source=x"),
        "https://en.wikipedia.org/wiki/Foo_(bar)",
        "balanced parentheses stay in url");

    check_eq (
        LinkCleaner.clean_text ("no links here"),
        "no links here",
        "plain text untouched");

    check_eq (
        LinkCleaner.clean_text ("Check https://youtu.be/abc?si=x."),
        "Check https://youtu.be/abc.",
        "trailing period not part of url");

    if (failures == 0) stdout.printf ("all link-cleaner tests passed\n");
    return failures == 0 ? 0 : 1;
}
