/**
 * Tendances de recherche.
 *
 * Chaque recherche « aboutie » (validée, ou dont on a ouvert un résultat)
 * est comptée ici, côté serveur : le client ne peut pas gonfler une
 * tendance. Un compte ne compte qu'**une fois par jour** pour une même
 * recherche, et les mots grossiers ne deviennent jamais des tendances.
 *
 * Document `searchTrends/{clé}` :
 * - `query`    : la recherche telle qu'affichée (« acte de naissance ») ;
 * - `count`    : nombre de recherches comptées (un compte, un jour) ;
 * - `hot`      : score de tendance qui décroît avec le temps (voir
 *                [mergeHot]) — c'est l'ordre d'affichage ;
 * - `prefixes` : débuts de mots, pour les suggestions pendant la frappe ;
 * - `hidden`   : `true` pour retirer une tendance à la main (modération).
 */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {normalize, searchPrefixes} = require("./search_index");

/** Demi-vie d'une recherche : au bout de 3 jours, elle pèse moitié moins. */
const HALF_LIFE_MS = 3 * 24 * 3600 * 1000;
const MAX_LENGTH = 40;
const MAX_WORDS = 5;

/**
 * Mots qui ne doivent jamais s'afficher en tendance, sous forme
 * normalisée (minuscules, sans accents). La modération peut en plus
 * masquer n'importe quelle tendance (`hidden: true`).
 */
const BLOCKED = new Set([
  "pute", "putain", "salope", "salopes", "connard", "connasse", "encule",
  "enculer", "batard", "nique", "niquer", "ntm", "fdp", "pd", "tapette",
  "sexe", "sex", "porno", "porn", "xxx", "nude", "nudes", "bite", "chatte",
  "couille", "couilles", "merde", "suce", "sucer", "baise", "baiser",
]);

/**
 * La clé d'une recherche (identifiant du document) et son affichage, ou
 * `null` si elle ne doit pas être comptée.
 * @param {unknown} raw
 * @return {{key: string, display: string} | null}
 */
function trendKey(raw) {
  if (typeof raw !== "string") return null;
  const display = raw.trim().replace(/\s+/g, " ").toLowerCase();
  if (display.length < 2 || display.length > MAX_LENGTH) return null;
  const words = normalize(display).split(/[^a-z0-9]+/).filter(Boolean);
  if (!words.length || words.length > MAX_WORDS) return null;
  // Au moins une lettre : « 12345 » n'est pas une tendance.
  if (!words.some((w) => /[a-z]/.test(w))) return null;
  if (words.some((w) => BLOCKED.has(w))) return null;
  const key = words.join(" ");
  if (key.length < 2) return null;
  return {key, display};
}

/**
 * Ajoute une recherche faite à l'instant `nowMs` à un score de tendance.
 *
 * Le score est log₂(Σ 2^(tᵢ / demi-vie)) : chaque recherche pèse 2 fois
 * moins tous les 3 jours, et comparer deux scores revient à comparer les
 * popularités récentes, sans jamais devoir recalculer les anciennes
 * tendances. Gardé en logarithme pour ne pas déborder.
 * @param {number|undefined} hot
 * @param {number} nowMs
 * @return {number}
 */
function mergeHot(hot, nowMs) {
  const t = nowMs / HALF_LIFE_MS;
  if (typeof hot !== "number" || !Number.isFinite(hot)) return t;
  const m = Math.max(hot, t);
  return m + Math.log2(Math.pow(2, hot - m) + Math.pow(2, t - m));
}

/**
 * Jour courant (UTC), pour ne compter qu'une recherche par compte et par
 * jour.
 * @param {number} nowMs
 * @return {string}
 */
function dayOf(nowMs) {
  return new Date(nowMs).toISOString().slice(0, 10);
}

const recordSearch = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  const parsed = trendKey(request.data && request.data.query);
  if (!parsed) return {counted: false};

  const db = getFirestore();
  const now = Date.now();
  const day = dayOf(now);
  const trendRef = db.collection("searchTrends").doc(parsed.key);
  const hitRef = trendRef.collection("hits").doc(uid);

  const counted = await db.runTransaction(async (tx) => {
    const [hit, trend] = await Promise.all([tx.get(hitRef), tx.get(trendRef)]);
    if (hit.exists && hit.get("day") === day) return false;

    tx.set(hitRef, {day, at: FieldValue.serverTimestamp()});
    if (trend.exists) {
      tx.update(trendRef, {
        count: FieldValue.increment(1),
        hot: mergeHot(trend.get("hot"), now),
        lastAt: FieldValue.serverTimestamp(),
      });
    } else {
      tx.set(trendRef, {
        query: parsed.display,
        count: 1,
        hot: mergeHot(undefined, now),
        prefixes: searchPrefixes(parsed.display),
        hidden: false,
        createdAt: FieldValue.serverTimestamp(),
        lastAt: FieldValue.serverTimestamp(),
      });
    }
    return true;
  });
  return {counted};
});

module.exports = {trendKey, mergeHot, dayOf, HALF_LIFE_MS, recordSearch};
