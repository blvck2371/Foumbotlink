/**
 * Certification de compte (badge « Compte certifié »).
 *
 * Les conditions ne sont **pas** dans le code : elles sont lues dans le
 * document Firestore `config/certification`, modifiable depuis la console
 * sans republier l'app ni les fonctions :
 *
 *   {
 *     personal: {
 *       enabled: true,        // les habitants peuvent demander
 *       minFollowers: 500,    // abonnés au moins
 *       minLikes: 1000,       // J'aime reçus au moins (toutes publications)
 *       autoApprove: false    // vrai : certifié dès la demande
 *     },
 *     structure: {
 *       enabled: false,       // « bientôt disponible » tant que faux
 *       minFollowers: 0,
 *       minLikes: 0,
 *       autoApprove: false
 *     }
 *   }
 *
 * Sans ce document, ou pour un type de compte absent, la certification est
 * simplement indisponible : aucune valeur par défaut n'est inventée ici.
 *
 * Une demande est un document `certificationRequests/{uid}`
 * (status: pending | approved | rejected), écrit par le serveur seul. Pour
 * la valider ou la refuser, un administrateur passe `status` à `approved`
 * ou `rejected` dans la console : [onCertificationDecided] certifie le
 * compte et prévient la personne.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {AggregateField, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const CONFIG_DOC = "config/certification";

/**
 * Règles d'un type de compte, lues telles quelles et bornées.
 *
 * @param {object|undefined} raw Bloc `personal` ou `structure`.
 * @return {{enabled: boolean, minFollowers: number, minLikes: number,
 *   autoApprove: boolean}}
 */
function rulesFrom(raw) {
  const r = raw && typeof raw === "object" ? raw : {};
  const num = (v) => Number.isFinite(v) && v > 0 ? Math.floor(v) : 0;
  return {
    enabled: r.enabled === true,
    minFollowers: num(r.minFollowers),
    minLikes: num(r.minLikes),
    autoApprove: r.autoApprove === true,
  };
}

module.exports = function certification({db, notifyUser}) {
  /**
   * Où en est le compte : règles applicables, compteurs, demande.
   *
   * @param {string} uid Compte.
   * @return {Promise<object>}
   */
  async function statusOf(uid) {
    const [userSnap, configSnap, requestSnap, likesAgg] = await Promise.all([
      db.doc(`users/${uid}`).get(),
      db.doc(CONFIG_DOC).get(),
      db.doc(`certificationRequests/${uid}`).get(),
      db.collection("posts").where("authorUid", "==", uid)
          .aggregate({likes: AggregateField.sum("likesCount")}).get(),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition",
          "Complétez votre profil d'abord.");
    }
    const user = userSnap.data();
    const accountType = user.accountType === "structure" ?
      "structure" : "personal";
    const config = configSnap.exists ? configSnap.data() : {};
    const rules = rulesFrom(config[accountType]);
    const followers = Number(user.followersCount) || 0;
    const likes = Number(likesAgg.data().likes) || 0;
    const request = requestSnap.exists ? requestSnap.data() : null;
    return {
      accountType,
      verified: user.verified === true,
      enabled: rules.enabled,
      minFollowers: rules.minFollowers,
      minLikes: rules.minLikes,
      followers,
      likes,
      eligible: rules.enabled &&
        followers >= rules.minFollowers && likes >= rules.minLikes,
      request: request ? {status: request.status || "pending"} : null,
      autoApprove: rules.autoApprove,
    };
  }

  const requireUid = (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");
    return uid;
  };

  const certificationStatus = onCall(async (request) => {
    const s = await statusOf(requireUid(request));
    delete s.autoApprove;
    return s;
  });

  const requestCertification = onCall(async (request) => {
    const uid = requireUid(request);
    const s = await statusOf(uid);
    if (s.verified) {
      throw new HttpsError("already-exists", "Votre compte est déjà certifié.");
    }
    if (!s.enabled) {
      throw new HttpsError("failed-precondition",
          "La certification n'est pas encore ouverte pour ce type de compte.");
    }
    if (s.request && s.request.status === "pending") {
      throw new HttpsError("already-exists",
          "Votre demande est déjà en cours d'examen.");
    }
    if (!s.eligible) {
      throw new HttpsError("failed-precondition",
          `Il faut au moins ${s.minFollowers} abonnés et ${s.minLikes} ` +
          "J'aime reçus pour demander la certification.");
    }

    const userSnap = await db.doc(`users/${uid}`).get();
    const ref = db.doc(`certificationRequests/${uid}`);
    await ref.set({
      uid,
      displayName: userSnap.get("displayName") || "",
      accountType: s.accountType,
      followers: s.followers,
      likes: s.likes,
      status: s.autoApprove ? "approved" : "pending",
      requestedAt: FieldValue.serverTimestamp(),
      decidedAt: s.autoApprove ? FieldValue.serverTimestamp() : null,
    });
    if (s.autoApprove) await approve(uid);
    logger.info(`Certification demandée par ${uid}` +
      (s.autoApprove ? " (validée automatiquement)" : ""));
    return {status: s.autoApprove ? "approved" : "pending"};
  });

  /**
   * Certifie le compte et prévient la personne.
   *
   * @param {string} uid Compte.
   * @return {Promise<void>}
   */
  async function approve(uid) {
    await db.doc(`users/${uid}`).update({verified: true});
    await notifyUser(uid, {
      type: "certification",
      title: "Compte certifié",
      body: "Votre compte porte désormais le badge de certification.",
      data: {status: "approved"},
    });
  }

  /** Décision d'un administrateur, prise dans la console. */
  const onCertificationDecided = onDocumentUpdated(
      "certificationRequests/{uid}", async (event) => {
        const before = event.data.before.data();
        const after = event.data.after.data();
        if (before.status === after.status) return;
        const uid = event.params.uid;
        if (after.status === "approved" && before.status === "pending") {
          await approve(uid);
          await event.data.after.ref.update({
            decidedAt: FieldValue.serverTimestamp(),
          });
        } else if (after.status === "rejected") {
          await notifyUser(uid, {
            type: "certification",
            title: "Certification non accordée",
            body: after.reason ||
              "Votre demande de certification n'a pas été retenue.",
            data: {status: "rejected"},
          });
        }
      });

  return {
    certificationStatus,
    requestCertification,
    onCertificationDecided,
    statusOf,
  };
};

module.exports.rulesFrom = rulesFrom;
