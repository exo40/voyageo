-- =====================================================================
-- Voyagéo : compte MySQL du site (droits minimum). À exécuter APRÈS voyageo_mysql_production.sql
-- ET voyageo_extensions_site.sql (les droits des tables complémentaires sont en bas de ce fichier),
-- avec un compte administrateur MySQL.
--
-- AVANT D'EXÉCUTER : remplacer CHANGER_CE_MOT_DE_PASSE par un mot de passe long et aléatoire
-- (16 caractères minimum), puis écrire le même dans le fichier .env (DB_USER=voyageo_app, DB_PASSWORD=...).
-- Ne jamais enregistrer ce fichier rempli sur GitHub.
-- Si le site et MySQL ne sont pas sur la même machine, remplacer 'localhost' par l'adresse du site.
--
-- Droits donnés : lire/écrire les tables métier. Droits refusés exprès : créer/supprimer des tables,
-- modifier la structure, créer des triggers, et ÉCRIRE directement dans bus_occupation (table tenue à jour
-- par la base elle-même : l'écriture directe pourrait contourner la règle des bus). Testé avec ces droits.
-- =====================================================================
CREATE USER 'voyageo_app'@'localhost' IDENTIFIED BY 'CHANGER_CE_MOT_DE_PASSE';

GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.compagnie     TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.utilisateur   TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.bus           TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.trajet        TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.horaire       TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.reservation   TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.paiement      TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.remboursement TO 'voyageo_app'@'localhost';
GRANT SELECT ON voyageo.bus_occupation        TO 'voyageo_app'@'localhost';
GRANT SELECT ON voyageo.v_places_horaire      TO 'voyageo_app'@'localhost';
GRANT SELECT ON voyageo.v_reservation_detail  TO 'voyageo_app'@'localhost';
GRANT SELECT ON voyageo.v_stats_globales      TO 'voyageo_app'@'localhost';
GRANT SELECT ON voyageo.v_stats_compagnie     TO 'voyageo_app'@'localhost';
GRANT SELECT ON voyageo.v_solde_reservation   TO 'voyageo_app'@'localhost';
GRANT SELECT ON voyageo.v_anomalies_financieres TO 'voyageo_app'@'localhost';

-- ---------------------------------------------------------------------
-- Tables complémentaires (voyageo_extensions_site.sql), toujours au strict nécessaire :
-- le journal d'audit et les avis ne sont qu'ajoutés (jamais modifiés ni effacés par le site).
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.chauffeur           TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT                 ON voyageo.avis                TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON voyageo.pourboire           TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT                 ON voyageo.journal_audit       TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON voyageo.compagnie_paiement  TO 'voyageo_app'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON voyageo.abonnement_paiement TO 'voyageo_app'@'localhost';
