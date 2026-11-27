/**
 * Index de recherche — profils, publications, annonces.
 *
 * Firestore ne sait pas chercher dans du texte. Chaque document indexé
 * reçoit donc un champ `search` : la liste des **débuts de mots** de ses
 * textes, normalisés (minuscules, sans accents). Taper « abd » trouve
 * « Abdel », « mar » trouve « marché » et « Mairie »… par une simple
 * requête `array-contains`, sans service externe.
 *
 * La normalisation doit rester **identique** à `lib/models/search_text.dart`
 * (`searchPrefixesOf` / `searchQueryTokens`) : une divergence rendrait des
 * documents introuvables sans rien signaler.
 */

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {getFirestore} = require("firebase-admin/firestore");

/** Plus court début de mot indexé (une seule lettre ramènerait tout). */
const MIN_PREFIX = 2;

/** Au-delà, un début de mot est assez précis pour retrouver le document. */
const MAX_PREFIX = 15;

/** Nombre de mots distincts indexés par document. */
const MAX_WORDS = 60;

/**
 * Minuscules sans accents ni diacritiques.
 * @param {string} input
 * @return {string}
 */
function normalize(input) {
  return String(input || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/œ/g, "oe")
    .replace(/æ/g, "ae");
}

/**
 * Mots normalisés, dans l'ordre, sans doublons.
 * @param {string} text
 * @return {string[]}
 */
function words(text) {
  const seen = new Set();
  for (const w of normalize(text).split(/[^a-z0-9]+/)) {
    if (w) seen.add(w);
  }
  return [...seen];
}

/**
 * Débuts de mots indexés pour une liste de textes. Le premier texte est
 * prioritaire (nom, titre) : ses mots passent avant ceux du corps quand
 * on atteint la limite.
 * @param {...string} texts
 * @return {string[]}
 */
function searchPrefixes(...texts) {
  const out = new Set();
  let count = 0;
  for (const text of texts) {
    for (const w of words(text)) {
      if (count++ >= MAX_WORDS) return [...out];
      // Un mot d'une lettre ou un nombre court (« 2 », « 15 ») reste
      // indexé tel quel : « Studio 2 pièces » doit répondre à « 2 ».
      if (w.length < MIN_PREFIX) {
        if (/^[0-9]$/.test(w)) out.add(w);
        continue;
      }
      for (let n = MIN_PREFIX; n <= Math.min(w.length, MAX_PREFIX); n++) {
        out.add(w.slice(0, n));
      }
    }
  }
  return [...out];
}

/** Textes indexés par collection. */
const SOURCES = {
  users: (d) => [d.displayName],
  posts: (d) => [
    `${d.title || ""} ${d.authorName || ""}`,
    d.body,
    d.repostOfAuthorName,
    // Une publication vidéo répond à « vidéo » : c'est ainsi qu'on
    // retrouve les vidéos par la recherche, même sans légende.
    d.videoUrl || (Array.isArray(d.videos) && d.videos.length) ?
      "video videos" : "",
  ],
  market: (d) => [d.title, d.description, d.location, d.sellerName],
};

/**
 * Valeur attendue du champ `search` pour un document.
 * @param {string} collection
 * @param {object} data
 * @return {string[]}
 */
function expectedIndex(collection, data) {
  return searchPrefixes(...SOURCES[collection](data).map((t) => t || ""));
}

/**
 * @param {string[]|undefined} a
 * @param {string[]} b
 * @return {boolean}
 */
function sameList(a, b) {
  if (!Array.isArray(a) || a.length !== b.length) return false;
  return a.every((v, i) => v === b[i]);
}

/**
 * Trigger qui tient `search` à jour. Ne réécrit que si l'index change :
 * sa propre écriture redéclenche le trigger, qui s'arrête là ; et un
 * simple « j'aime » ne coûte qu'une lecture du document déjà fourni.
 * @param {string} collection
 * @return {Function}
 */
function indexer(collection) {
  return onDocumentWritten(`${collection}/{id}`, async (event) => {
    const after = event.data && event.data.after;
    if (!after || !after.exists) return;
    const data = after.data();
    const index = expectedIndex(collection, data);
    if (sameList(data.search, index)) return;
    await after.ref.update({search: index});
  });
}

/**
 * Réindexe une collection entière (première mise en place).
 * @param {string} collection
 * @return {Promise<number>} documents réécrits
 */
async function backfill(collection) {
  const db = getFirestore();
  const snap = await db.collection(collection).get();
  let writer = db.bulkWriter();
  let changed = 0;
  for (const doc of snap.docs) {
    const index = expectedIndex(collection, doc.data());
    if (sameList(doc.data().search, index)) continue;
    writer.update(doc.ref, {search: index});
    changed++;
  }
  await writer.close();
  writer = null;
  return changed;
}

module.exports = {
  normalize,
  searchPrefixes,
  expectedIndex,
  backfill,
  indexUser: indexer("users"),
  indexPost: indexer("posts"),
  indexMarket: indexer("market"),
};
