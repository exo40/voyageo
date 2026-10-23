'use strict';
const config = require('./src/config');
const db = require('./src/db');
const { createApp } = require('./src/app');
const { ensureAdmin } = require('./src/services/authService');
const { seedIfEmpty } = require('./src/services/demoData');
const session = require('express-session');

async function main() {
  if (!config.sessionSecret) throw new Error('SESSION_SECRET est obligatoire en production (voir .env).');
  await db.init();
  const missing = db.missingFunctions();
  if (missing.length) throw new Error(`L'adaptateur "${config.db.driver}" est incomplet. Fonctions manquantes : ${missing.join(', ')}`);
  await ensureAdmin();
  if (config.demoData) await seedIfEmpty();

  const app = createApp();

  // Utilisation d'un stockage mémoire par défaut si Redis n'est pas disponible ou en développement
  let sessionStore;
  let redisClient;

  if (config.isProd || process.env.USE_REDIS === 'true') {
    try {
      const RedisStore = require('connect-redis').default;
      const { createClient } = require('redis');

      redisClient = createClient({
        socket: {
          host: config.redis.host,
          port: config.redis.port,
        },
        password: config.redis.password,
      });

      redisClient.on('error', (err) => console.error('Redis error:', err));
      await redisClient.connect();
      sessionStore = new RedisStore({ client: redisClient });
      console.log('  Session : stockage Redis activé');
    } catch (e) {
      console.warn('  Session : échec de connexion Redis, repli sur le stockage en mémoire.', e.message);
    }
  }

  if (!sessionStore) {
    console.warn('  Session : les sessions sont gardées en mémoire (non persistant).');
  }

  app.use(session({
    name: 'voyageo.sid',
    secret: config.sessionSecret,
    resave: false,
    saveUninitialized: false,
    store: sessionStore,
    cookie: { httpOnly: true, sameSite: 'lax', secure: config.isProd ? 'auto' : false, maxAge: 7 * 24 * 3600 * 1000 },
  }));

  const server = app.listen(config.port, () => {
    console.log(`\n  ${config.appName} est en ligne : ${config.baseUrl}`);
    console.log(`  Base de données : ${config.db.driver} | Paiement : ${config.payment.mode} | E-mail : ${config.smtp.host ? 'activé' : 'désactivé'}\n`);
  });

  const stop = async () => {
    server.close();
    await db.close();
    if (redisClient) await redisClient.quit();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

main().catch((e) => { console.error('\nERREUR AU DÉMARRAGE :', e.message); process.exit(1); });
