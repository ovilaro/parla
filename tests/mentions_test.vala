using Dc;

private string strip_gtk_links (string markup) throws RegexError {
    return /<\/?a(\s[^>]*)?>/.replace (markup, -1, 0, "");
}

private void assert_valid_pango_markup (string markup) {
    try {
        Pango.AttrList attrs;
        string parsed;
        unichar accel;
        Pango.parse_markup (strip_gtk_links (markup), -1, 0,
                            out attrs, out parsed, out accel);
    } catch (Error e) {
        assert_not_reached ();
    }
}

private MentionRoster build_roster () {
    var roster = new MentionRoster ();
    roster.add_member (new MentionMember (10, "Alice", "alice@nine.testrun.org"));
    roster.add_member (new MentionMember (11, "Alice Smith", "asmith@mehl.cloud"));
    roster.add_member (new MentionMember (12, "Bob", "bob@nine.testrun.org"));
    return roster;
}

/* Roster shaped like a real account: the local user (core names the self
   contact "Me", the roster substitutes the configured display name) plus a
   contact whose name is a prefix of the account name. */
private MentionRoster build_self_roster () {
    var roster = new MentionRoster ();
    roster.add_self_key ("pancake-dcg");
    roster.add_self_key ("pancake-dcg@nine.testrun.org");
    roster.add_member (new MentionMember (1, "pancake-dcg",
                                          "pancake-dcg@nine.testrun.org", true));
    roster.add_member (new MentionMember (12, "pancake", "pancake@nopcode.org"));
    return roster;
}

private void test_hyphen_not_truncated () {
    var roster = build_self_roster ();
    /* "@pancake-dcg" must not degrade to the contact named "pancake". */
    var spans = Dc.Mentions.find_mentions ("hey @pancake-dcg how are you", roster);
    assert (spans.length == 1);
    assert (spans[0].display == "pancake-dcg");
    assert (spans[0].href == "parla-mention:cid=1");
    assert (spans[0].is_self);
    assert (spans[0].end - spans[0].start == "@pancake-dcg".length);

    /* The shorter name still resolves on its own. */
    var spans2 = Dc.Mentions.find_mentions ("hey @pancake how are you", roster);
    assert (spans2.length == 1);
    assert (spans2[0].href == "parla-mention:cid=12");

    /* A trailing dot ends a sentence, it does not continue the name. */
    var spans3 = Dc.Mentions.find_mentions ("ping @pancake.", roster);
    assert (spans3.length == 1);
    assert (spans3[0].display == "pancake");
}

private void test_self_mention_forms_agree () {
    var roster = build_self_roster ();
    /* Name and address forms must render the same label, never core's "Me". */
    var by_name = Dc.Mentions.find_mentions ("@pancake-dcg ping", roster);
    var by_addr = Dc.Mentions.find_mentions (
        "@pancake-dcg@nine.testrun.org ping", roster);
    assert (by_name.length == 1 && by_addr.length == 1);
    assert (by_name[0].display == "pancake-dcg");
    assert (by_addr[0].display == "pancake-dcg");
    assert (by_name[0].is_self && by_addr[0].is_self);
    assert (Dc.Mentions.has_self_mention ("@pancake-dcg ping", roster));
    assert (!Dc.Mentions.has_self_mention ("@pancake ping", roster));
}

private void test_self_name_without_member () {
    /* Direct chats carry no self member: the account's own keys must still
       resolve, which is how another client's "@name" mention is recognized. */
    var roster = new MentionRoster ();
    roster.add_self_key ("pancake-dcg");
    roster.add_member (new MentionMember (12, "Bob", "bob@nine.testrun.org"));

    var spans = Dc.Mentions.find_mentions ("yo @pancake-dcg", roster);
    assert (spans.length == 1);
    assert (spans[0].is_self);
    assert (spans[0].display == "pancake-dcg");
    assert (spans[0].href == "parla-mention:cid=1");
}

private void test_name_longest_match () {
    var roster = build_roster ();

    var spans = Dc.Mentions.find_mentions ("hi @Alice Smith how are you", roster);
    assert (spans.length == 1);
    assert (spans[0].display == "Alice Smith");
    assert (spans[0].href == "parla-mention:cid=11");

    var spans2 = Dc.Mentions.find_mentions ("hi @Alice how are you", roster);
    assert (spans2.length == 1);
    assert (spans2[0].display == "Alice");
    assert (spans2[0].href == "parla-mention:cid=10");
}

