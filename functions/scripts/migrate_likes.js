/**
 * Migration des « j'aime » : `posts/{id}.likedBy[]` → `posts/{id}/likes/{uid}`.
 *
 * Le tableau `likedBy` vivait dans le document du post. Il était réécrit en
 * entier à chaque like, ce qui plafonnait avec la taille du document (1 Mio)
 * et sérialisait tous les likes d'un post sur une seule écriture. Chaque like
 * devient donc un document à part, plus son miroir personnel
 * `users/{uid}/likes/{postId}` (qui permet de charger « ce que j'ai aimé » en
 * une requête, sans lire un document par post affiché).
 *
 * Pour chaque post portant encore un `likedBy` :
 *   - crée `posts/{id}/likes/{uid}` et `users/{uid}/likes/{id}` par uid,
 *   - réaligne `likesCount` sur le nombre réel de likes,
 *   - supprime le champ `likedBy`.
 *
 * Le script est **idempotent** : relançable sans risque, il ignore les posts
 * déjà migrés et n'écrase pas la date d'un like déjà transféré.
 *
 * Utilisation (depuis `functions/`) :
 *
 *   # ce qui serait fait, sans rien écrire
 *   node scripts/migrate_likes.js --dry-run
 *
 *   # la migration elle-même
 *   node scripts/migrate_likes.js
 *
 *   # réaligne `likesCount` sur les likes réellement présents, sans migrer
 *   # (le compteur est incrémental côté client : ce mode répare une dérive)
 *   node scripts/migrate_likes.js --recount
 *
 * Authentification : identifiants par défaut de l'application. Soit
 *   gcloud auth application-default login
 * soit GOOGLE_APPLICATION_CREDENTIALS pointant sur une clé de compte de
 * service. Le projet vient de --project, GCLOUD_PROJECT ou de la clé.
 */

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const RECOUNT = args.includes("--recount");
const projectArg = args.find((a) => a.startsWith("--project="));
const projectId = projectArg ?
  projectArg.split("=")[1] :
  process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;

// Sous émulateur (FIRESTORE_EMULATOR_HOST), aucune authentification n'est
// requise : demander les identifiants par défaut ne ferait qu'échouer
// bruyamment contre le serveur de métadonnées.
initializeApp(
    process.env.FIRESTORE_EMULATOR_HOST ?
      {projectId} :
      {credential: applicationDefault(), projectId},
);
const db = getFirestore();

/** Taille des pages de posts parcourues. */
const PAGE = 200;
/** Un lot d'écritures Firestore plafonne à 500 opérations. */
const BATCH_LIMIT = 500;

/**
 * Compte les likes réellement présents dans la sous-collection d'un post.
 *
 * @param {string} postId Publication à compter.
 * @return {Promise<number>} Nombre de documents de like.
 */
async function countLikes(postId) {
  const agg = await db.collection(`posts/${postId}/likes`).count().get();
  return agg.data().count;
}

/**
 * Migre un post : un document de like par uid, plus le miroir personnel.
 *
 * @param {FirebaseFirestore.QueryDocumentSnapshot} doc Post à migrer.
 * @return {Promise<{likes: number, skipped: number}>} Ce qui a été écrit.
 */
async function migratePost(doc) {
  const postId = doc.id;
  const likedBy = Array.isArray(doc.get("likedBy")) ? doc.get("likedBy") : [];
  // Dédoublonne : rien n'empêchait un même uid d'apparaître deux fois dans
  // le tableau, et c'est précisément ce qui faussait les compteurs.
  const uids = [...new Set(likedBy.filter((u) => typeof u === "string" && u))];

  // Ce qui a déjà été transféré lors d'un passage précédent.
  const existing = new Set(
      (await db.collection(`posts/${postId}/likes`).get()).docs.map((d) => d.id),
  );
  const toWrite = uids.filter((uid) => !existing.has(uid));

  if (DRY_RUN) {
    console.log(
        `  ${postId} : ${toWrite.length} like(s) à créer, ` +
      `${uids.length - toWrite.length} déjà en place, ` +
      `likesCount → ${uids.length}`,
    );
    return {likes: toWrite.length, skipped: uids.length - toWrite.length};
  }

  // `likedAt` reprend la date de publication : l'instant du like n'a jamais
  // été conservé, et une date plausible vaut mieux que « maintenant », qui
  // ferait remonter d'anciens likes en tête du miroir personnel.
  const likedAt = doc.get("publishedAt") || FieldValue.serverTimestamp();

  for (let i = 0; i < toWrite.length; i += BATCH_LIMIT / 2) {
    const chunk = toWrite.slice(i, i + BATCH_LIMIT / 2);
    const batch = db.batch();
    for (const uid of chunk) {
      batch.set(db.doc(`posts/${postId}/likes/${uid}`), {uid, likedAt});
      batch.set(db.doc(`users/${uid}/likes/${postId}`), {postId, likedAt});
    }
    await batch.commit();
  }

  await doc.ref.update({
    likesCount: uids.length,
    likedBy: FieldValue.delete(),
  });

  return {likes: toWrite.length, skipped: uids.length - toWrite.length};
}

/**
 * Réaligne `likesCount` sur les likes réellement présents.
 *
 * @param {FirebaseFirestore.QueryDocumentSnapshot} doc Post à recompter.
 * @return {Promise<boolean>} Vrai si le compteur était faux.
 */
async function recountPost(doc) {
  const actual = await countLikes(doc.id);
  const stored = doc.get("likesCount") || 0;
  if (actual === stored) return false;
  console.log(`  ${doc.id} : likesCount ${stored} → ${actual}`);
  if (!DRY_RUN) await doc.ref.update({likesCount: actual});
  return true;
}

/**
 * Parcourt tous les posts par pages et applique le traitement demandé.
 *
 * @return {Promise<void>} Résolue en fin de parcours.
 */
async function run() {
  const mode = RECOUNT ? "recomptage" : "migration";
  console.log(
      `${mode}${DRY_RUN ? " (essai à blanc, aucune écriture)" : ""}` +
    `${projectId ? ` — projet ${projectId}` : ""}`,
  );

  let cursor = null;
  let posts = 0;
  let migrated = 0;
  let likes = 0;
  let fixed = 0;

  for (;;) {
    let query = db
        .collection("posts")
        .orderBy("__name__")
        .limit(PAGE);
    if (cursor) query = query.startAfter(cursor);

    const snap = await query.get();
    if (snap.empty) break;
    cursor = snap.docs[snap.docs.length - 1];
    posts += snap.size;

    for (const doc of snap.docs) {
      if (RECOUNT) {
        if (await recountPost(doc)) fixed++;
        continue;
      }
      // Un post sans `likedBy` est déjà migré (ou n'a jamais eu de like).
      if (doc.get("likedBy") === undefined) continue;
      const result = await migratePost(doc);
      migrated++;
      likes += result.likes;
    }

    if (snap.size < PAGE) break;
  }

  if (RECOUNT) {
    console.log(`${posts} post(s) parcouru(s), ${fixed} compteur(s) corrigé(s)`);
  } else {
    console.log(
        `${posts} post(s) parcouru(s), ${migrated} migré(s), ` +
      `${likes} like(s) transféré(s)`,
    );
  }
}

run().then(
    () => process.exit(0),
    (err) => {
      console.error("Migration interrompue :", err);
      process.exit(1);
    },
);
