# Déploiement de Voyageo sur Vercel

## Prérequis

1. **Créer un compte Vercel** si vous ne l'avez pas déjà fait
2. **Configurer votre dépôt GitHub** avec les permissions nécessaires
3. **Installer Node.js** (version 20 ou supérieure)

## Instructions de déploiement

### Étape 1 : Préparer le dépôt GitHub

1. Créez un dépôt GitHub pour votre projet Voyageo
2. Clonez le projet localement
3. Ajoutez les fichiers de configuration de production

### Étape 2 : Configurer les variables d'environnement

1. Créez un fichier `.env.production` dans le dossier racine du projet avec les variables d'environnement de production
2. Configurez les variables pour votre base de données, FedaPay, e-mail, etc.

### Étape 3 : Configurer GitHub Actions

1. Ajoutez le fichier `deploy.yml` dans le dossier `.github/workflows/`
2. Configurez les secrets sur GitHub pour `VERCEL_TOKEN`

### Étape 4 : Déployer

1. Poussez les modifications vers votre dépôt GitHub
2. Vercel déclenchera automatiquement le workflow de déploiement
3. Le déploiement prendra environ 2-5 minutes

## Variables d'environnement recommandées

```env
# .env.production
NODE_ENV=production
PORT=3000
APP_BASE_URL=https://voyageo.example.com
SESSION_SECRET=very_long_and_random_session_secret_for_production

# Base de données
DB_DRIVER=mysql
DB_HOST=localhost
DB_PORT=3306
DB_USER=voyageo_app
DB_PASSWORD=voyageo_app_password
DB_NAME=voyageo

# Paiement
PAYMENT_MODE=fedapay
FEDAPAY_ENV=production
FEDAPAY_PUBLIC_KEY=your_production_public_key
FEDAPAY_SECRET_KEY=your_production_secret_key

# E-mail
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USER=VOTRE_UTILISATEUR_SMTP
SMTP_PASS=REMPLACER_PAR_UN_SECRET
MAIL_FROM="Voyagéo <voyageo.bj@gmail.com>"

# WhatsApp
WHATSAPP_NUMBER=22960315810
WHATSAPP_DISPLAY="+229 60 31 58 10"

# Configuration Redis (si utilisé)
# REDIS_HOST=your_redis_host
# REDIS_PORT=6379
# REDIS_PASSWORD=your_redis_password
# REDIS_DB=0
```

## Configuration de la base de données

1. Installez MySQL ou PostgreSQL sur votre serveur
2. Créez la base de données avec les scripts fournis :
   - `database/voyageo_mysql_production.sql`
   - `database/voyageo_extensions_site.sql`
   - `database/voyageo_compte_applicatif.sql`

## Configuration de FedaPay

1. Créez un compte sur FedaPay
2. Configurez le mode de production dans votre compte
3. Récupérez les clés publiques et secrètes pour l'environnement de production

## Webhooks

Pour que le paiement fonctionne correctement, configurez les webhooks sur FedaPay :
- `APP_BASE_URL/paiement/webhook` pour les paiements individuels
- `APP_BASE_URL/paiement/webhook/:cid` pour les paiements des agences

## Test du déploiement

Une fois déployé, testez l'application en accédant à l'URL publique fournie par Vercel.

## Exemple de workflow de déploiement

```yaml
# .github/workflows/deploy.yml
name: Deploy to Vercel

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Set up Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '20'

    - name: Install dependencies
      run: npm install

    - name: Build
      run: npm run build

    - name: Deploy to Vercel
      uses: vercel/vercel-deploy@v1
      with:
        token: ${{ secrets.VERCEL_TOKEN }}
        project-name: voyageo
        production: true
        env: |
          NODE_ENV=production
          DB_DRIVER=mysql
          DB_HOST=your_db_host
          DB_PORT=3306
          DB_USER=voyageo_app
          DB_PASSWORD=REMPLACER_PAR_UN_SECRET
          DB_NAME=voyageo
          PAYMENT_MODE=fedapay
          FEDAPAY_ENV=production
          FEDAPAY_PUBLIC_KEY=your_production_public_key
          FEDAPAY_SECRET_KEY=your_production_secret_key
          SMTP_HOST=smtp-relay.brevo.com
          SMTP_PORT=587
          SMTP_USER=ton_utilisateur_smtp
          SMTP_PASS=REMPLACER_PAR_UN_SECRET
          MAIL_FROM="Voyagéo <voyageo.bj@gmail.com>"
          APP_BASE_URL=https://voyageo.example.com
          SESSION_SECRET=REMPLACER_PAR_UN_SECRET
          REDIS_HOST=your_redis_host
          REDIS_PORT=6379
          REDIS_PASSWORD=your_redis_password
          REDIS_DB=0
          WHATSAPP_NUMBER=22960315810
          WHATSAPP_DISPLAY="+229 60 31 58 10"
          ANNULATION_HEURES=24
          RESERVATION_ATTENTE_MINUTES=15
          CLOTURE_RESERVATION_MINUTES=30
          TIMEZONE_OFFSET=+01:00
          SUBSCRIPTION_PRICE_FCFA=20000
          SUBSCRIPTION_DURATION_DAYS=30
          ENCRYPTION_KEY=very_long_encryption_key
          EMAIL_VERIFICATION=true
          CODE_VALIDITE_MINUTES=15
          DEMO_DATA=false
```

## Instructions pour l'utilisateur

1. Connectez-vous à votre compte Vercel
2. Créez un nouveau projet depuis votre dépôt GitHub
3. Vercel va automatiquement :
   - Installer les dépendances
   - Configurer les variables d'environnement
   - Déployer l'application
   - Gérer les bases de données et Redis si nécessaire

Le projet Voyageo est maintenant prêt à être déployé en ligne avec toutes les fonctionnalités déjà testées localement. Les étapes ci-dessus vous permettront de mettre en production votre projet avec succès.
