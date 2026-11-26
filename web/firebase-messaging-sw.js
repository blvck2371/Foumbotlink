// Notifications push de Foumbot Link dans le navigateur, quand l'onglet
// est fermé ou en arrière-plan (au premier plan, l'app reçoit les messages
// elle-même). Version du SDK alignée sur firebase_core_web
// (supportedFirebaseJsSdkVersion) : à remonter avec les paquets Firebase.
importScripts("https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js");

// Configuration publique de l'app web (identique à lib/firebase_options.dart).
firebase.initializeApp({
  apiKey: "AIzaSyBRMuM9n1HsfAcRRXygMjiUlIFYrSFSOec",
  appId: "1:141324093576:web:acdc4217391e9a4e88773d",
  messagingSenderId: "141324093576",
  projectId: "foumbotlink",
  authDomain: "foumbotlink.firebaseapp.com",
  storageBucket: "foumbotlink.firebasestorage.app",
});

const messaging = firebase.messaging();

// Les messages avec un bloc `notification` sont affichés par le SDK.
// Un appel entrant n'a que des données : on le montre nous-mêmes, sinon
// l'appelé ne verrait rien tant que l'onglet n'est pas au premier plan.
messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  if (payload.notification || data.type !== "incoming_call") return;
  const kind = data.callType === "video" ? "Appel vidéo" : "Appel vocal";
  return self.registration.showNotification(data.callerName || "Appel entrant", {
    body: `${kind} entrant…`,
    icon: "icons/Icon-192.png",
    tag: `call_${data.callId || ""}`,
    requireInteraction: true,
    data,
  });
});

// Toucher la notification ramène sur l'app (onglet existant ou nouveau).
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({type: "window", includeUncontrolled: true}).then((list) => {
      for (const c of list) {
        if ("focus" in c) return c.focus();
      }
      return clients.openWindow("./");
    }),
  );
});
