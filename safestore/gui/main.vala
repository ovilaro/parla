namespace SafeStore {

    public class Application : Adw.Application {

        public Application () {
            Object (
                application_id: "io.github.trufae.SafeStore",
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
        }

        protected override void activate () {
            var window = this.active_window as Window;
            if (window == null) {
                window = new Window (this);
            }
            window.present ();
        }
    }
}

int main (string[] args) {
    return new SafeStore.Application ().run (args);
}
