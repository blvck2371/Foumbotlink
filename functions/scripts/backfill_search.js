/**
 * Indexe pour la recherche les documents existants (users, posts, market).
 * Les nouveaux documents sont indexés par les triggers de search_index.js ;
 * ce script ne sert qu'à la première mise en place. Idempotent : seuls les
 * documents dont l'index diffère sont réécrits, et seul le champ `search`.
 *
 * Passe par l'API REST Firestore avec le jeton gcloud de l'opérateur :
 *   GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) \
 *   node scripts/backfill_search.js
 */
const {expectedIndex} = require("../search_index");

const token = process.env.GOOGLE_OAUTH_ACCESS_TOKEN;
const base = "https://firestore.googleapis.com/v1/projects/foumbotlink/" +
  "databases/(default)/documents";
const headers = {
  "Authorization": `Bearer ${token}`,
  "Content-Type": "application/json",
};

/** Valeur REST Firestore → JS (seulement ce dont l'index a besoin). */
function plain(v) {
  if (!v) return undefined;
  if ("stringValue" in v) return v.stringValue;
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(plain);
  return undefined;
}

async function run(collection) {
  let pageToken = "";
  let changed = 0;
  do {
    const url = `${base}/${collection}?pageSize=300` +
      (pageToken ? `&pageToken=${pageToken}` : "");
    const res = await fetch(url, {headers});
    if (!res.ok) throw new Error(`${collection}: ${res.status} ${await res.text()}`);
    const body = await res.json();
    for (const doc of body.documents || []) {
      const data = {};
      for (const [k, v] of Object.entries(doc.fields || {})) data[k] = plain(v);
      const index = expectedIndex(collection, data);
      const current = data.search;
      if (Array.isArray(current) && current.length === index.length &&
          current.every((x, i) => x === index[i])) continue;
      const patch = await fetch(
        `https://firestore.googleapis.com/v1/${doc.name}` +
        "?updateMask.fieldPaths=search&currentDocument.exists=true",
        {
          method: "PATCH",
          headers,
          body: JSON.stringify({fields: {search: {arrayValue: {
            values: index.map((s) => ({stringValue: s})),
          }}}}),
        });
      if (!patch.ok) throw new Error(`${doc.name}: ${await patch.text()}`);
      changed++;
    }
    pageToken = body.nextPageToken || "";
  } while (pageToken);
  return changed;
}

(async () => {
  if (!token) throw new Error("GOOGLE_OAUTH_ACCESS_TOKEN manquant");
  for (const c of ["users", "posts", "market"]) {
    console.log(`${c} : ${await run(c)} document(s) indexé(s)`);
  }
})().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
