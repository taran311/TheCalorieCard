// Shows the evening "log today's food" reminder when The Calorie Card
// isn't open. Firebase Messaging looks for this file at the site root.
importScripts("https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDsINOWDiuf_A7srryvuNajYQwxae3Dqy0",
  appId: "1:795453323864:web:20c99e15c9d0a610d1a82d",
  messagingSenderId: "795453323864",
  projectId: "auth-af04a",
  authDomain: "auth-af04a.firebaseapp.com",
  storageBucket: "auth-af04a.appspot.com",
});

// Messages with a "notification" part are shown automatically; tapping
// one opens the link the server sends (the app).
firebase.messaging();
