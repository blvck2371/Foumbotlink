/**
 * Discussion de bout en bout : Alice envoie, Bob reçoit, Carole (tierce)
 * ne voit rien.
 *
 * Chaque type de message suit le chemin exact de l'app, sous les vraies
 * règles Firestore **et** Storage :
 *   1. le fichier monte dans `chat/{conversation}/…` avec son type MIME
 *      (ChatService.upload*) ;
 *   2. le message est écrit (ChatService.sendMessage, mêmes champs que
 *      ChatMessage.toMap), l'aperçu de la conversation mis à jour ;
 *   3. le trigger `onMessageCreated` produit la notification de Bob ;
 *   4. Bob relit le message, télécharge le fichier par son URL — comme le
 *      lecteur de l'app — et retrouve exactement les octets envoyés.
 *
 * Puis ce qui suit la réception : lu, réactions, vue unique, suppression
 * pour tous / pour moi, transfert, plafonds de taille, blocage.
 *
 *   npm run test:chat
 */

process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: process.env.GCLOUD_PROJECT,
});

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  collection,
  query,
  where,
  getDocs,
  serverTimestamp,
  increment,
  deleteField,
  arrayUnion,
  Timestamp,
} = require("firebase/firestore");
const {
  ref,
  uploadBytes,
  getBytes,
  getDownloadURL,
  deleteObject,
} = require("firebase/storage");
const {getFirestore} = require("firebase-admin/firestore");
const fs = require("fs");
const path = require("path");
const {onMessageCreated} = require("../index.js");

const PROJECT = process.env.GCLOUD_PROJECT || "demo-chat";
const ALICE = "alice";
const BOB = "bob";
const CAROLE = "carole";
const CONV = [ALICE, BOB].sort().join("_");

let failures = 0;

/**
 * Exécute une vérification en annonçant son résultat.
 *
 * @param {string} name Ce qui est vérifié.
 * @param {function(): Promise<void>} body Le cas.
 * @return {Promise<void>} Résolue une fois le cas terminé.
 */
async function check(name, body) {
  try {
    await body();
    console.log(`  ✓ ${name}`);
  } catch (err) {
    failures++;
    console.error(`  ✗ ${name}\n    ${err.message}`);
  }
}

/**
 * Lève une erreur lisible si la condition est fausse.
 *
 * @param {boolean} ok Condition.
 * @param {string} what Ce qui était attendu.
 */
function assert(ok, what) {
  if (!ok) throw new Error(what);
}

/**
 * Faux contenu binaire, reconnaissable octet par octet.
 *
 * @param {string} magic En-tête du format (« %PDF », …).
 * @param {number} size Taille totale.
 * @return {Uint8Array} Les octets.
 */
function fakeFile(magic, size = 2048) {
  const bytes = new Uint8Array(size);
  for (let i = 0; i < size; i++) bytes[i] = (i * 31 + 7) % 256;
  bytes.set(Buffer.from(magic), 0);
  return bytes;
}

/**
 * Compare deux suites d'octets.
 *
 * @param {Uint8Array} a Première.
 * @param {Uint8Array} b Seconde.
 * @return {boolean} Vrai si identiques.
 */
function sameBytes(a, b) {
  return Buffer.from(a).equals(Buffer.from(b));
}

