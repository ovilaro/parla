int main (string[] args) {
    Dc.Platform.setup_macos_bundle_environment ();
    var app = new Dc.Application ();
    return app.run (args);
}