private void test_no_partial_name_match () {
    var roster = build_roster ();
    /* "@Alicexyz" must not resolve to "Alice". */
    var spans = Dc.Mentions.find_mentions ("hey @Alicexyz", roster);
    assert (spans.length == 0);
}

private void test_boundary_before_at () {
    var roster = build_roster ();
    /* '@' not at start / after whitespace is not a mention (email-like). */
    var spans = Dc.Mentions.find_mentions ("mail me at foo@Alice", roster);
    assert (spans.length == 0);

    var spans2 = Dc.Mentions.find_mentions ("@Bob hi", roster);
    assert (spans2.length == 1);
    assert (spans2[0].start == 0);
    assert (spans2[0].display == "Bob");
}

private void test_address_mention () {
    var roster = build_roster ();

    var spans = Dc.Mentions.find_mentions ("ping @alice@nine.testrun.org now", roster);
    assert (spans.length == 1);
    assert (spans[0].display == "Alice");
    assert (spans[0].href == "parla-mention:cid=10");

    /* Trailing punctuation is trimmed off the address. */
    var spans2 = Dc.Mentions.find_mentions ("thanks @bob@nine.testrun.org!", roster);
    assert (spans2.length == 1);
    assert (spans2[0].href == "parla-mention:cid=12");
}

private void test_unknown_address_not_resolved () {
    var roster = build_roster ();
    var spans = Dc.Mentions.find_mentions ("hi @nobody@somewhere.org", roster);
    assert (spans.length == 0);
}

private void test_render_markup_is_valid () {
    Dc.Markdown.mode = Dc.MarkdownMode.DISABLED;
    var roster = build_roster ();

    string markup = Dc.Mentions.render_markup (
        "hey @Alice check https://example.com", roster);
    assert (markup.contains ("parla-mention:cid=10"));
    assert (markup.contains ("@Alice"));
    assert (markup.contains ("<a href=\"https://example.com\">"));
    assert_valid_pango_markup (markup);
}

private void test_render_self_mention_chip () {
    Dc.Markdown.mode = Dc.MarkdownMode.DISABLED;
    var roster = build_self_roster ();
    string markup = Dc.Mentions.render_markup ("yo @pancake-dcg", roster);
    assert (markup.contains ("@pancake-dcg"));
    assert (!markup.contains ("@Me"));
    assert_valid_pango_markup (markup);
}

private void test_render_markup_no_mentions () {
    Dc.Markdown.mode = Dc.MarkdownMode.DISABLED;
    var roster = build_roster ();
    string markup = Dc.Mentions.render_markup ("no mentions here", roster);
    assert (markup == "no mentions here");
}

private void test_self_detection () {
    string[] keys = { "me myself", "self@nine.testrun.org" };

    assert (Dc.Mentions.mentions_self ("hello @me myself !", keys));
    assert (Dc.Mentions.mentions_self ("ping @self@nine.testrun.org", keys));
    assert (!Dc.Mentions.mentions_self ("ping @someone else", keys));
    assert (!Dc.Mentions.mentions_self ("no at sign", keys));
    /* Not at a boundary. */
    assert (!Dc.Mentions.mentions_self ("mailto@me myself", keys));
    /* A longer hyphenated name is a different person, not a self-mention. */
    assert (!Dc.Mentions.mentions_self ("@me myself-and-i hi",
                                        { "me myself" }));
}

public int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/mentions/name-longest-match", test_name_longest_match);
    Test.add_func ("/mentions/hyphen-not-truncated", test_hyphen_not_truncated);
    Test.add_func ("/mentions/self-forms-agree", test_self_mention_forms_agree);
    Test.add_func ("/mentions/self-name-no-member", test_self_name_without_member);
    Test.add_func ("/mentions/no-partial-name", test_no_partial_name_match);
    Test.add_func ("/mentions/boundary-before-at", test_boundary_before_at);
    Test.add_func ("/mentions/address", test_address_mention);
    Test.add_func ("/mentions/unknown-address", test_unknown_address_not_resolved);
    Test.add_func ("/mentions/render-valid", test_render_markup_is_valid);
    Test.add_func ("/mentions/render-self-chip", test_render_self_mention_chip);
    Test.add_func ("/mentions/render-no-mentions", test_render_markup_no_mentions);
    Test.add_func ("/mentions/self-detection", test_self_detection);
    return Test.run ();
}
