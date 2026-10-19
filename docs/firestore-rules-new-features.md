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
- **users/{uid}**: you write `card_design`, `best_streak`, `card_unlocks`,
  `calorie_sense` and `games` (Games XP, level and Daily Calorie Quiz) on your
  own doc, and friends need to read them to see your card design, Calorie
  Sense and Games XP on the hiscores (and friends' Daily scores).
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
can only start one with a friend, and only add your own guesses (and, in a
"Guess what I ate" game, your own 5 foods, once). Either player can cancel
a game that hasn't finished; finished games stay, so nobody can quietly
delete a loss.

Fields:

- `mode`: `'classic'` (Mystery foods: both guess the same 5 dealt `foods`),
  `'higherLower'` (Higher or Lower: the same 10 pairs for both) or `'swap'`
  (Guess what I ate: no longer offered by the app, but older games and
  older app versions still use it). Games saved before this have no `mode`
  and are classic.
- `foods`: the 5 dealt foods (`{emoji, name, portion, kcal}`); in Higher or
  Lower the 20 foods of the 10 pairs, two at a time; empty in a swap game.
- `guesses`: in Higher or Lower, one `0` or `1` per pair (which of the two
  the player picked as having more calories).
- `picks` (swap only): `{uid: [5 foods] | null}`. The challenger's 5 are
  saved when the game is created; the friend's are null until they pick.
  In a swap game, `guesses[uid]` are for the *other* player's picks.
- `expires_at`: 7 days after the last move (set on create, and pushed back
  by every pick and guess, from the device clock). Games saved before this
  count as 7 days after `updated_at`.
- `expired: true`: the game ran out of time. Either player's app ends a
  stale game: `status: 'finished'`, and `winner` is the only player who had
  guessed all their foods, or `'draw'` (which doesn't count in the record).
- `push_sent`: written by the server only (Admin SDK) when it sends a
  "your turn" push, to avoid sending the same one twice. Clients never
  write it, which the `hasOnly` lists below enforce.

Add this inside `match /databases/...`:

```
match /calorie_games/{id} {
  function game() { return resource.data; }
  function incoming() { return request.resource.data; }
  function isSwap(d) { return d.get('mode', 'classic') == 'swap'; }
  function isHl(d) { return d.get('mode', 'classic') == 'higherLower'; }
  function other(d) { return d.player_ids.removeAll([me()])[0]; }
  // Foods each player guesses: 5 in a swap game, the dealt foods otherwise.
  function total(d) { return isSwap(d) ? 5 : d.foods.size(); }
  // How many answers a player can give: one per pair in Higher or Lower.
  function fits(d, n) {
    return isHl(d) ? n * 2 <= d.foods.size() : n <= total(d);
  }
  function done(d, uid) {
    return isHl(d) ? d.guesses[uid].size() * 2 == d.foods.size()
      : d.guesses[uid].size() == total(d);
  }
  function allGuessed(d) {
    return done(d, d.player_ids[0]) && done(d, d.player_ids[1]);
  }
  function bothPicked(d) {
    return !isSwap(d) ||
      (d.picks[d.player_ids[0]] != null && d.picks[d.player_ids[1]] != null);
  }
  // Older games have no expires_at: a week after the last move.
  function endsAt(d) {
    return 'expires_at' in d ? d.expires_at
      : d.updated_at + duration.value(7, 'd');
  }
  function stale() { return request.time > endsAt(game()); }
  // Set from the device clock: allow a day either side for a wrong clock.
  function freshExpiry() {
    return incoming().expires_at is timestamp &&
      incoming().expires_at > request.time + duration.value(6, 'd') &&
      incoming().expires_at < request.time + duration.value(8, 'd');
  }
  function mineBefore() { return game().guesses[me()]; }
  function mineAfter() { return incoming().guesses[me()]; }

  // A stale link to a cancelled game reads as "missing", not "denied".
  allow read: if signedIn() && (resource == null || me() in game().player_ids);
  allow create: if signedIn() &&
    incoming().keys().hasOnly(['mode', 'player_ids', 'names', 'created_by',
      'foods', 'picks', 'guesses', 'status', 'winner', 'created_at',
      'updated_at', 'expires_at']) &&
    incoming().created_by == me() &&
    incoming().player_ids.size() == 2 &&
    incoming().player_ids[0] != incoming().player_ids[1] &&
    me() in incoming().player_ids &&
    incoming().player_ids.removeAll([me()]).hasOnly(friendsOf(me())) &&
    (
      (!isSwap(incoming()) && incoming().get('mode', 'classic') == 'classic' &&
        incoming().foods.size() == 5 && !('picks' in incoming())) ||
      (isHl(incoming()) && incoming().foods.size() == 20 &&
        !('picks' in incoming())) ||
      (isSwap(incoming()) && incoming().foods.size() == 0 &&
        incoming().picks.keys().hasOnly(incoming().player_ids) &&
        incoming().picks[me()].size() == 5 &&
        incoming().picks[other(incoming())] == null)
    ) &&
    incoming().guesses.keys().hasOnly(incoming().player_ids) &&
    incoming().guesses[incoming().player_ids[0]].size() == 0 &&
    incoming().guesses[incoming().player_ids[1]].size() == 0 &&
    incoming().status == 'active' &&
    incoming().winner == null &&
    incoming().created_at == request.time &&
    incoming().updated_at == request.time &&
    freshExpiry();

  allow update: if signedIn() &&
    me() in game().player_ids &&
    game().status == 'active' &&
    (
      // Your 5 foods in a swap game, once, while the game is open.
      (isSwap(game()) && !stale() &&
        incoming().diff(game()).affectedKeys()
          .hasOnly(['picks', 'updated_at', 'expires_at']) &&
        incoming().picks.diff(game().picks).affectedKeys().hasOnly([me()]) &&
        game().picks[me()] == null &&
        incoming().picks[me()].size() == 5 &&
        incoming().updated_at == request.time &&
        freshExpiry()) ||

      // One more guess of your own each time; earlier guesses can't
      // change. In a swap game, only once both have picked. The last guess
      // of the game also sets status, winner and finished_at.
      (!stale() && bothPicked(game()) &&
        incoming().diff(game()).affectedKeys().hasOnly(['guesses',
          'updated_at', 'expires_at', 'status', 'winner', 'finished_at']) &&
        incoming().guesses.diff(game().guesses).affectedKeys()
          .hasOnly([me()]) &&
        mineAfter().size() == mineBefore().size() + 1 &&
        fits(game(), mineAfter().size()) &&
        // Higher or Lower: each answer is which of the two, 0 or 1.
        (!isHl(game()) || mineAfter()[mineBefore().size()] in [0, 1]) &&
        mineAfter()[0:mineBefore().size()] == mineBefore() &&
        incoming().updated_at == request.time &&
        freshExpiry() &&
        (
          (incoming().status == 'active' && incoming().winner == null &&
            !allGuessed(incoming())) ||
          (incoming().status == 'finished' && allGuessed(incoming()) &&
            (incoming().winner == 'draw' ||
              incoming().winner in game().player_ids) &&
            incoming().finished_at == request.time)
        )) ||

      // Ending a game nobody has moved in for 7 days. The winner is the
      // only player who guessed all their foods, else a draw.
      (stale() &&
        incoming().diff(game()).affectedKeys().hasOnly(['status', 'winner',
          'expired', 'finished_at', 'updated_at']) &&
        incoming().status == 'finished' &&
        incoming().expired == true &&
        incoming().finished_at == request.time &&
        incoming().updated_at == request.time &&
        (
          (done(game(), game().player_ids[0]) !=
              done(game(), game().player_ids[1]) &&
            done(game(), incoming().winner)) ||
          (done(game(), game().player_ids[0]) ==
              done(game(), game().player_ids[1]) &&
            incoming().winner == 'draw')
        ))
    );
  // Games XP: once a game has finished, each player adds themselves to
  // `xp_claimed` once, so its XP is only given once (see GamesService).
  allow update: if signedIn() &&
    me() in game().player_ids &&
    game().status == 'finished' &&
    incoming().diff(game()).affectedKeys().hasOnly(['xp_claimed']) &&
    !(me() in game().get('xp_claimed', [])) &&
    incoming().xp_claimed.size() == game().get('xp_claimed', []).size() + 1 &&
    incoming().xp_claimed.hasAll(game().get('xp_claimed', []).concat([me()]));
  allow delete: if signedIn() &&
    me() in game().player_ids &&
    game().status == 'active';
}
```

The game also posts into your one-to-one chat ("I've challenged you…",
"Your turn", the result), using the same `conversations` rules as cheers.

**"Your turn" notifications.** The app calls the server's
`POST /notify/game` with `{"gameId": "<id>", "event": "update"}` after
creating a game, picking foods, and the guess that completes a player's 5
(including the finishing guess), and with `"event": "nudge"` for Nudge. The
server reads the game, works out who's up and sends at most one push to the
other player (it records that in `push_sent`). The push opens
`https://thecaloriecard.com/?game=<id>`.

`users/{uid}` gets `game_notifications` (bool; turn alerts are on unless
it's `false`, as long as the user has a token in `fcm_tokens`), written by
the owner alongside the existing `fcm_tokens` and `tz_offset_minutes`. If
your `users` rule limits which keys you can write, add
`game_notifications`.

## Games play counts

`game_stats/{yyyy-MM-dd}` counts how often each game is played, so you can
see what people use. It holds only numbers (no names or ids):
`plays: {quiz, meal, own, higher_lower, friends}` and
`players: {...}` (first play on each device that day). Any signed-in user
can add to it; only you (in the console) read it:

```
match /game_stats/{day} {
  allow read: if false;
  allow create, update: if signedIn() &&
    request.resource.data.keys().hasOnly(['plays', 'players']);
}
```

## Gift codes (lifetime Premium)

Codes are kept at `meta/gifts/codes/{CODE}`, under `meta`, which the app
can never read or write, so no rule changes are needed. Only the server
makes, lists and redeems them. Redeeming sets `billing/{uid}.lifetime`.
Admins are set on the server with `ADMIN_EMAILS` and/or `ADMIN_UIDS`.

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

## Usernames, budgets, rest days and notes (October 2026)

Your live rules currently let any signed-in user read and write everything
except `billing` and `meta`, so these all work already. When you tighten
the rules, include:

- `usernames/{handle}` = `{uid, created_at}`: the lock that keeps each
  @username unique.

```
match /usernames/{handle} {
  allow read: if signedIn();
  allow create: if signedIn() && request.resource.data.uid == me() &&
    handle.matches('^[a-z0-9_]{3,20}$');
  allow delete: if signedIn() && resource.data.uid == me();
  allow update: if false;
}
```

- `users/{uid}.username`, `users/{uid}.game_notifications` (owner writes).
- `user_data.budgets` (owner writes).
- `daily_logs/{uid}_{date}.rest_day` (owner writes).
- `user_food/{id}.food_note` (owner updates).
- `calorie_games/{id}.push_sent` is written only by the server.

## Deleting chats and messages

- **Delete chat** (for you only) writes `cleared_at.{uid}`,
  `deleted_at.{uid}` and `unread_count.{uid}` on
  `conversations/{id}`. **Delete for me** on a single message adds its id
  to `hidden_messages.{uid}` (an array). Any participant may write their
  own keys. If your conversation rules list allowed keys, add
  `deleted_at` and `hidden_messages` next to `cleared_at`.
- **Delete for everyone** deletes the message doc, and only the sender
  can do it. It then sets `last_message` to "Message deleted" if it was
  the latest.

```
match /conversations/{cid}/messages/{mid} {
  // ...your existing read/create/update rules...
  allow delete: if signedIn() && resource.data.sender_id == me();
}
```

## Avatars

- `users/{uid}.avatar` (owner writes): `{preset: 'avocado'}` or
  `{photo: <256px JPEG, base64, under 150KB>}`; missing means the
  initial-letter avatar. Friends and chat partners read it from the
  `users` doc they already read for names. If your users rules list the
  fields an owner may write, add `avatar`.
