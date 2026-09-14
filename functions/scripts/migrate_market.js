/**
 * Migration du marché vers le modèle « annonce qui vit et qui expire ».
 *
 * Trois changements de fond, tous portés par ce script :
 *
 *  1. **Le numéro sort du document public.** `market/{id}.sellerPhone`
 *     était lisible par n'importe qui, connecté ou non : une seule
 *     requête suffisait à récupérer les numéros de toute la commune. Il
 *     part dans `market/{id}/contact/info`, réservé aux comptes
 *     connectés, et le document public ne garde qu'un booléen
 *     `hasPhone`.
 *
 *  2. **La grille est triée sur `bumpedAt`, plus sur `createdAt`.** Une
 *     annonce relancée doit pouvoir remonter sans perdre sa date réelle
 *     de publication. Les annonces existantes n'ont pas ce champ, et une
 *     requête `orderBy('bumpedAt')` les écarterait purement et
 *     simplement : elles disparaîtraient du marché sans un mot. Ce
 *     script leur pose `bumpedAt = createdAt`.
 *
 *  3. **Recherche, expiration et compteurs.** `keywords` (jetons de
 *     recherche calculés sur le titre et la description), `expiresAt`
 *     (60 jours après la publication) et les trois compteurs d'intérêt.
 *
 * **Ce script est facultatif.** La même réparation tourne côté serveur
 * (`repairMarketListings`, une fois par nuit) et s'applique aussi à
 * chaque annonce publiée depuis une version trop ancienne de l'app. Ce
 * script ne sert qu'à ne pas attendre la nuit, ou à traiter d'un coup une
 * base plus grosse que le lot quotidien.
 *
 * Le script est **idempotent** : relançable sans risque, il ne touche
 * qu'aux champs manquants et ne réécrit jamais une valeur déjà posée. La
 * logique elle-même vit dans `market_backfill.js`, partagée avec les
 * Cloud Functions : il n'y a qu'une seule définition de « ce qui manque à
 * une annonce ».
 *
 * Utilisation (depuis `functions/`) :
 *
 *   # ce qui serait fait, sans rien écrire
 *   node scripts/migrate_market.js --dry-run
 *
 *   # la migration elle-même
 *   node scripts/migrate_market.js
 *
 *   # sur un projet précis
 *   node scripts/migrate_market.js --project=foumbotlink
 *
 * Authentification : identifiants par défaut de l'application. Soit
 *   gcloud auth application-default login
 * soit GOOGLE_APPLICATION_CREDENTIALS pointant sur une clé de compte de
 * service. Le projet vient de --project, GCLOUD_PROJECT ou de la clé.
 */

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {planFor, backfillListing} = require("../market_backfill");

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
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

/** Taille des pages d'annonces parcourues. */
const PAGE = 200;

/**
 * Parcourt toutes les annonces et applique le plan de migration.
 *
 * @return {Promise<void>} Résolue en fin de parcours.
 */
async function run() {
  let last = null;
  let seen = 0;
  let migrated = 0;
  let phones = 0;

  for (;;) {
    let query = db.collection("market").orderBy("__name__").limit(PAGE);
    if (last) query = query.startAfter(last);
    const snap = await query.get();
    if (snap.empty) break;
    last = snap.docs[snap.docs.length - 1];

    for (const doc of snap.docs) {
      seen += 1;
      const {update, phone} = planFor(doc.data());
      if (Object.keys(update).length === 0 && !phone) continue;

      migrated += 1;
      if (phone) phones += 1;

      if (DRY_RUN) {
        console.log(
            `  ${doc.id} : ${Object.keys(update).join(", ") || "—"}` +
            (phone ? " (+ numéro déplacé)" : ""),
        );
        continue;
      }

      // Le numéro part **avant** d'être retiré du document public : si le
      // script s'interrompt entre les deux, on préfère un numéro présent
      // aux deux endroits à un numéro perdu.
      await backfillListing(doc.ref, doc.data());
    }
  }

  console.log(
      `\n${seen} annonce(s) parcourue(s), ${migrated} mise(s) à jour, ` +
      `${phones} numéro(s) déplacé(s)${DRY_RUN ? " (simulation)" : ""}.`,
  );
}

run().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
