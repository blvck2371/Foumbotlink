/**
 * Rattrapage des annonces au modèle « annonce qui vit et qui expire ».
 *
 * Module à part, et non une fonction de plus dans `index.js`, pour trois
 * raisons : le déclencheur de création s'en sert (pour les annonces
 * venues d'une version trop ancienne de l'app), la réparation planifiée
 * s'en sert (pour celles publiées avant ce changement de modèle), et il
 * peut être chargé seul dans un test — sans initialiser d'application
 * Firebase ni enregistrer de fonction.
 */

const {FieldValue, Timestamp} = require("firebase-admin/firestore");

/** Durée de vie d'une annonce — aligné sur `kListingLifetime` côté Dart. */
const LISTING_LIFETIME_MS = 60 * 24 * 60 * 60 * 1000;

/**
 * Jetons de recherche d'une annonce.
 *
 * ⚠️ Doit produire exactement les mêmes jetons que `marketKeywords` dans
 * `lib/models/market_text.dart` : ceux écrits à la publication sont ceux
 * que la recherche interroge, et une divergence rendrait silencieusement
 * des annonces introuvables. Les deux implémentations sont couvertes par
 * des tests qui vérifient la même sortie sur les mêmes entrées
 * (`test/market_text_test.dart` et `scripts/test_backfill_market.js`).
 *
 * @param {string} title Titre de l'annonce.
 * @param {string} description Description de l'annonce.
 * @return {string[]} Jetons normalisés, sans doublon, 40 au plus.
 */
function marketKeywords(title, description) {
  const source = `${title || ""} ${description || ""}`
      .toLowerCase()
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "");
  const words = source.split(/[^a-z0-9]+/).filter((w) => w.length >= 3);
  return [...new Set(words)].slice(0, 40);
}

/**
 * Ce qu'il manque à une annonce pour exister dans la grille.
 *
 * Séparé de l'écriture pour être vérifiable sans base : c'est ici que se
 * décide quels champs sont posés et lesquels sont laissés tels quels.
 *
 * @param {object} data Contenu actuel du document.
 * @return {{update: object, phone: string|null}} Champs à écrire, et
 *   numéro à déplacer en sous-collection (ou `null`).
 */
function planFor(data) {
  const update = {};

  const createdAt = data.createdAt && data.createdAt.toMillis ?
    data.createdAt :
    null;
  const createdMs = createdAt ? createdAt.toMillis() : Date.now();

  // Sans `bumpedAt`, l'annonce sort de toutes les requêtes triées : c'est
  // le champ dont l'absence la rendrait purement et simplement
  // invisible, sans le moindre message d'erreur.
  if (!data.bumpedAt) {
    update.bumpedAt = createdAt || Timestamp.fromMillis(createdMs);
  }
  if (!data.expiresAt) {
    update.expiresAt = Timestamp.fromMillis(createdMs + LISTING_LIFETIME_MS);
  }
  if (!Array.isArray(data.keywords) || data.keywords.length === 0) {
    update.keywords = marketKeywords(data.title, data.description);
  }
  // `sold` conditionne la requête publique : un document où il est absent
  // n'est pas remonté par `where('sold', '==', false)`.
  if (typeof data.sold !== "boolean") update.sold = false;
  if (typeof data.hidden !== "boolean") update.hidden = false;
  if (typeof data.viewsCount !== "number") update.viewsCount = 0;
  if (typeof data.favoritesCount !== "number") update.favoritesCount = 0;
  if (typeof data.contactsCount !== "number") update.contactsCount = 0;

  const phone = typeof data.sellerPhone === "string" ?
    data.sellerPhone.trim() :
    "";
  if (data.sellerPhone !== undefined) {
    update.hasPhone = phone.length > 0;
    update.sellerPhone = FieldValue.delete();
  } else if (typeof data.hasPhone !== "boolean") {
    update.hasPhone = false;
  }

  return {update, phone: phone.length > 0 ? phone : null};
}

/**
 * Applique le rattrapage à une annonce.
 *
 * Idempotent : ne touche qu'aux champs absents, ne réécrit jamais une
 * valeur déjà posée — relançable autant de fois que voulu.
 *
 * @param {FirebaseFirestore.DocumentReference} ref Annonce à compléter.
 * @param {object} data Contenu actuel du document.
 * @return {Promise<boolean>} Vrai si quelque chose a été écrit.
 */
async function backfillListing(ref, data) {
  const {update, phone} = planFor(data);
  if (Object.keys(update).length === 0 && !phone) return false;

  // Le numéro part **avant** d'être retiré du document public : si
  // l'opération s'interrompt entre les deux, mieux vaut un numéro présent
  // aux deux endroits qu'un numéro perdu.
  if (phone) {
    await ref.collection("contact").doc("info").set(
        {phone, sellerUid: data.sellerUid || null},
        {merge: true},
    );
  }
  if (Object.keys(update).length > 0) await ref.update(update);
  return true;
}

module.exports = {
  LISTING_LIFETIME_MS,
  marketKeywords,
  planFor,
  backfillListing,
};