/**
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "storage.rules"), "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
  await env.clearFirestore();
  await env.clearStorage();

  const admin = getFirestore();
  const ctx = (uid) => env.authenticatedContext(uid);
  const fsOf = (uid) => ctx(uid).firestore();
  const stOf = (uid) => ctx(uid).storage();

  await env.withSecurityRulesDisabled(async (c) => {
    const names = {[ALICE]: "Alice", [BOB]: "Bob", [CAROLE]: "Carole"};
    for (const [uid, displayName] of Object.entries(names)) {
      await setDoc(doc(c.firestore(), "users", uid), {
        displayName,
        accountType: "personal",
        verified: false,
        followersCount: 0,
        followingCount: 0,
      });
    }
  });

  /**
   * Envoie un message comme ChatService.sendMessage : le message, puis
   * l'aperçu et le badge de la conversation. Exécute ensuite le trigger.
   *
   * @param {string} from Expéditeur.
   * @param {string} to Destinataire.
   * @param {string} id Id du message.
   * @param {object} fields Type, contenu, nom de fichier…
   * @param {string} preview Aperçu de la liste des conversations.
   * @return {Promise<object>} Le message écrit.
   */
  async function send(from, to, id, fields, preview) {
    const conv = [from, to].sort().join("_");
    const db = fsOf(from);
    const msg = {
      senderUid: from,
      createdAt: Timestamp.now(),
      ...fields,
    };
    await setDoc(doc(db, "conversations", conv, "messages", id), msg);
    await setDoc(doc(db, "conversations", conv), {
      lastMessage: preview,
      lastMessageType: fields.type,
      lastMessageAt: Timestamp.now(),
      lastMessageSenderUid: from,
    }, {merge: true});
    await onMessageCreated.run({
      params: {conversationId: conv, messageId: id},
      data: {id, data: () => msg},
    });
    return msg;
  }

  /**
   * Dernière notification reçue par `uid`.
   *
   * @param {string} uid Destinataire.
   * @return {Promise<object|undefined>} Ses champs.
   */
  async function lastNotification(uid) {
    const snap = await admin.collection(`users/${uid}/notifications`)
        .orderBy("createdAt", "desc").limit(1).get();
    return snap.docs[0]?.data();
  }

  /**
   * Monte un fichier comme ChatService.upload* et rend son URL.
   *
   * @param {string} uid Qui envoie.
   * @param {string} storagePath Chemin sous `chat/`.
   * @param {Uint8Array} bytes Contenu.
   * @param {object} metadata Type, disposition…
   * @return {Promise<string>} URL de téléchargement.
   */
  async function upload(uid, storagePath, bytes, metadata) {
    const r = ref(stOf(uid), storagePath);
    await uploadBytes(r, bytes, metadata);
    return getDownloadURL(r);
  }

  /**
   * Ce que Bob vérifie à la réception d'un fichier : le message est
   * lisible, l'URL renvoie les mêmes octets avec le bon type, et Carole
   * n'a accès à rien.
   *
   * @param {string} id Id du message.
   * @param {string} storagePath Chemin du fichier.
   * @param {Uint8Array} bytes Octets envoyés.
   * @param {string} contentType Type attendu.
   * @return {Promise<object>} Le message relu par Bob.
   */
  async function receiveFile(id, storagePath, bytes, contentType) {
    const snap = await getDoc(doc(fsOf(BOB), "conversations", CONV,
        "messages", id));
    assert(snap.exists(), "Bob ne lit pas le message");
    const msg = snap.data();
    const res = await fetch(msg.content);
    assert(res.ok, `téléchargement par URL refusé (${res.status})`);
    const got = new Uint8Array(await res.arrayBuffer());
    assert(sameBytes(got, bytes), "octets reçus différents des octets envoyés");
    const type = res.headers.get("content-type") || "";
    assert(type.startsWith(contentType),
        `type servi « ${type} » au lieu de « ${contentType} »`);
    const viaSdk = new Uint8Array(await getBytes(ref(stOf(BOB), storagePath)));
    assert(sameBytes(viaSdk, bytes), "lecture SDK de Bob différente");
    await assertFails(getBytes(ref(stOf(CAROLE), storagePath)));
    await assertFails(getDoc(doc(fsOf(CAROLE), "conversations", CONV,
        "messages", id)));
    return msg;
  }

  console.log("Discussion — envoi et réception");

  // --- Premier message, avant que la conversation existe --------------------
  await check("premier message avant la conversation : Bob est notifié",
      async () => {
        await setDoc(doc(fsOf(ALICE), "conversations", CONV, "messages", "t0"), {
          senderUid: ALICE, type: "text", content: "Salut Bob",
          createdAt: Timestamp.now(),
        });
        await onMessageCreated.run({
          params: {conversationId: CONV, messageId: "t0"},
          data: {id: "t0", data: () => ({
            senderUid: ALICE, type: "text", content: "Salut Bob"})},
        });
        const n = await lastNotification(BOB);
        assert(n && n.title === "Alice" && n.body === "Salut Bob",
            `notification inattendue : ${JSON.stringify(n)}`);
        assert(n.data.conversationId === CONV, "conversation absente du push");
      });

  // Le serveur a créé la conversation pour ce premier message : l'app la
  // trouve (getOrCreateConversation lit avant de créer).
  await check("la conversation existe, badge de Bob à 1", async () => {
    const conv = await getDoc(doc(fsOf(ALICE), "conversations", CONV));
    assert(conv.exists(), "conversation non créée par le serveur");
    assert(conv.data().participants.includes(BOB), "participants");
    assert(conv.data().unreadCounts[BOB] === 1,
        `badge ${conv.data().unreadCounts[BOB]}`);
  });

  // --- Texte ----------------------------------------------------------------
  await check("texte : envoyé, reçu, notifié, compté non lu", async () => {
    await send(ALICE, BOB, "t1", {type: "text", content: "Ça va ?"}, "Ça va ?");
    const got = (await getDoc(doc(fsOf(BOB), "conversations", CONV,
        "messages", "t1"))).data();
    assert(got.content === "Ça va ?", "contenu altéré");
    assert((await lastNotification(BOB)).body === "Ça va ?", "push texte");
    const conv = (await getDoc(doc(fsOf(BOB), "conversations", CONV))).data();
    assert(conv.unreadCounts[BOB] === 2, `badge ${conv.unreadCounts[BOB]}`);
    assert(!conv.unreadCounts[ALICE], "l'expéditrice ne se compte pas");
    assert(conv.lastMessage === "Ça va ?", "aperçu de la liste");
  });

  // --- Photo ----------------------------------------------------------------
  const png = fakeFile("\x89PNG", 4096);
  const pngPath = `chat/${CONV}/images/p1.png`;
  await check("photo PNG : octets et type intacts à l'arrivée", async () => {
    const url = await upload(ALICE, pngPath, png, {contentType: "image/png"});
    await send(ALICE, BOB, "i1", {type: "image", content: url}, "📷 Photo");
    await receiveFile("i1", pngPath, png, "image/png");
    assert((await lastNotification(BOB)).body === "📷 Photo", "push photo");
  });

  // --- Vidéo + vignette -----------------------------------------------------
  const mp4 = fakeFile("\0\0\0\x18ftypmp42", 300 * 1024);
  const jpg = fakeFile("\xff\xd8\xff", 2048);
  const mp4Path = `chat/${CONV}/videos/v1.mp4`;
  const thumbPath = `chat/${CONV}/videos/v1_thumb.jpg`;
  let videoMsg;
  await check("vidéo : fichier, vignette et durée reçus", async () => {
    const url = await upload(ALICE, mp4Path, mp4, {contentType: "video/mp4"});
    const thumbUrl = await upload(ALICE, thumbPath, jpg,
        {contentType: "image/jpeg"});
    await send(ALICE, BOB, "v1", {
      type: "video", content: url, thumbUrl, durationMs: 42000,
    }, "🎥 Vidéo");
    videoMsg = await receiveFile("v1", mp4Path, mp4, "video/mp4");
    assert(videoMsg.durationMs === 42000, "durée perdue");
    const thumb = await fetch(videoMsg.thumbUrl);
    assert(thumb.ok && sameBytes(
        new Uint8Array(await thumb.arrayBuffer()), jpg), "vignette illisible");
    assert((await lastNotification(BOB)).body === "🎥 Vidéo", "push vidéo");
  });

  // --- Vocal ----------------------------------------------------------------
  const m4a = fakeFile("\0\0\0\x20ftypM4A ", 16 * 1024);
  const m4aPath = `chat/${CONV}/voice/a1.m4a`;
  await check("vocal : lisible en flux (audio/mp4), durée reçue", async () => {
    const url = await upload(ALICE, m4aPath, m4a, {contentType: "audio/mp4"});
    await send(ALICE, BOB, "a1", {
      type: "voice", content: url, durationMs: 7000,
    }, "🎤 Message vocal");
    const got = await receiveFile("a1", m4aPath, m4a, "audio/mp4");
    assert(got.durationMs === 7000, "durée perdue");
    assert((await lastNotification(BOB)).body === "🎤 Message vocal",
        "push vocal");
  });

  // --- Document PDF ---------------------------------------------------------
  const pdf = fakeFile("%PDF-1.7\n", 64 * 1024);
  const pdfName = "Facture mars #2.pdf";
  const pdfPath = `chat/${CONV}/docs/d1_Facture_mars_2.pdf`;
  await check("PDF : reçu comme PDF, sous son nom d'origine", async () => {
    const url = await upload(ALICE, pdfPath, pdf, {
      contentType: "application/pdf",
      contentDisposition: "inline; filename=\"Facture_mars_2.pdf\"; " +
        "filename*=UTF-8''Facture%20mars%20%232.pdf",
    });
    await send(ALICE, BOB, "d1", {
      type: "document", content: url, fileName: pdfName,
    }, `📎 ${pdfName}`);
    const got = await receiveFile("d1", pdfPath, pdf, "application/pdf");
    assert(got.fileName === pdfName, "nom d'origine perdu");
    const res = await fetch(got.content);
    const disposition = res.headers.get("content-disposition") || "";
    assert(disposition.includes("Facture"),
        `nom absent du téléchargement : « ${disposition} »`);
    assert((await lastNotification(BOB)).body === `📎 ${pdfName}`,
        "push document");
    const conv = (await getDoc(doc(fsOf(BOB), "conversations", CONV))).data();
    assert(conv.lastMessage === `📎 ${pdfName}`, "aperçu document");
  });

  // --- Sticker et réponse ---------------------------------------------------
  await check("sticker : l'emoji est le message et la notification",
      async () => {
        await send(ALICE, BOB, "s1", {type: "sticker", content: "🎉"}, "🎉");
        assert((await lastNotification(BOB)).body === "🎉", "push sticker");
      });

  await check("réponse de Bob : citation relue par Alice, Alice notifiée",
      async () => {
        await send(BOB, ALICE, "r1", {
          type: "text", content: "Oui très bien",
          replyTo: {id: "t1", senderUid: ALICE, text: "Ça va ?"},
        }, "Oui très bien");
        const got = (await getDoc(doc(fsOf(ALICE), "conversations", CONV,
            "messages", "r1"))).data();
        assert(got.replyTo.id === "t1" && got.replyTo.text === "Ça va ?",
            "citation perdue");
        const n = await lastNotification(ALICE);
        assert(n.title === "Bob" && n.body === "Oui très bien", "push réponse");
      });

  // --- Liste des conversations ----------------------------------------------
  await check("la conversation apparaît dans la liste de Bob", async () => {
    const snap = await getDocs(query(collection(fsOf(BOB), "conversations"),
        where("participants", "array-contains", BOB)));
    assert(snap.docs.some((d) => d.id === CONV), "conversation absente");
  });

  // --- Badge non lu : le serveur seul compte ---------------------------------
  await check("Alice ne gonfle pas le badge de Bob", async () => {
    const c = doc(fsOf(ALICE), "conversations", CONV);
    await assertFails(updateDoc(c, {[`unreadCounts.${BOB}`]: increment(5)}));
    await assertFails(updateDoc(c, {[`unreadCounts.${BOB}`]: 0}));
    await assertFails(setDoc(c, {lastMessage: "…",
      unreadCounts: {[BOB]: increment(1)}}, {merge: true}));
  });

  await check("Bob ne s'invente pas de non-lus", async () => {
    await assertFails(updateDoc(doc(fsOf(BOB), "conversations", CONV),
        {[`unreadCounts.${BOB}`]: 42}));
  });

  await check("l'aperçu reste écrit par l'app de l'expéditrice", async () => {
    await assertSucceeds(setDoc(doc(fsOf(ALICE), "conversations", CONV), {
      lastMessage: "…", lastMessageSenderUid: ALICE,
    }, {merge: true}));
  });

  await check("un message déjà lu à l'arrivée du trigger n'est pas compté",
      async () => {
        await updateDoc(doc(fsOf(BOB), "conversations", CONV),
            {[`unreadCounts.${BOB}`]: 0});
        // Bob, discussion ouverte, lit le message avant que le trigger ne
        // passe.
        await setDoc(doc(fsOf(ALICE), "conversations", CONV, "messages",
            "vu"), {senderUid: ALICE, type: "text", content: "Tu es là ?",
          createdAt: Timestamp.now()});
        await updateDoc(doc(fsOf(BOB), "conversations", CONV, "messages",
            "vu"), {readAt: serverTimestamp()});
        await onMessageCreated.run({
          params: {conversationId: CONV, messageId: "vu"},
          data: {id: "vu", data: () => ({senderUid: ALICE, type: "text",
            content: "Tu es là ?"})},
        });
        const conv = (await getDoc(doc(fsOf(BOB), "conversations",
            CONV))).data();
        assert(conv.unreadCounts[BOB] === 0,
            `badge ${conv.unreadCounts[BOB]} au lieu de 0`);
      });

  // --- Après réception ------------------------------------------------------
  await check("Bob marque lu et remet son badge à zéro", async () => {
    await assertSucceeds(updateDoc(doc(fsOf(BOB), "conversations", CONV,
        "messages", "t1"), {readAt: serverTimestamp()}));
    await assertSucceeds(updateDoc(doc(fsOf(BOB), "conversations", CONV),
        {[`unreadCounts.${BOB}`]: 0}));
  });

  await check("Bob réagit, mais pas au nom d'Alice", async () => {
    const m = doc(fsOf(BOB), "conversations", CONV, "messages", "i1");
    await assertSucceeds(updateDoc(m, {[`reactions.${BOB}`]: "❤️"}));
    await assertFails(updateDoc(m, {[`reactions.${ALICE}`]: "😡"}));
  });

  await check("Bob ne réécrit pas un message d'Alice", async () => {
    await assertFails(updateDoc(doc(fsOf(BOB), "conversations", CONV,
        "messages", "t1"), {content: "falsifié"}));
  });

  await check("Bob supprime « pour moi » sans toucher Alice", async () => {
    await assertSucceeds(updateDoc(doc(fsOf(BOB), "conversations", CONV,
        "messages", "s1"), {hiddenFor: arrayUnion(BOB)}));
    const forAlice = (await getDoc(doc(fsOf(ALICE), "conversations", CONV,
        "messages", "s1"))).data();
    assert(forAlice.content === "🎉", "le message a disparu chez Alice");
  });

  // --- Vue unique -----------------------------------------------------------
  const secretPath = `chat/${CONV}/images/once.jpg`;
  await check("vue unique : contenu caché du push, ouvert une seule fois",
      async () => {
        const url = await upload(ALICE, secretPath, jpg,
            {contentType: "image/jpeg"});
        await send(ALICE, BOB, "o1", {
          type: "image", content: url, viewOnce: true,
        }, "👁 Photo · vue unique");
        assert((await lastNotification(BOB)).body === "👁 Photo · vue unique",
            "le push trahit le contenu");
        const consume = {
          viewOnceOpenedAt: serverTimestamp(),
          content: "",
          thumbUrl: deleteField(),
        };
        const m = (uid) => doc(fsOf(uid), "conversations", CONV,
            "messages", "o1");
        await assertFails(updateDoc(m(ALICE), consume));
        await assertSucceeds(updateDoc(m(BOB), consume));
        await assertFails(updateDoc(m(BOB), consume));
        await assertSucceeds(deleteObject(ref(stOf(BOB), secretPath)));
      });

  // --- Suppression pour tous ------------------------------------------------
  await check("Alice retire son PDF : fichier et contenu partis", async () => {
    await assertFails(updateDoc(doc(fsOf(BOB), "conversations", CONV,
        "messages", "d1"), {deleted: true, content: ""}));
    await assertSucceeds(deleteObject(ref(stOf(ALICE), pdfPath)));
    await assertSucceeds(updateDoc(doc(fsOf(ALICE), "conversations", CONV,
        "messages", "d1"), {
      deleted: true, content: "", fileName: deleteField(),
      durationMs: deleteField(), thumbUrl: deleteField(), reactions: {},
    }));
    let gone = false;
    try {
      await getBytes(ref(stOf(BOB), pdfPath));
    } catch (err) {
      gone = err.code === "storage/object-not-found";
    }
    assert(gone, "le fichier est toujours téléchargeable");
  });

  // --- Transfert ------------------------------------------------------------
  await check("transfert de la vidéo à Carole : lisible avec sa vignette",
      async () => {
        const conv2 = [ALICE, CAROLE].sort().join("_");
        await setDoc(doc(fsOf(ALICE), "conversations", conv2), {
          participants: [ALICE, CAROLE],
          lastMessageAt: serverTimestamp(),
          createdAt: serverTimestamp(),
        });
        await send(ALICE, CAROLE, "f1", {
          type: "video", content: videoMsg.content,
          thumbUrl: videoMsg.thumbUrl, durationMs: videoMsg.durationMs,
        }, "🎥 Vidéo");
        const got = (await getDoc(doc(fsOf(CAROLE), "conversations", conv2,
            "messages", "f1"))).data();
        const res = await fetch(got.content);
        assert(res.ok && sameBytes(new Uint8Array(await res.arrayBuffer()),
            mp4), "vidéo transférée illisible");
        assert(got.thumbUrl, "vignette perdue au transfert");
      });

  // --- Plafonds et intrus ---------------------------------------------------
  await check("document de 21 Mo refusé, vidéo de 25 Mo acceptée",
      async () => {
        await assertFails(uploadBytes(
            ref(stOf(ALICE), `chat/${CONV}/docs/gros.pdf`),
            new Uint8Array(21 * 1024 * 1024), {contentType: "application/pdf"}));
        await assertSucceeds(uploadBytes(
            ref(stOf(ALICE), `chat/${CONV}/videos/longue.mp4`),
            new Uint8Array(25 * 1024 * 1024), {contentType: "video/mp4"}));
      });

  await check("une « photo » de 25 Mo est refusée", async () => {
    await assertFails(uploadBytes(
        ref(stOf(ALICE), `chat/${CONV}/images/fausse.jpg`),
        new Uint8Array(25 * 1024 * 1024), {contentType: "image/jpeg"}));
  });

  await check("Carole ne dépose rien dans la conversation des autres",
      async () => {
        await assertFails(uploadBytes(
            ref(stOf(CAROLE), `chat/${CONV}/docs/intrus.pdf`),
            pdf, {contentType: "application/pdf"}));
        await assertFails(setDoc(doc(fsOf(CAROLE), "conversations", CONV,
            "messages", "x1"), {senderUid: CAROLE, type: "text",
          content: "coucou", createdAt: Timestamp.now()}));
      });

  await check("personne n'écrit au nom d'un autre", async () => {
    await assertFails(setDoc(doc(fsOf(BOB), "conversations", CONV,
        "messages", "x2"), {senderUid: ALICE, type: "text",
      content: "c'est moi Alice", createdAt: Timestamp.now()}));
  });

  // --- Blocage --------------------------------------------------------------
  await check("après un blocage, plus aucun message dans aucun sens",
      async () => {
        await env.withSecurityRulesDisabled(async (c) => {
          await setDoc(doc(c.firestore(), "users", BOB, "blocked", ALICE), {});
          await setDoc(doc(c.firestore(), "users", ALICE, "blockedBy", BOB), {});
        });
        for (const [from, id] of [[ALICE, "b1"], [BOB, "b2"]]) {
          await assertFails(setDoc(doc(fsOf(from), "conversations", CONV,
              "messages", id), {senderUid: from, type: "text",
            content: "…", createdAt: Timestamp.now()}));
        }
      });

  await env.cleanup();
  console.log(failures === 0 ?
    "\nEnvoi et réception conformes pour tous les types." :
    `\n${failures} cas en échec.`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
