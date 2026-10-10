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
    // Fields: type ('head_to_head' | 'group' | 'protein' | 'early_logger'),
    // title, created_by, member_ids, names {uid: name}, start_key and
    // end_key ('YYYY-MM-DD'; a challenge starts the day it's made and runs
    // 7 days), target (finished days, or grams for 'protein').
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
    // `weekdays` (list of 1-7, Monday = 1; empty = every day) limits which
    // days a debit comes up.
    match /direct_debits/{id} {
      allow read, update, delete: if signedIn() && resource.data.user_id == me();
      allow create: if signedIn() && request.resource.data.user_id == me();
    }
  }
}
```

Also check these existing rules:

- **friend_groups**: when you remove a friend, they're taken out of the
  groups *you* made (`members` loses their id, and so does the group
  chat's `participant_ids`). Groups someone else made are left alone, and
  the app tells you which ones you still share. If your rules don't let a
  group's creator edit `members`, the app says so instead. A rule that
  allows this, and lets members leave:

  ```
  match /friend_groups/{id} {
    allow read: if signedIn() && me() in resource.data.members;
    allow create: if signedIn() &&
      request.resource.data.creator_id == me() &&
      me() in request.resource.data.members;
    // The creator can change the group; anyone else can only leave.
    allow update: if signedIn() && (
      resource.data.creator_id == me() ||
      (request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['members']) &&
       request.resource.data.members.removeAll(resource.data.members)
         .size() == 0 &&
       resource.data.members.removeAll(request.resource.data.members)
         .hasOnly([me()])));
    allow delete: if signedIn() && resource.data.creator_id == me();
  }
  ```
- **daily_logs**: the Friends page shows each friend's day live (today's
  `{uid}_{date}` doc: `finished`, `totals`, `balances`, `goals`), and the
  Statement reads your own history to judge finished days the same way
  as Hiscores. Friends (and group members) need read access.
- **user_data**: friends' and group members' calorie goal is read as a
  fallback when their day's history has no budget in it (the same doc the
  read-only friend card already reads).
- **user_food**: the "Protein goal" and "Early logger" challenges add up
  members' food since the challenge started, as the group page already
  does for today. Members whose food you can't read show 0.
- **conversations/{id}/messages**: messages may carry extra fields:
  `type: 'game'` with `game_id` (Guess the Calories messages, shown as a
  tappable card that opens the game), `type: 'nudge'` ("Nudge to log"),
  and `type: 'card'` with `card` as before. If your message rules list
  allowed keys, add `type`, `game_id` and `card`. Sharing "Your week" can
  post into a group chat (`group_{groupId}`) with the same fields as the
  Chat tab.
- Nudges are limited to one per friend per day on your device (no new
  Firestore fields).

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

## Weight log

Each weigh-in is `weigh_ins/{uid}_{yyyy-MM-dd}` (one per day) with
`user_id`, `date_key`, `kg` and `created_at`. Only you can read or write
yours:

```
match /weigh_ins/{id} {
  allow read, delete: if signedIn() && resource.data.user_id == me();
  allow create, update: if signedIn() &&
    request.resource.data.user_id == me() &&
    id == me() + '_' + request.resource.data.date_key &&
    request.resource.data.kg is number &&
    request.resource.data.kg > 0 && request.resource.data.kg < 400;
}
```

## Profile additions

- `user_data`: `units` ('metric' | 'imperial') and `weight_unit`
  ('kg' | 'st' | 'lb'); `height` and `weight` can now have decimals. Your
  existing owner-only rule covers these.
- `users/{uid}.display_name`: the name friends see (up to 40 characters),
  written by the owner. If your `users` rule limits which keys you can
  write, add `display_name`.
- `user_food`: new optional fields `food_source`, `food_estimate`,
  `food_edited`, `food_base`, `food_portion_base` and `food_multiplier`, and
  entries can now be **updated** by their owner (editing a portion, fixing
  calories, moving meal). Make sure your rule allows update when
  `resource.data.user_id == me()` and the `user_id` doesn't change:

```
allow update: if signedIn() && resource.data.user_id == me() &&
  request.resource.data.user_id == me();
```

## Account deletion

Deleting an account goes through the server (`POST /account/delete`),
which uses the Admin SDK, so no client rules are needed for it.
