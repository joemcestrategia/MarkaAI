importScripts('https://www.gstatic.com/firebasejs/9.17.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.17.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyBpneZQEJ6BlKbtJaBfwlKAXTxGCV-XCFs",
  appId: "1:170942564821:web:a326f050b2a75ebacfd55c",
  messagingSenderId: "170942564821",
  projectId: "wismart-118c3",
  authDomain: "wismart-118c3.firebaseapp.com",
  storageBucket: "wismart-118c3.firebasestorage.app"
});

const messaging = firebase.messaging();
