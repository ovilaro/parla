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

private void test_table_grid () {
    Dc.Markdown.enabled = true;

    string markup = Dc.Markdown.format (
        "| Name | Qty |\n" +
        "| --- | ---: |\n" +
        "| Apples | 12 |\n" +
        "| Pear | 7 |");

    assert (markup ==
        "<tt>Name   | Qty\n" +
        "-------+----\n" +
        "Apples |  12\n" +
        "Pear   |   7</tt>");
    assert_valid_pango_markup (markup);
}

private void test_table_with_inline_markup_and_link () {
    Dc.Markdown.enabled = true;

    string markup = Dc.Markdown.format (
        "| Thing | URL |\n" +
        "| --- | --- |\n" +
        "| **bold** | https://example.com |");

    assert (markup.contains ("<tt>Thing"));
    assert (markup.contains ("<b>bold</b>"));
    assert (markup.contains ("<a href=\"https://example.com\">"));
    assert_valid_pango_markup (markup);
}

private void test_plain_pipe_text_is_not_table () {
    Dc.Markdown.enabled = true;

    string markup = Dc.Markdown.format ("hello | world\nnot a separator");

    assert (!markup.contains ("<tt>"));
    assert (markup == "hello | world\nnot a separator");
}

public int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/markdown/table-grid", test_table_grid);
    Test.add_func ("/markdown/table-inline-markup-link", test_table_with_inline_markup_and_link);
    Test.add_func ("/markdown/plain-pipe-text", test_plain_pipe_text_is_not_table);
    return Test.run ();
}
