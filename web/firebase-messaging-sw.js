// Background FCM handler for PakBazar web. Shows a notification when a push
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

// Where a notification should take the reader. Listing pushes have a real
// route; everything else goes to the app, which then routes from its own
// notification inbox.
function targetUrl(data) {
  const d = data || {};
  const listingId = d.listingId || (d.type === "listing" ? d.refId : "");
  return listingId ? "/ad/" + listingId : "/";
}

messaging.onBackgroundMessage((payload) => {
  const n = payload.notification || {};
  self.registration.showNotification(n.title || "PakBazar", {
    body: n.body || "",
    icon: "/icons/Icon-192.png",
    // Carried through to the click handler below — without it a tapped
    // notification had nowhere to go, so tapping one did nothing at all.
    data: { url: targetUrl(payload.data) },
  });
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((windows) => {
        // Reuse the tab the reader already has open rather than stacking up a
        // new one per notification.
        for (const client of windows) {
          if (client.url.indexOf(self.location.origin) === 0 && client.focus) {
            client.navigate(url);
            return client.focus();
          }
        }
        return self.clients.openWindow(url);
      })
  );
});
