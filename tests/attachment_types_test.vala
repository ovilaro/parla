using Dc;

private void test_sticker_formats () {
    assert (AttachmentTypes.infer_outgoing_view_type ("/tmp/a.gif") == "Sticker");
    assert (AttachmentTypes.infer_outgoing_view_type ("/tmp/a.WEBP") == "Sticker");
    assert (AttachmentTypes.infer_outgoing_view_type ("/tmp/a.webm") == "Sticker");
}

private void test_display_name_fallback () {
    assert (AttachmentTypes.infer_outgoing_view_type (
        "/tmp/blob-without-extension", "sticker.webp") == "Sticker");
}

private void test_webxdc_apps () {
    assert (AttachmentTypes.infer_outgoing_view_type ("/tmp/poll.xdc") == "Webxdc");
    assert (AttachmentTypes.infer_outgoing_view_type (
        "/tmp/blob-without-extension", "chess.XDC") == "Webxdc");
}

private void test_regular_attachments () {
    assert (AttachmentTypes.infer_outgoing_view_type ("/tmp/photo.png") == null);
    assert (AttachmentTypes.infer_outgoing_view_type ("/tmp/audio.ogg") == null);
    assert (AttachmentTypes.infer_outgoing_view_type (null) == null);
}

public int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/attachment-types/sticker-formats", test_sticker_formats);
    Test.add_func ("/attachment-types/display-name-fallback", test_display_name_fallback);
    Test.add_func ("/attachment-types/webxdc", test_webxdc_apps);
    Test.add_func ("/attachment-types/regular", test_regular_attachments);
    return Test.run ();
}
