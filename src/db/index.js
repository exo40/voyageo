'use strict';
/**
 * POINT D'ENTRÉE UNIQUE VERS LA BASE DE DONNÉES.
 * Le reste du site appelle uniquement  db.nomDeLaFonction(...).
 * Le choix de l'adaptateur se fait avec DB_DRIVER dans le fichier .env.
 */
const config = require('../config');
const { FUNCTIONS } = require('./contract');

let adapter = null;

function load() {
  if (adapter) return adapter;
  const driver = config.db.driver;
  if (driver === 'json') adapter = require('./adapters/json');
  else if (driver === 'mysql') adapter = require('./adapters/mysql');
  else if (driver === 'custom') adapter = require('./adapters/custom');
  else throw new Error(`DB_DRIVER inconnu : "${driver}" (valeurs possibles : json, mysql, custom)`);
  return adapter;
}

/** Retourne la liste des fonctions du contrat absentes de l'adaptateur. */
function missingFunctions() {
  const a = load();
  return FUNCTIONS.filter((name) => typeof a[name] !== 'function');
}

module.exports = new Proxy(
  { missingFunctions },
  {
    get(target, prop) {
      if (prop in target) return target[prop];
      if (typeof prop === 'symbol' || prop === 'then') return undefined;
      const fn = load()[prop];
      if (typeof fn !== 'function') throw new Error(`La fonction de base de données "${String(prop)}" n'existe pas dans l'adaptateur "${config.db.driver}".`);
      return fn;
    },
  }
);
