/**
 * Règles Firestore du guichet : démarches, codes de suivi, dossiers.
 *
 * C'est la surface la plus sensible de l'application. Un dossier
 * administratif n'est pas une publication : il porte le nom d'un
 * habitant, l'objet de sa demande et son avancement. Trois garanties
 * doivent tenir, et ce sont elles qu'on vérifie ici :
 *
 *  1. **Seule une structure validée tient un guichet.** Un compte
 *     personnel, ou une structure pas encore validée, ne crée ni
 *     démarche ni dossier.
 *  2. **Un dossier ne peut être rattaché qu'au bon habitant.** La règle
 *     relit l'annuaire des codes de suivi et compare : sans ça, un
 *     guichet pourrait rattacher un dossier à n'importe qui, et cette
 *     personne verrait apparaître une démarche qu'elle n'a jamais
 *     déposée.
 *  3. **Personne d'autre que les deux intéressés n'y a accès**, et
 *     l'avancement n'appartient qu'au service qui traite.
 *
 *   npx firebase emulators:exec --only firestore \
 *     "node scripts/test_rules_dossiers.js"
 */

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  getDoc,
  deleteDoc,
  updateDoc,
  writeBatch,
  arrayUnion,
  serverTimestamp,
} = require("firebase/firestore");
const fs = require("fs");
const path = require("path");

const STRUCTURE = "mairie";
const OTHER_STRUCTURE = "prefecture";
const PENDING = "assoNonValidee";
const CITIZEN = "habitant";
const OUTSIDER = "voisin";
const CODE = "FBT-A1B";
const DOSSIER = "dossier1";

let failures = 0;

/**
 * Exécute un cas de test en annonçant son résultat.
 *
 * @param {string} name Ce qui est vérifié.
 * @param {function(): Promise<void>} body Le cas lui-même.
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
 * Point d'entrée.
 *
 * @return {Promise<void>} Résolue en fin de campagne.
 */
