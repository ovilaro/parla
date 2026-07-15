using Dc;

private Json.Array message_ids () {
    var ids = new Json.Array ();
    ids.add_int_element (10);
    ids.add_int_element (20);
    ids.add_int_element (30);
    return ids;
}

private void test_find_id () {
    var ids = message_ids ();
    assert (MessageHistory.find_id (ids, 10) == 0);
    assert (MessageHistory.find_id (ids, 20) == 1);
    assert (MessageHistory.find_id (ids, 30) == 2);
    assert (MessageHistory.find_id (ids, 99) == -1);
}

private void test_earlier_batches_stop_at_target () {
    assert (MessageHistory.earlier_batch_start (350, 25) == 250);
    assert (MessageHistory.earlier_batch_start (250, 25) == 150);
    assert (MessageHistory.earlier_batch_start (150, 25) == 50);
    assert (MessageHistory.earlier_batch_start (50, 25) == 25);
}

private void test_nearby_target_avoids_overfetch () {
    assert (MessageHistory.earlier_batch_start (350, 280) == 280);
    assert (MessageHistory.earlier_batch_start (30, 0) == 0);
    assert (MessageHistory.earlier_batch_start (30, 30) == 30);
}

public int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/message-history/find-id", test_find_id);
    Test.add_func ("/message-history/earlier-batches-stop-at-target",
                   test_earlier_batches_stop_at_target);
    Test.add_func ("/message-history/nearby-target-avoids-overfetch",
                   test_nearby_target_avoids_overfetch);
    return Test.run ();
}
