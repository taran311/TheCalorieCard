# Firestore rules for the new features

The new features use some new collections. Until rules allow them, those
features fail with "permission denied", and the app shows a polite error.
Merge these into your rules in the Firebase console (Firestore Database →
Rules). They assume a `users/{uid}` doc with a `friends` array, as the app
already uses.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() { return request.auth != null; }
    function me() { return request.auth.uid; }
    function friendsOf(uid) {
      return get(/databases/$(database)/documents/users/$(uid)).data.get('friends', []);
    }

    // ---- Split the bill ----
    match /bill_splits/{id} {
      allow read: if signedIn() &&
        (resource.data.from_user_id == me() || me() in resource.data.to_user_ids);
      allow create: if signedIn() &&
        request.resource.data.from_user_id == me() &&
        request.resource.data.to_user_ids.hasOnly(friendsOf(me()));
      // A recipient may only change their own status.
      allow update: if signedIn() &&
        me() in resource.data.to_user_ids &&
        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status']) &&
        request.resource.data.status.diff(resource.data.status).affectedKeys().hasOnly([me()]);
      // The sender can withdraw it (used if logging their share fails).
      allow delete: if signedIn() && resource.data.from_user_id == me();
    }

    // ---- Challenges ----
    match /challenges/{id} {
      allow read: if signedIn() && me() in resource.data.member_ids;
      allow create: if signedIn() &&
        request.resource.data.created_by == me() &&
        me() in request.resource.data.member_ids;
      // Members can only remove themselves (Leave).
      allow update: if signedIn() &&
        me() in resource.data.member_ids &&
        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['member_ids']) &&
        !(me() in request.resource.data.member_ids);
    }

    // ---- Direct debits (private) ----
    match /direct_debits/{id} {
      allow read, update, delete: if signedIn() && resource.data.user_id == me();
      allow create: if signedIn() && request.resource.data.user_id == me();
    }
  }
}
```

Also check these existing rules:

- **daily_logs**: challenge members need to read each other's
  `{uid}_{date}` docs to score challenges. If only friends can read them,
  a member who isn't your friend shows 0 rather than breaking the page.
- **users/{uid}**: you write `card_design`, `best_streak`, `card_unlocks` and
  `calorie_sense` on your own doc, and friends need to read them to see your
  card design and Calorie Sense on the hiscores.
- **user_data/{doc}**: pots add the fields `pots_enabled`, `pot`, `pot_week`,
  `pot_spent` and `pot_spent_date` to your own profile.

## Achievements

Achievements are saved on `user_achievements/{uid}` (unlocks, progress and a
few counters). You write your own; friends read it to see your achievements.

```
match /user_achievements/{uid} {
  allow read: if signedIn();
  allow write: if signedIn() && me() == uid;
}
```

Working achievements out reads your own `daily_logs` (finished days),
`users/{uid}`, `user_data`, `direct_debits`, `recipes` and `challenges`, all
of which your rules already let you read.

## Guess the Calories

Games are saved in `calorie_games/{id}`. Both players can read a game; you
can only start one with a friend, and only add your own guesses. Either
player can cancel a game that hasn't finished; finished games stay, so
nobody can quietly delete a loss. Add this inside `match /databases/...`:

```
match /calorie_games/{id} {
  function game() { return resource.data; }
  function incoming() { return request.resource.data; }
  function mineBefore() { return game().guesses[me()]; }
  function mineAfter() { return incoming().guesses[me()]; }
  function allGuessed(d) {
    return d.guesses[d.player_ids[0]].size() == d.foods.size() &&
      d.guesses[d.player_ids[1]].size() == d.foods.size();
  }

  // A stale link to a cancelled game reads as "missing", not "denied".
  allow read: if signedIn() && (resource == null || me() in game().player_ids);
  allow create: if signedIn() &&
    incoming().keys().hasOnly(['player_ids', 'names', 'created_by', 'foods',
      'guesses', 'status', 'winner', 'created_at', 'updated_at']) &&
    incoming().created_by == me() &&
    incoming().player_ids.size() == 2 &&
    incoming().player_ids[0] != incoming().player_ids[1] &&
    me() in incoming().player_ids &&
    incoming().player_ids.removeAll([me()]).hasOnly(friendsOf(me())) &&
    incoming().foods.size() == 5 &&
    incoming().guesses.keys().hasOnly(incoming().player_ids) &&
    incoming().guesses[incoming().player_ids[0]].size() == 0 &&
    incoming().guesses[incoming().player_ids[1]].size() == 0 &&
    incoming().status == 'active' &&
    incoming().winner == null &&
    incoming().created_at == request.time &&
    incoming().updated_at == request.time;
  // One more guess of your own each time; earlier guesses can't change.
  // The last guess of the game also sets status, winner and finished_at.
  allow update: if signedIn() &&
    me() in game().player_ids &&
    game().status == 'active' &&
    incoming().diff(game()).affectedKeys()
      .hasOnly(['guesses', 'updated_at', 'status', 'winner', 'finished_at']) &&
    incoming().guesses.diff(game().guesses).affectedKeys().hasOnly([me()]) &&
    mineAfter().size() == mineBefore().size() + 1 &&
    mineAfter().size() <= game().foods.size() &&
    mineAfter()[0:mineBefore().size()] == mineBefore() &&
    incoming().updated_at == request.time &&
    (
      (incoming().status == 'active' && incoming().winner == null &&
        !allGuessed(incoming())) ||
      (incoming().status == 'finished' && allGuessed(incoming()) &&
        (incoming().winner == 'draw' || incoming().winner in game().player_ids) &&
        incoming().finished_at == request.time)
    );
  allow delete: if signedIn() &&
    me() in game().player_ids &&
    game().status == 'active';
}
```

The game also posts into your one-to-one chat ("I've challenged you…",
"Your turn", the result), using the same `conversations` rules as cheers.
