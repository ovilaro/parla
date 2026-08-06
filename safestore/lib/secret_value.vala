namespace SafeStore {

    /**
     * Short-lived mutable storage for a password supplied by a UI.
     *
     * The backing allocation is locked against swapping when the platform
     * permits it and is explicitly overwritten by clear() and on finalization.
     * Callers still need to clear their original input widget immediately.
     */
    public class SecretValue : Object {
        private SecretMemory memory;

        public SecretValue (string value) {
            memory = new SecretMemory (value);
        }

        public unowned string peek () {
            return memory.peek ();
        }

        public void clear () {
            memory.clear ();
        }
    }
}
