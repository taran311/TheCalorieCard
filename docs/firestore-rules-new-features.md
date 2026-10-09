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
