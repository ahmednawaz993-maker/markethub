// Background FCM handler for PakBazaar web. Shows a notification when a push
// arrives while the site is closed or in the background.
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js"
);
importScripts(
  "https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js"
);

firebase.initializeApp({
  apiKey: "AIzaSyCERNmuaRMssjATHPc3MoJPtfLeVtqykKA",
  authDomain: "markethub-80276.firebaseapp.com",
  projectId: "markethub-80276",
  storageBucket: "markethub-80276.firebasestorage.app",
  messagingSenderId: "541505846653",
  appId: "1:541505846653:web:2afe478f1fb52e358a2014",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const n = payload.notification || {};
  self.registration.showNotification(n.title || "PakBazaar", {
    body: n.body || "",
    icon: "/icons/Icon-192.png",
  });
});
