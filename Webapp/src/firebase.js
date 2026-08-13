// src/firebase.js — MEKA IoT Firebase Configuration
import { initializeApp } from "firebase/app";
import { getDatabase } from "firebase/database";
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut } from "firebase/auth";
import { getStorage } from "firebase/storage";

const firebaseConfig = {
  apiKey:            "AIzaSyCTUV7fV0ObuQdKa9Tl1lycCRS-ltbvog0",
  authDomain:        "sliot-80296.firebaseapp.com",
  databaseURL:       "https://sliot-80296-default-rtdb.firebaseio.com",
  projectId:         "sliot-80296",
  storageBucket:     "sliot-80296.firebasestorage.app",
  messagingSenderId: "742654983112",
  appId:             "1:742654983112:web:5eb0dbcbdda53fea0b9efd",
  measurementId:     "G-QWMGQ0J370"
};

const app   = initializeApp(firebaseConfig);
export const db = getDatabase(app);
export const auth = getAuth(app);
export const storage = getStorage(app);
export const googleProvider = new GoogleAuthProvider();
export { signInWithPopup, signOut };
export default app;
