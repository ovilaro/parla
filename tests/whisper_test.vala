using Dc;

private void test_parse_segments () {
    string output =
        "Detecting language using up to the first 30 seconds. "
        + "Use `--language` to specify the language\n"
        + "Detected language: Spanish\n"
        + "[00:00.800 --> 00:07.160]  Si no me escribes por Telegram\n"
        + "[00:07.160 --> 00:12.340]  entonces si me lo cuentas mejor\n";
    assert (Transcriber.parse_output (output) ==
        "Si no me escribes por Telegram\nentonces si me lo cuentas mejor");
}

private void test_parse_ignores_noise () {
    assert (Transcriber.parse_output ("") == "");
    assert (Transcriber.parse_output ("UserWarning: FP16 is not supported\n") == "");
    assert (Transcriber.parse_output ("[no closing bracket\n") == "");
    assert (Transcriber.parse_output ("[00:00.000 --> 00:01.000]  \n") == "");
}

private void test_parse_takes_first_bracket () {
    assert (Transcriber.parse_output ("[00:00.0 --> 00:01.0] a [b] c\n") ==
        "a [b] c");
}

public int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/whisper/segments", test_parse_segments);
    Test.add_func ("/whisper/noise", test_parse_ignores_noise);
    Test.add_func ("/whisper/first-bracket", test_parse_takes_first_bracket);
    return Test.run ();
}