async function main() {
  const env = await initializeTestEnvironment({
    projectId: "foumbotlink-rules-dossiers",
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, "..", "..", "firestore.rules"),
          "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  const structure = env.authenticatedContext(STRUCTURE).firestore();
  const otherStructure = env.authenticatedContext(OTHER_STRUCTURE).firestore();
  const pending = env.authenticatedContext(PENDING).firestore();
  const citizen = env.authenticatedContext(CITIZEN).firestore();
  const outsider = env.authenticatedContext(OUTSIDER).firestore();
  const anon = env.unauthenticatedContext().firestore();

  /**
   * Sème comptes, code de suivi et dossier de départ.
   *
   * @return {Promise<void>} Résolue après réinitialisation.
   */
  async function reset() {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const profile = (accountType, verified) => ({
        accountType,
        verified,
        displayName: "Compte",
        createdAt: new Date().toISOString(),
      });
      await setDoc(doc(db, "users", STRUCTURE), profile("structure", true));
      await setDoc(
          doc(db, "users", OTHER_STRUCTURE), profile("structure", true));
      await setDoc(doc(db, "users", PENDING), profile("structure", false));
      await setDoc(doc(db, "users", CITIZEN), profile("personal", false));
      await setDoc(doc(db, "users", OUTSIDER), profile("personal", false));
      await setDoc(doc(db, "trackingCodes", CODE), {uid: CITIZEN});
    });
  }

  console.log("Règles — guichet (démarches, codes, dossiers)");

  // --- 1. Démarches -----------------------------------------------------
  await reset();

  await check("le guide des démarches est public", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "demarches", "cni"), {
        structureUid: STRUCTURE,
        title: "Carte nationale d’identité",
      });
    });
    await assertSucceeds(getDoc(doc(anon, "demarches", "cni")));
  });

  await check("une structure validée publie une démarche", async () => {
    await assertSucceeds(
        setDoc(doc(structure, "demarches", "acte"), {
          structureUid: STRUCTURE,
          title: "Acte de naissance",
        }),
    );
  });

  await check("une structure non validée ne publie pas", async () => {
    await assertFails(
        setDoc(doc(pending, "demarches", "refus"), {
          structureUid: PENDING,
          title: "Quelque chose",
        }),
    );
  });

  await check("un habitant ne publie pas de démarche", async () => {
    await assertFails(
        setDoc(doc(citizen, "demarches", "refus2"), {
          structureUid: CITIZEN,
          title: "Quelque chose",
        }),
    );
  });

  await check("on ne publie pas au nom d'un autre guichet", async () => {
    await assertFails(
        setDoc(doc(structure, "demarches", "usurpation"), {
          structureUid: OTHER_STRUCTURE,
          title: "Acte",
        }),
    );
  });

  await check("un guichet ne modifie pas la démarche d'un autre", async () => {
    await assertFails(
        updateDoc(doc(otherStructure, "demarches", "acte"), {title: "Volé"}),
    );
  });

  await check("une démarche ne change pas de guichet", async () => {
    await assertFails(
        updateDoc(doc(structure, "demarches", "acte"), {
          structureUid: OTHER_STRUCTURE,
        }),
    );
  });

  // --- 2. Codes de suivi -------------------------------------------------
  /**
   * Réserve un code comme le fait l'app : le code et
   * `users/{uid}/private/tracking` dans le même batch.
   *
   * @param {object} db Contexte Firestore de l'appelant.
   * @param {string} uid Compte qui réserve.
   * @param {string} code Code tiré.
   * @param {string=} target Compte vers lequel le code pointe.
   * @return {Promise<void>} Résolue une fois le batch validé.
   */
  function reserve(db, uid, code, target = uid) {
    const batch = writeBatch(db);
    batch.set(doc(db, "trackingCodes", code), {uid: target});
    batch.set(doc(db, "users", uid, "private", "tracking"), {code});
    return batch.commit();
  }

  await check("chacun réserve un code pointant sur lui-même", async () => {
    await assertSucceeds(reserve(outsider, OUTSIDER, "FBT-ZZZ"));
  });

  await check("un compte ne réserve qu'un seul code", async () => {
    // Sans ce verrou, un compte pouvait réserver des codes en boucle.
    await assertFails(reserve(outsider, OUTSIDER, "FBT-YYY"));
  });

  await check("le verrou du code ne s'efface ni ne se réécrit", async () => {
    const lock = doc(outsider, "users", OUTSIDER, "private", "tracking");
    await assertFails(deleteDoc(lock));
    await assertFails(setDoc(lock, {code: "FBT-WWW"}));
  });

  await check("un code seul, sans son verrou, est refusé", async () => {
    await assertFails(
        setDoc(doc(pending, "trackingCodes", "FBT-VVV"), {uid: PENDING}),
    );
  });

  await check("le verrou seul, sans code réservé, est refusé", async () => {
    await assertFails(
        setDoc(doc(pending, "users", PENDING, "private", "tracking"),
            {code: "FBT-VVV"}),
    );
  });

  await check("on ne réserve pas un code pour autrui", async () => {
    await assertFails(reserve(pending, PENDING, "FBT-XXX", CITIZEN));
  });

  await check("un code déjà pris ne se réserve pas", async () => {
    await assertFails(reserve(pending, PENDING, CODE));
  });

  await check("un code attribué ne se réattribue pas", async () => {
    // Le réécrire ferait basculer les dossiers en cours d'un habitant
    // vers un autre.
    await assertFails(
        updateDoc(doc(outsider, "trackingCodes", CODE), {uid: OUTSIDER}),
    );
    await assertFails(deleteDoc(doc(citizen, "trackingCodes", CODE)));
  });

  await check("le guichet retrouve l'habitant derrière un code", async () => {
    await assertSucceeds(getDoc(doc(structure, "trackingCodes", CODE)));
  });

  await check("chacun relit son propre code", async () => {
    await assertSucceeds(getDoc(doc(citizen, "trackingCodes", CODE)));
  });

  await check("le code d'un autre n'est pas lisible", async () => {
    // Sans ça, n'importe qui balaierait les codes pour dresser la liste
    // des habitants.
    await assertFails(getDoc(doc(outsider, "trackingCodes", CODE)));
  });

  // --- 3. Dossiers -------------------------------------------------------
  await reset();

  const dossier = {
    ownerUid: CITIZEN,
    ownerName: "Habitant",
    structureUid: STRUCTURE,
    structureName: "Mairie",
    title: "Acte de naissance",
    trackingCode: CODE,
    status: "receptionne",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    events: [],
  };

  await check("le guichet réceptionne un dossier", async () => {
    await assertSucceeds(setDoc(doc(structure, "dossiers", DOSSIER), dossier));
  });

  await check(
      "un dossier ne peut pas être rattaché au mauvais habitant",
      async () => {
        await assertFails(
            setDoc(doc(structure, "dossiers", "detourne"), {
              ...dossier,
              ownerUid: OUTSIDER,
            }),
        );
      },
  );

  await check("un code inconnu ne permet pas de réceptionner", async () => {
    await assertFails(
        setDoc(doc(structure, "dossiers", "inventé"), {
          ...dossier,
          trackingCode: "FBT-000",
        }),
    );
  });

  await check("un dossier naît toujours « réceptionné »", async () => {
    await assertFails(
        setDoc(doc(structure, "dossiers", "avance"), {
          ...dossier,
          status: "livre",
        }),
    );
  });

  await check("un habitant ne réceptionne pas de dossier", async () => {
    await assertFails(
        setDoc(doc(citizen, "dossiers", "faux"), {
          ...dossier,
          structureUid: CITIZEN,
        }),
    );
  });

  await check("l'habitant suit son dossier", async () => {
    await assertSucceeds(getDoc(doc(citizen, "dossiers", DOSSIER)));
  });

  await check("le guichet consulte le dossier qu'il traite", async () => {
    await assertSucceeds(getDoc(doc(structure, "dossiers", DOSSIER)));
  });

  await check("personne d'autre n'y a accès", async () => {
    await assertFails(getDoc(doc(outsider, "dossiers", DOSSIER)));
    await assertFails(getDoc(doc(otherStructure, "dossiers", DOSSIER)));
    await assertFails(getDoc(doc(anon, "dossiers", DOSSIER)));
  });

  await check("le guichet fait avancer le dossier", async () => {
    await assertSucceeds(
        updateDoc(doc(structure, "dossiers", DOSSIER), {
          status: "en_cours",
          updatedAt: serverTimestamp(),
          events: arrayUnion({status: "en_cours", byName: "Mairie"}),
        }),
    );
  });

  await check("l'habitant ne fait pas avancer son dossier", async () => {
    // Son dossier est le compte rendu du service, pas un document qu'il
    // rédige.
    await assertFails(
        updateDoc(doc(citizen, "dossiers", DOSSIER), {status: "livre"}),
    );
  });

  await check("le guichet ne change pas de propriétaire", async () => {
    await assertFails(
        updateDoc(doc(structure, "dossiers", DOSSIER), {ownerUid: OUTSIDER}),
    );
  });

  await check("le guichet ne réécrit pas l'objet du dossier", async () => {
    await assertFails(
        updateDoc(doc(structure, "dossiers", DOSSIER), {title: "Autre chose"}),
    );
  });

  await check("un dossier ne s'efface pas", async () => {
    // Il est la trace de ce qu'on a déposé.
    await assertFails(deleteDoc(doc(structure, "dossiers", DOSSIER)));
    await assertFails(deleteDoc(doc(citizen, "dossiers", DOSSIER)));
  });

  await env.cleanup();
  console.log(
      failures === 0 ?
        "\nToutes les règles du guichet sont conformes." :
        `\n${failures} cas en échec.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
