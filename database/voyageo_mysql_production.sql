-- =====================================================================
-- Voyagéo : script de CRÉATION de la base RÉELLE (MySQL 8.0.16 ou plus récent)
-- Fichier : voyageo_mysql_production.sql
--
-- Ce script crée la base « voyageo » VIDE : tables, règles d'intégrité, déclencheurs, vues.
-- Il ne contient aucune donnée (ni compagnie, ni utilisateur, ni mot de passe) : le site crée
-- lui-même le compte administrateur et, si DEMO_DATA=true, les données de démonstration.
--
-- Sécurité : aucun DROP, aucun DELETE sur des données. Si une base « voyageo » existe déjà, le
-- script s'arrête avec l'erreur 1007 sans rien modifier : il ne peut pas écraser une base existante.
-- Pour une base existante déjà remplie avec l'ancien schéma : utiliser migration_voyageo.sql.
--
-- À exécuter :   mysql -u <compte_administrateur_mysql> -p --default-character-set=utf8mb4 < voyageo_mysql_production.sql
--   (ou « Importer » dans phpMyAdmin, sans cocher d'option qui supprime des tables)
--
-- IMPORTANT : serveur MySQL 8 obligatoire (testé sur 8.0.46). Le MariaDB fourni avec XAMPP n'est PAS
-- compatible : le script utilise des instructions propres à MySQL 8 (FOR SHARE OF...). Non testé sur MariaDB.
-- Si le serveur a le journal binaire actif et que le compte n'est pas SUPER : activer
-- log_bin_trust_function_creators=1 le temps de la création (pour créer fonction et triggers).
--
-- Ensuite : créer le compte du site avec voyageo_compte_applicatif.sql (jamais « root » dans le .env).
-- Encodage : utf8mb4 / utf8mb4_unicode_ci (insensible à la casse et aux accents : « cotonou » trouve « Cotonou »).
-- Fuseau   : les heures de voyage sont des heures locales du Bénin (UTC+1). Le site doit ouvrir chaque
--            connexion avec SET time_zone = '+00:00' (dates en UTC, comme le contrat du site).
-- =====================================================================

SET NAMES utf8mb4;
CREATE DATABASE voyageo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE voyageo;

-- ---------------------------------------------------------------------
-- COMPAGNIE
-- ---------------------------------------------------------------------
CREATE TABLE compagnie (
    id_compagnie  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nom           VARCHAR(100) NOT NULL,
    telephone     VARCHAR(30),
    email         VARCHAR(150),
    adresse       VARCHAR(255),
    statut        ENUM('active', 'suspendue') NOT NULL DEFAULT 'active',
    PRIMARY KEY (id_compagnie),
    UNIQUE KEY ux_compagnie_nom (nom)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- UTILISATEUR
-- Un gestionnaire est rattaché à UNE compagnie ; voyageur et administrateur n'en ont pas.
-- ---------------------------------------------------------------------
CREATE TABLE utilisateur (
    id_utilisateur      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nom                 VARCHAR(100) NOT NULL,
    prenom              VARCHAR(100) NOT NULL,
    email               VARCHAR(150) NOT NULL,
    telephone           VARCHAR(30),
    mot_de_passe_hache  VARCHAR(255) NOT NULL,              -- hash (bcrypt/argon2) calculé par le backend, jamais en clair
    role                ENUM('voyageur', 'administrateur', 'gestionnaire') NOT NULL DEFAULT 'voyageur',
    statut              ENUM('actif', 'bloque') NOT NULL DEFAULT 'actif',
    date_creation       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_compagnie        INT UNSIGNED NULL,
    PRIMARY KEY (id_utilisateur),
    UNIQUE KEY ux_utilisateur_email (email),
    KEY idx_utilisateur_compagnie (id_compagnie),
    CONSTRAINT fk_utilisateur_compagnie FOREIGN KEY (id_compagnie) REFERENCES compagnie(id_compagnie)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_utilisateur_compagnie CHECK (
        (role = 'gestionnaire' AND id_compagnie IS NOT NULL) OR (role <> 'gestionnaire' AND id_compagnie IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- BUS
-- ---------------------------------------------------------------------
CREATE TABLE bus (
    id_bus           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_compagnie     INT UNSIGNED NOT NULL,
    immatriculation  VARCHAR(30) NOT NULL,
    nombre_places    SMALLINT UNSIGNED NOT NULL,
    type             ENUM('standard', 'climatise', 'minibus') NOT NULL DEFAULT 'standard',
    PRIMARY KEY (id_bus),
    UNIQUE KEY ux_bus_immatriculation (immatriculation),
    KEY idx_bus_compagnie (id_compagnie),
    CONSTRAINT fk_bus_compagnie FOREIGN KEY (id_compagnie) REFERENCES compagnie(id_compagnie)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_bus_places CHECK (nombre_places BETWEEN 1 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- TRAJET
-- ---------------------------------------------------------------------
CREATE TABLE trajet (
    id_trajet      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_compagnie   INT UNSIGNED NOT NULL,
    ville_depart   VARCHAR(80) NOT NULL,
    ville_arrivee  VARCHAR(80) NOT NULL,
    duree_estimee  SMALLINT UNSIGNED NOT NULL,              -- en minutes
    lieu_embarquement VARCHAR(160) NULL,                    -- facultatif : où monter dans le bus
    lien_maps      VARCHAR(500) NULL,                       -- facultatif : lien Google Maps du lieu
    PRIMARY KEY (id_trajet),
    UNIQUE KEY ux_trajet_liaison (id_compagnie, ville_depart, ville_arrivee),
    KEY idx_trajet_villes (ville_depart, ville_arrivee),
    CONSTRAINT fk_trajet_compagnie FOREIGN KEY (id_compagnie) REFERENCES compagnie(id_compagnie)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_trajet_villes CHECK (ville_depart <> ville_arrivee),
    CONSTRAINT ck_trajet_duree CHECK (duree_estimee > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- HORAIRE (un voyage = un trajet + un bus + un départ + une arrivée)
-- date_arrivee distincte : un voyage de nuit arrive le lendemain (ex. 22:00 -> 03:00).
-- depart_dt est calculée (ne jamais l'écrire). L'occupation des bus (anti-chevauchement)
-- est tenue dans bus_occupation, alimentée automatiquement par des triggers.
-- ---------------------------------------------------------------------
CREATE TABLE horaire (
    id_horaire     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_trajet      INT UNSIGNED NOT NULL,
    id_bus         INT UNSIGNED NOT NULL,
    date_depart    DATE NOT NULL,
    heure_depart   TIME NOT NULL,
    date_arrivee   DATE NOT NULL,
    heure_arrivee  TIME NOT NULL,
    tarif_fcfa     INT UNSIGNED NOT NULL,
    statut         ENUM('programme', 'annule', 'termine') NOT NULL DEFAULT 'programme',
    depart_dt      DATETIME GENERATED ALWAYS AS (TIMESTAMP(date_depart, heure_depart)) STORED,
    PRIMARY KEY (id_horaire),
    KEY idx_horaire_bus (id_bus, date_depart, heure_depart),
    KEY idx_horaire_recherche (date_depart, id_trajet),
    KEY idx_horaire_trajet (id_trajet, date_depart),
    CONSTRAINT fk_horaire_trajet FOREIGN KEY (id_trajet) REFERENCES trajet(id_trajet)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_horaire_bus    FOREIGN KEY (id_bus)    REFERENCES bus(id_bus)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_horaire_tarif CHECK (tarif_fcfa > 0),
    -- TIME accepte jusqu'à 838:59:59 : on impose une heure d'horloge réelle
    CONSTRAINT ck_horaire_heures CHECK (
        heure_depart  >= '00:00:00' AND heure_depart  < '24:00:00' AND
        heure_arrivee >= '00:00:00' AND heure_arrivee < '24:00:00'),
    -- garde-fou si le serveur est en sql_mode permissif (dates invalides converties en 0000-00-00)
    CONSTRAINT ck_horaire_dates CHECK (date_depart >= '2000-01-01' AND date_arrivee >= '2000-01-01'),
    CONSTRAINT ck_horaire_sens CHECK (TIMESTAMP(date_arrivee, heure_arrivee) > TIMESTAMP(date_depart, heure_depart))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- BUS_OCCUPATION : créneaux occupés par les voyages NON annulés (table dérivée, tenue par
-- les triggers de horaire ; ne jamais l'écrire directement).
-- MySQL n'a pas de contrainte d'exclusion et un trigger ne peut pas relire (avec verrou)
-- la table qui l'a déclenché : le contrôle de chevauchement lit donc cette table.
-- L'unicité (id_bus, debut) interdit en plus, de façon déclarative, deux départs simultanés.
-- ---------------------------------------------------------------------
CREATE TABLE bus_occupation (
    id_horaire  INT UNSIGNED NOT NULL,
    id_bus      INT UNSIGNED NOT NULL,
    debut       DATETIME NOT NULL,
    fin         DATETIME NOT NULL,
    PRIMARY KEY (id_horaire),
    UNIQUE KEY ux_occupation_bus_debut (id_bus, debut),
    KEY idx_occupation_bus_fin (id_bus, fin),
    CONSTRAINT fk_occupation_horaire FOREIGN KEY (id_horaire) REFERENCES horaire(id_horaire)
        ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_occupation_bus FOREIGN KEY (id_bus) REFERENCES bus(id_bus)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_occupation_sens CHECK (fin > debut)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- RESERVATION
-- prix_fcfa : prix convenu, figé à la réservation (le tarif du voyage peut ensuite changer).
-- numero_place_active : calculée (= numero_place tant que non annulée, sinon NULL) ;
--   l'index unique (id_horaire, numero_place_active) interdit deux réservations actives
--   sur la même place du même voyage. MySQL admet plusieurs NULL dans un index unique :
--   les réservations annulées ne bloquent donc pas la place.
-- date_annulation : gérée par trigger (ne pas l'écrire).
-- ---------------------------------------------------------------------
CREATE TABLE reservation (
    id_reservation      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    numero_ticket       VARCHAR(20) NOT NULL,
    id_utilisateur      INT UNSIGNED NOT NULL,
    id_horaire          INT UNSIGNED NOT NULL,
    numero_place        SMALLINT UNSIGNED NOT NULL,
    nom_passager        VARCHAR(100) NOT NULL,
    prenom_passager     VARCHAR(100) NOT NULL,
    telephone_passager  VARCHAR(30) NOT NULL,
    piece_identite      VARCHAR(50),
    prix_fcfa           INT UNSIGNED NOT NULL,
    statut              ENUM('confirmee', 'en_attente', 'annulee') NOT NULL DEFAULT 'en_attente',
    date_reservation    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    date_annulation     DATETIME NULL,
    numero_place_active SMALLINT UNSIGNED
        GENERATED ALWAYS AS (IF(statut = 'annulee', NULL, numero_place)) STORED,
    PRIMARY KEY (id_reservation),
    UNIQUE KEY ux_reservation_ticket (numero_ticket),
    UNIQUE KEY ux_reservation_place_active (id_horaire, numero_place_active),
    KEY idx_reservation_utilisateur (id_utilisateur),
    CONSTRAINT fk_reservation_utilisateur FOREIGN KEY (id_utilisateur) REFERENCES utilisateur(id_utilisateur)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_reservation_horaire     FOREIGN KEY (id_horaire)     REFERENCES horaire(id_horaire)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_reservation_ticket CHECK (numero_ticket REGEXP '^VYG-[0-9]{4}-[0-9]{6}$'),
    CONSTRAINT ck_reservation_place  CHECK (numero_place >= 1),
    CONSTRAINT ck_reservation_prix   CHECK (prix_fcfa > 0),
    CONSTRAINT ck_reservation_annulation CHECK (statut = 'annulee' OR date_annulation IS NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- PAIEMENT : une ligne = une TENTATIVE d'encaissement (initie / echoue / reussi).
-- Au plus un paiement 'reussi' par réservation (id_reservation_reussie, calculée).
-- Les remboursements sont tracés dans la table remboursement ; 'rembourse' n'est atteint
-- que lorsque le montant total a été remboursé (voir triggers).
-- Tant que le paiement est 'initie', mode et référence peuvent être précisés (l'opérateur n'est connu
-- qu'à la fin d'un paiement via une passerelle) ; ils sont figés dès que le paiement est réussi ou échoué.
-- La référence est unique PAR OPÉRATEUR : deux opérateurs peuvent légitimement émettre
-- la même référence.
-- ---------------------------------------------------------------------
CREATE TABLE paiement (
    id_paiement            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_reservation         INT UNSIGNED NOT NULL,
    montant_fcfa           INT UNSIGNED NOT NULL,
    mode                   ENUM('mtn_momo', 'moov_money', 'celtiis_cash', 'especes', 'fedapay') NOT NULL,   -- 'fedapay' = passerelle, opérateur final inconnu à l'initiation
    reference_transaction  VARCHAR(100),
    statut                 ENUM('initie', 'reussi', 'echoue', 'rembourse') NOT NULL DEFAULT 'initie',
    date_paiement          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Compteurs tenus par les triggers de remboursement (ne pas les écrire) :
    --   engage = remboursements initiés + réussis ; reussi = remboursements réussis.
    -- Ils permettent de garantir le plafond par CHECK et par verrou de ligne, sans relire
    -- la table remboursement depuis son propre trigger (interdit par MySQL, erreur 1442).
    rembourse_engage_fcfa  INT UNSIGNED NOT NULL DEFAULT 0,
    rembourse_reussi_fcfa  INT UNSIGNED NOT NULL DEFAULT 0,
    id_reservation_reussie INT UNSIGNED GENERATED ALWAYS AS (IF(statut = 'reussi', id_reservation, NULL)) STORED,
    PRIMARY KEY (id_paiement),
    UNIQUE KEY ux_paiement_reference (mode, reference_transaction),
    UNIQUE KEY ux_paiement_reussi (id_reservation_reussie),
    KEY idx_paiement_reservation (id_reservation),
    CONSTRAINT fk_paiement_reservation FOREIGN KEY (id_reservation) REFERENCES reservation(id_reservation)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_paiement_montant CHECK (montant_fcfa > 0),
    CONSTRAINT ck_paiement_rembourse CHECK (rembourse_reussi_fcfa <= rembourse_engage_fcfa AND rembourse_engage_fcfa <= montant_fcfa),
    CONSTRAINT ck_paiement_reference CHECK (
        statut NOT IN ('reussi', 'rembourse') OR mode = 'especes' OR reference_transaction IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- REMBOURSEMENT : historique financier des remboursements (totaux ou partiels)
-- ---------------------------------------------------------------------
CREATE TABLE remboursement (
    id_remboursement       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_paiement            INT UNSIGNED NOT NULL,
    montant_fcfa           INT UNSIGNED NOT NULL,
    reference_transaction  VARCHAR(100),
    statut                 ENUM('initie', 'reussi', 'echoue') NOT NULL DEFAULT 'initie',
    date_remboursement     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_remboursement),
    UNIQUE KEY ux_remboursement_reference (id_paiement, reference_transaction),
    CONSTRAINT fk_remboursement_paiement FOREIGN KEY (id_paiement) REFERENCES paiement(id_paiement)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_remboursement_montant CHECK (montant_fcfa > 0),
    CONSTRAINT ck_remboursement_reference CHECK (statut <> 'reussi' OR reference_transaction IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- FONCTIONS, PROCÉDURES ET TRIGGERS
-- Codes d'erreur applicatifs (SQLSTATE 45000, MYSQL_ERRNO) pour le backend :
--  50001 voyage inexistant            50002 place hors capacité du bus
--  50003 voyage non programmé         50004 voyage déjà parti
--  50005 compagnie suspendue          50006 utilisateur non voyageur actif
--  50007 champ de réservation immuable 50008 transition de réservation interdite
--  50009 prix différent du tarif      50010 bus/trajet inexistant ou de compagnies différentes
--  50011 chevauchement du bus         50012 capacité du bus insuffisante pour les places réservées
--  50013 statut de voyage définitif   50014 annulation de voyage avec réservations actives
--  50015 changement de trajet avec réservations actives
--  50016 changement de compagnie d'un bus/trajet déjà programmé
--  50017 rôle voyageur modifié alors que des réservations existent
--  50020 réservation inexistante (paiement)   50021 'rembourse' interdit à l'insertion
--  50022 nouvelle tentative sur réservation annulée   50023 montant différent du prix convenu
--  50024 champ de paiement immuable   50025 transition de paiement interdite
--  50026 remboursement total non justifié
--  50030 paiement inexistant ou non réussi (remboursement)   50031 remboursement supérieur au paiement
--  50032 statut initial de remboursement interdit   50033 champ/transition de remboursement interdit
-- Les verrous (FOR SHARE / FOR UPDATE) dans les triggers sérialisent les opérations
-- concurrentes ; en cas d'interblocage détecté par InnoDB (erreur 1213) le backend relance
-- la transaction.
-- ---------------------------------------------------------------------
DELIMITER //

CREATE FUNCTION fn_maintenant_local() RETURNS DATETIME
    NOT DETERMINISTIC NO SQL
BEGIN
    -- Heure légale du Bénin : UTC+1 toute l'année
    RETURN CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+01:00');
END//

-- Vérifie qu'un utilisateur peut réserver (voyageur actif) ; verrouille sa ligne en lecture
CREATE PROCEDURE p_verifier_voyageur(IN p_id_utilisateur INT UNSIGNED)
BEGIN
    DECLARE v_role   VARCHAR(20);
    DECLARE v_statut VARCHAR(20);
    SELECT role, statut INTO v_role, v_statut
      FROM utilisateur WHERE id_utilisateur = p_id_utilisateur FOR SHARE;
    IF v_role IS NULL OR v_role <> 'voyageur' OR v_statut <> 'actif' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50006, MESSAGE_TEXT = 'Seul un voyageur actif peut réserver';
    END IF;
END//

-- Vérifie une place sur un voyage ; verrouille horaire, bus et compagnie en lecture.
-- p_controle_actif = 1 : contrôles d'une réservation ACTIVE (statut du voyage, départ, compagnie)
-- p_controle_actif = 0 : seulement l'existence du voyage et la capacité
CREATE PROCEDURE p_verifier_place(IN p_id_horaire INT UNSIGNED, IN p_numero_place SMALLINT UNSIGNED, IN p_controle_actif TINYINT)
BEGIN
    DECLARE v_places   SMALLINT UNSIGNED;
    DECLARE v_statut_h VARCHAR(20);
    DECLARE v_depart   DATETIME;
    DECLARE v_statut_c VARCHAR(20);

    SELECT b.nombre_places, h.statut, h.depart_dt, c.statut
      INTO v_places, v_statut_h, v_depart, v_statut_c
      FROM horaire h
      JOIN bus b       ON b.id_bus = h.id_bus
      JOIN trajet t    ON t.id_trajet = h.id_trajet
      JOIN compagnie c ON c.id_compagnie = t.id_compagnie
     WHERE h.id_horaire = p_id_horaire
       FOR SHARE OF h, b, c;

    IF v_places IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50001, MESSAGE_TEXT = 'Voyage inexistant';
    END IF;
    IF p_numero_place > v_places THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50002, MESSAGE_TEXT = 'Numéro de place supérieur à la capacité du bus';
    END IF;
    IF p_controle_actif = 1 THEN
        IF v_statut_h <> 'programme' THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50003, MESSAGE_TEXT = 'Ce voyage n''est plus disponible à la réservation';
        END IF;
        IF v_depart <= fn_maintenant_local() THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50004, MESSAGE_TEXT = 'Ce voyage est déjà parti';
        END IF;
        IF v_statut_c <> 'active' THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50005, MESSAGE_TEXT = 'La compagnie est suspendue';
        END IF;
    END IF;
END//

-- Cohérence d'un voyage (appelée par les triggers de horaire).
-- Le verrou FOR UPDATE sur la ligne du bus sérialise les créations/modifications de voyages
-- d'un même bus : le contrôle de chevauchement ne peut donc pas être contourné par concurrence.
CREATE PROCEDURE p_verifier_horaire(
    IN p_id_horaire INT UNSIGNED, IN p_id_trajet INT UNSIGNED, IN p_id_bus INT UNSIGNED,
    IN p_depart DATETIME, IN p_arrivee DATETIME, IN p_statut VARCHAR(20))
BEGIN
    DECLARE v_comp_bus    INT UNSIGNED;
    DECLARE v_comp_trajet INT UNSIGNED;
    DECLARE v_places      SMALLINT UNSIGNED;
    DECLARE v_conflits    INT;
    DECLARE v_max_place   SMALLINT UNSIGNED;

    SELECT id_compagnie, nombre_places INTO v_comp_bus, v_places
      FROM bus WHERE id_bus = p_id_bus FOR UPDATE;
    SELECT id_compagnie INTO v_comp_trajet
      FROM trajet WHERE id_trajet = p_id_trajet FOR SHARE;

    IF v_comp_bus IS NULL OR v_comp_trajet IS NULL OR v_comp_bus <> v_comp_trajet THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50010, MESSAGE_TEXT = 'Le bus doit appartenir à la compagnie du trajet';
    END IF;

    IF p_statut <> 'annule' THEN
        SELECT COUNT(*) INTO v_conflits
          FROM bus_occupation
         WHERE id_bus = p_id_bus
           AND debut < p_arrivee
           AND fin   > p_depart
           AND (p_id_horaire IS NULL OR id_horaire <> p_id_horaire)
           FOR UPDATE;
        IF v_conflits > 0 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50011, MESSAGE_TEXT = 'Le bus est déjà affecté à un autre voyage sur ce créneau';
        END IF;
    END IF;

    IF p_id_horaire IS NOT NULL THEN
        SELECT COALESCE(MAX(numero_place), 0) INTO v_max_place
          FROM reservation
         WHERE id_horaire = p_id_horaire AND numero_place_active IS NOT NULL
           FOR SHARE;
        IF v_max_place > v_places THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50012, MESSAGE_TEXT = 'Le bus ne peut pas accueillir les places déjà réservées';
        END IF;
    END IF;
END//

-- ----------------------------- COMPAGNIE / UTILISATEUR / BUS / TRAJET -----------------------------
CREATE TRIGGER trg_utilisateur_avant_update BEFORE UPDATE ON utilisateur FOR EACH ROW
BEGIN
    DECLARE v_nb INT;
    IF OLD.role = 'voyageur' AND NEW.role <> 'voyageur' THEN
        SELECT COUNT(*) INTO v_nb FROM reservation WHERE id_utilisateur = OLD.id_utilisateur FOR SHARE;
        IF v_nb > 0 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50017, MESSAGE_TEXT = 'Le rôle d''un voyageur ayant des réservations ne peut pas être modifié';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_bus_avant_update BEFORE UPDATE ON bus FOR EACH ROW
BEGIN
    DECLARE v_nb  INT;
    DECLARE v_max SMALLINT UNSIGNED;
    IF NEW.id_compagnie <> OLD.id_compagnie THEN
        SELECT COUNT(*) INTO v_nb FROM horaire WHERE id_bus = OLD.id_bus FOR SHARE;
        IF v_nb > 0 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50016, MESSAGE_TEXT = 'Un bus déjà programmé ne peut pas changer de compagnie';
        END IF;
    END IF;
    IF NEW.nombre_places < OLD.nombre_places THEN
        SELECT COALESCE(MAX(r.numero_place), 0) INTO v_max
          FROM reservation r JOIN horaire h ON h.id_horaire = r.id_horaire
         WHERE h.id_bus = OLD.id_bus AND h.statut = 'programme' AND r.numero_place_active IS NOT NULL
           FOR SHARE;
        IF v_max > NEW.nombre_places THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50012, MESSAGE_TEXT = 'Le bus ne peut pas accueillir les places déjà réservées';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_trajet_avant_update BEFORE UPDATE ON trajet FOR EACH ROW
BEGIN
    DECLARE v_nb INT;
    IF NEW.id_compagnie <> OLD.id_compagnie THEN
        SELECT COUNT(*) INTO v_nb FROM horaire WHERE id_trajet = OLD.id_trajet FOR SHARE;
        IF v_nb > 0 THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50016, MESSAGE_TEXT = 'Un trajet déjà programmé ne peut pas changer de compagnie';
        END IF;
    END IF;
END//

-- ------------------------------------- HORAIRE -------------------------------------
CREATE TRIGGER trg_horaire_avant_insert BEFORE INSERT ON horaire FOR EACH ROW
BEGIN
    -- Compatibilité : si date_arrivee est omise, elle est déduite des heures
    -- (arrivée après le départ = même jour ; avant = lendemain). Voyage de plus de 24 h :
    -- date_arrivee doit être fournie explicitement.
    IF NEW.date_arrivee IS NULL THEN
        SET NEW.date_arrivee = IF(NEW.heure_arrivee >= NEW.heure_depart, NEW.date_depart, NEW.date_depart + INTERVAL 1 DAY);
    END IF;
    CALL p_verifier_horaire(NULL, NEW.id_trajet, NEW.id_bus,
                            TIMESTAMP(NEW.date_depart, NEW.heure_depart),
                            TIMESTAMP(NEW.date_arrivee, NEW.heure_arrivee), NEW.statut);
END//

CREATE TRIGGER trg_horaire_avant_update BEFORE UPDATE ON horaire FOR EACH ROW
BEGIN
    DECLARE v_actives INT;
    IF OLD.statut IN ('annule', 'termine') AND NEW.statut <> OLD.statut THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50013, MESSAGE_TEXT = 'Un voyage annulé ou terminé ne peut plus changer de statut';
    END IF;
    IF (NEW.statut = 'annule' AND OLD.statut <> 'annule') OR NEW.id_trajet <> OLD.id_trajet THEN
        SELECT COUNT(*) INTO v_actives FROM reservation
         WHERE id_horaire = OLD.id_horaire AND numero_place_active IS NOT NULL FOR SHARE;
        IF v_actives > 0 THEN
            IF NEW.statut = 'annule' AND OLD.statut <> 'annule' THEN
                SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50014, MESSAGE_TEXT = 'Annuler d''abord les réservations actives de ce voyage';
            ELSE
                SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50015, MESSAGE_TEXT = 'Le trajet d''un voyage ayant des réservations actives ne peut pas changer';
            END IF;
        END IF;
    END IF;
    CALL p_verifier_horaire(OLD.id_horaire, NEW.id_trajet, NEW.id_bus,
                            TIMESTAMP(NEW.date_depart, NEW.heure_depart),
                            TIMESTAMP(NEW.date_arrivee, NEW.heure_arrivee), NEW.statut);
END//

CREATE TRIGGER trg_horaire_apres_insert AFTER INSERT ON horaire FOR EACH ROW
BEGIN
    IF NEW.statut <> 'annule' THEN
        INSERT INTO bus_occupation (id_horaire, id_bus, debut, fin)
        VALUES (NEW.id_horaire, NEW.id_bus, TIMESTAMP(NEW.date_depart, NEW.heure_depart), TIMESTAMP(NEW.date_arrivee, NEW.heure_arrivee));
    END IF;
END//

CREATE TRIGGER trg_horaire_apres_update AFTER UPDATE ON horaire FOR EACH ROW
BEGIN
    IF NEW.statut = 'annule' THEN
        DELETE FROM bus_occupation WHERE id_horaire = NEW.id_horaire;
    ELSE
        INSERT INTO bus_occupation (id_horaire, id_bus, debut, fin)
        VALUES (NEW.id_horaire, NEW.id_bus, TIMESTAMP(NEW.date_depart, NEW.heure_depart), TIMESTAMP(NEW.date_arrivee, NEW.heure_arrivee))
        ON DUPLICATE KEY UPDATE id_bus = VALUES(id_bus), debut = VALUES(debut), fin = VALUES(fin);
    END IF;
END//

-- ------------------------------------- RESERVATION -------------------------------------
CREATE TRIGGER trg_reservation_avant_insert BEFORE INSERT ON reservation FOR EACH ROW
BEGIN
    DECLARE v_tarif INT UNSIGNED;
    CALL p_verifier_voyageur(NEW.id_utilisateur);
    CALL p_verifier_place(NEW.id_horaire, NEW.numero_place, IF(NEW.statut = 'annulee', 0, 1));
    SELECT tarif_fcfa INTO v_tarif FROM horaire WHERE id_horaire = NEW.id_horaire;   -- ligne déjà verrouillée
    IF NEW.prix_fcfa IS NULL THEN
        SET NEW.prix_fcfa = v_tarif;                       -- prix convenu = tarif au moment de la réservation
    ELSEIF NEW.prix_fcfa <> v_tarif THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50009, MESSAGE_TEXT = 'Le prix de la réservation doit être le tarif du voyage';
    END IF;
    IF NEW.statut = 'annulee' THEN
        IF NEW.date_annulation IS NULL THEN SET NEW.date_annulation = NOW(); END IF;
    ELSE
        SET NEW.date_annulation = NULL;
    END IF;
END//

CREATE TRIGGER trg_reservation_avant_update BEFORE UPDATE ON reservation FOR EACH ROW
BEGIN
    IF NEW.id_utilisateur <> OLD.id_utilisateur OR NEW.id_horaire <> OLD.id_horaire
       OR NEW.numero_ticket <> OLD.numero_ticket OR NEW.prix_fcfa <> OLD.prix_fcfa
       OR NEW.date_reservation <> OLD.date_reservation THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50007,
            MESSAGE_TEXT = 'Utilisateur, voyage, ticket, prix et date de réservation sont immuables (annuler puis réserver à nouveau)';
    END IF;
    IF OLD.statut = 'confirmee' AND NEW.statut = 'en_attente' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50008, MESSAGE_TEXT = 'Une réservation confirmée ne peut pas repasser en attente';
    END IF;

    IF NEW.statut = 'annulee' THEN
        IF OLD.statut <> 'annulee' THEN
            SET NEW.date_annulation = NOW();
        ELSE
            SET NEW.date_annulation = OLD.date_annulation;
        END IF;
        IF NEW.numero_place <> OLD.numero_place THEN
            CALL p_verifier_place(NEW.id_horaire, NEW.numero_place, 0);
        END IF;
    ELSE
        IF OLD.statut = 'annulee' THEN
            CALL p_verifier_voyageur(NEW.id_utilisateur);                  -- réactivation
            CALL p_verifier_place(NEW.id_horaire, NEW.numero_place, 1);
        ELSEIF NEW.numero_place <> OLD.numero_place THEN
            CALL p_verifier_place(NEW.id_horaire, NEW.numero_place, 1);    -- changement de siège
        END IF;
        SET NEW.date_annulation = NULL;
    END IF;
END//

-- -------------------------------------- PAIEMENT --------------------------------------
CREATE TRIGGER trg_paiement_avant_insert BEFORE INSERT ON paiement FOR EACH ROW
BEGIN
    DECLARE v_statut_r VARCHAR(20);
    DECLARE v_prix     INT UNSIGNED;
    SELECT statut, prix_fcfa INTO v_statut_r, v_prix
      FROM reservation WHERE id_reservation = NEW.id_reservation FOR UPDATE;
    IF v_statut_r IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50020, MESSAGE_TEXT = 'Réservation inexistante';
    END IF;
    IF NEW.statut = 'rembourse' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50021, MESSAGE_TEXT = 'Un paiement ne peut pas être créé directement au statut rembourse (utiliser remboursement)';
    END IF;
    IF NEW.statut = 'initie' AND v_statut_r = 'annulee' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50022, MESSAGE_TEXT = 'Aucune nouvelle tentative de paiement sur une réservation annulée';
    END IF;
    IF NEW.montant_fcfa <> v_prix THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50023, MESSAGE_TEXT = 'Le montant doit être égal au prix convenu de la réservation';
    END IF;
END//

CREATE TRIGGER trg_paiement_avant_update BEFORE UPDATE ON paiement FOR EACH ROW
BEGIN
    -- réservation, montant et date sont toujours immuables ; mode et référence ne peuvent être précisés
    -- que tant que le paiement est 'initie' (l'opérateur réel n'est connu qu'à l'issue du paiement)
    IF NEW.id_reservation <> OLD.id_reservation OR NEW.montant_fcfa <> OLD.montant_fcfa
       OR NEW.date_paiement <> OLD.date_paiement
       OR (OLD.statut <> 'initie' AND (NEW.mode <> OLD.mode
           OR (OLD.reference_transaction IS NOT NULL AND NOT (NEW.reference_transaction <=> OLD.reference_transaction)))) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50024,
            MESSAGE_TEXT = 'Réservation, montant et date sont immuables ; mode et référence sont figés dès que le paiement n''est plus initié';
    END IF;
    IF NEW.statut <> OLD.statut THEN
        IF OLD.statut = 'reussi' AND NEW.statut = 'rembourse' THEN
            IF NEW.rembourse_reussi_fcfa <> OLD.montant_fcfa THEN
                SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50026, MESSAGE_TEXT = 'Le statut rembourse exige des remboursements réussis couvrant tout le montant';
            END IF;
        ELSEIF NOT (OLD.statut = 'initie' AND NEW.statut IN ('reussi', 'echoue')) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50025, MESSAGE_TEXT = 'Transition de statut de paiement interdite';
        END IF;
    END IF;
END//

-- ------------------------------------ REMBOURSEMENT ------------------------------------
-- La ligne du paiement est verrouillée (FOR UPDATE) puis ses compteurs sont mis à jour :
-- deux remboursements concurrents du même paiement sont donc sérialisés et le plafond
-- (CHECK ck_paiement_rembourse) ne peut pas être dépassé. Dès que les remboursements réussis
-- couvrent tout le montant, le paiement passe automatiquement à 'rembourse'.
CREATE TRIGGER trg_remboursement_avant_insert BEFORE INSERT ON remboursement FOR EACH ROW
BEGIN
    DECLARE v_statut_p  VARCHAR(20);
    DECLARE v_montant_p INT UNSIGNED;
    DECLARE v_engage    INT UNSIGNED;
    DECLARE v_delta_r   INT UNSIGNED;
    SELECT statut, montant_fcfa, rembourse_engage_fcfa INTO v_statut_p, v_montant_p, v_engage
      FROM paiement WHERE id_paiement = NEW.id_paiement FOR UPDATE;
    IF v_statut_p IS NULL OR v_statut_p <> 'reussi' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50030, MESSAGE_TEXT = 'Seul un paiement réussi peut être remboursé';
    END IF;
    IF NEW.statut = 'echoue' THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50032, MESSAGE_TEXT = 'Un remboursement ne peut pas être créé directement échoué';
    END IF;
    IF v_engage + NEW.montant_fcfa > v_montant_p THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50031, MESSAGE_TEXT = 'Le total remboursé ne peut pas dépasser le montant du paiement';
    END IF;
    SET v_delta_r = IF(NEW.statut = 'reussi', NEW.montant_fcfa, 0);
    UPDATE paiement
       SET statut = IF(rembourse_reussi_fcfa + v_delta_r = montant_fcfa, 'rembourse', statut),
           rembourse_engage_fcfa = rembourse_engage_fcfa + NEW.montant_fcfa,
           rembourse_reussi_fcfa = rembourse_reussi_fcfa + v_delta_r
     WHERE id_paiement = NEW.id_paiement;
END//

CREATE TRIGGER trg_remboursement_avant_update BEFORE UPDATE ON remboursement FOR EACH ROW
BEGIN
    IF NEW.id_paiement <> OLD.id_paiement OR NEW.montant_fcfa <> OLD.montant_fcfa
       OR NEW.date_remboursement <> OLD.date_remboursement
       OR (OLD.reference_transaction IS NOT NULL AND NOT (NEW.reference_transaction <=> OLD.reference_transaction)) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50033, MESSAGE_TEXT = 'Paiement, montant, date et référence (une fois renseignée) d''un remboursement sont immuables';
    END IF;
    IF NEW.statut <> OLD.statut THEN
        IF NOT (OLD.statut = 'initie' AND NEW.statut IN ('reussi', 'echoue')) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 50033, MESSAGE_TEXT = 'Transition de statut de remboursement interdite';
        END IF;
        IF NEW.statut = 'reussi' THEN
            -- la ligne du paiement est verrouillée par l'UPDATE ; l'ordre des affectations compte :
            -- statut est évalué avec les anciens compteurs
            UPDATE paiement
               SET statut = IF(rembourse_reussi_fcfa + OLD.montant_fcfa = montant_fcfa, 'rembourse', statut),
                   rembourse_reussi_fcfa = rembourse_reussi_fcfa + OLD.montant_fcfa
             WHERE id_paiement = OLD.id_paiement;
        ELSE
            UPDATE paiement
               SET rembourse_engage_fcfa = rembourse_engage_fcfa - OLD.montant_fcfa
             WHERE id_paiement = OLD.id_paiement;
        END IF;
    END IF;
END//

DELIMITER ;

-- ---------------------------------------------------------------------
-- VUES (dates et heures renvoyées en texte 'AAAA-MM-JJ' et 'HH:MM', comme dans la version d'origine)
-- Les colonnes d'origine sont conservées dans le même ordre ; les nouvelles sont ajoutées à la fin.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_places_horaire AS
SELECT
    h.id_horaire, t.id_compagnie, c.nom AS compagnie,
    t.ville_depart, t.ville_arrivee,
    DATE_FORMAT(h.date_depart, '%Y-%m-%d')  AS date_depart,
    TIME_FORMAT(h.heure_depart, '%H:%i')    AS heure_depart,
    TIME_FORMAT(h.heure_arrivee, '%H:%i')   AS heure_arrivee,
    t.duree_estimee, h.tarif_fcfa, h.statut, b.nombre_places,
    -- COUNT(numero_place_active) ne compte que les réservations actives (colonne NULL si annulée)
    CAST(b.nombre_places AS SIGNED) - (SELECT COUNT(r.numero_place_active) FROM reservation r
                       WHERE r.id_horaire = h.id_horaire) AS places_libres,
    DATE_FORMAT(h.date_arrivee, '%Y-%m-%d') AS date_arrivee
FROM horaire h
JOIN trajet    t ON t.id_trajet    = h.id_trajet
JOIN compagnie c ON c.id_compagnie = t.id_compagnie
JOIN bus       b ON b.id_bus       = h.id_bus;

-- tarif_fcfa = prix CONVENU de la réservation (figé) ; tarif_actuel_fcfa = tarif courant du voyage
CREATE OR REPLACE VIEW v_reservation_detail AS
SELECT
    r.id_reservation, r.numero_ticket, r.statut, r.date_reservation,
    r.id_utilisateur, r.nom_passager, r.prenom_passager, r.telephone_passager, r.numero_place,
    h.id_horaire, t.id_compagnie, c.nom AS compagnie,
    t.ville_depart, t.ville_arrivee,
    DATE_FORMAT(h.date_depart, '%Y-%m-%d')  AS date_depart,
    TIME_FORMAT(h.heure_depart, '%H:%i')    AS heure_depart,
    TIME_FORMAT(h.heure_arrivee, '%H:%i')   AS heure_arrivee,
    r.prix_fcfa                             AS tarif_fcfa,
    h.tarif_fcfa                            AS tarif_actuel_fcfa,
    DATE_FORMAT(h.date_arrivee, '%Y-%m-%d') AS date_arrivee,
    r.date_annulation
FROM reservation r
JOIN horaire   h ON h.id_horaire   = r.id_horaire
JOIN trajet    t ON t.id_trajet    = h.id_trajet
JOIN compagnie c ON c.id_compagnie = t.id_compagnie;

CREATE OR REPLACE VIEW v_stats_globales AS
SELECT
    (SELECT COUNT(*) FROM v_reservation_detail
       WHERE DATE(date_reservation) = CURDATE() AND statut <> 'annulee')  AS reservations_du_jour,
    (SELECT COUNT(*) FROM v_places_horaire WHERE statut = 'programme')     AS trajets_actifs,
    (SELECT COUNT(*) FROM utilisateur WHERE role = 'voyageur')             AS utilisateurs_inscrits,
    (SELECT ROUND(100 * (SUM(nombre_places) - SUM(places_libres)) / SUM(nombre_places), 0)
       FROM v_places_horaire WHERE statut = 'programme')                   AS taux_remplissage_pct;

CREATE OR REPLACE VIEW v_stats_compagnie AS
SELECT
    c.id_compagnie, c.nom AS compagnie,
    (SELECT COUNT(*) FROM v_reservation_detail d
       WHERE d.id_compagnie = c.id_compagnie
         AND DATE(d.date_reservation) = CURDATE() AND d.statut <> 'annulee') AS reservations_du_jour,
    (SELECT COUNT(*) FROM v_places_horaire p
       WHERE p.id_compagnie = c.id_compagnie AND p.statut = 'programme')      AS trajets_actifs,
    (SELECT ROUND(100 * (SUM(p.nombre_places) - SUM(p.places_libres)) / SUM(p.nombre_places), 0)
       FROM v_places_horaire p
       WHERE p.id_compagnie = c.id_compagnie AND p.statut = 'programme')      AS taux_remplissage_pct
FROM compagnie c;

-- Situation financière par réservation (montants exacts en FCFA, entiers)
CREATE OR REPLACE VIEW v_solde_reservation AS
SELECT
    r.id_reservation, r.numero_ticket, r.statut AS statut_reservation, r.prix_fcfa,
    COALESCE(p.paye_fcfa, 0)                          AS paye_fcfa,
    COALESCE(rb.rembourse_fcfa, 0)                    AS rembourse_fcfa,
    CAST(COALESCE(p.paye_fcfa, 0) AS SIGNED) - CAST(COALESCE(rb.rembourse_fcfa, 0) AS SIGNED) AS net_encaisse_fcfa
FROM reservation r
LEFT JOIN (SELECT id_reservation, SUM(montant_fcfa) AS paye_fcfa
             FROM paiement WHERE statut IN ('reussi', 'rembourse') GROUP BY id_reservation) p
       ON p.id_reservation = r.id_reservation
LEFT JOIN (SELECT pa.id_reservation, SUM(rm.montant_fcfa) AS rembourse_fcfa
             FROM remboursement rm JOIN paiement pa ON pa.id_paiement = rm.id_paiement
            WHERE rm.statut = 'reussi' GROUP BY pa.id_reservation) rb
       ON rb.id_reservation = r.id_reservation;

-- Écarts à traiter par le backend / la comptabilité (la base ne décide pas à leur place)
CREATE OR REPLACE VIEW v_anomalies_financieres AS
SELECT s.id_reservation, NULL AS id_paiement, 'annulee_avec_encaissement_non_rembourse' AS anomalie
  FROM v_solde_reservation s WHERE s.statut_reservation = 'annulee' AND s.net_encaisse_fcfa > 0
UNION ALL
SELECT s.id_reservation, NULL, 'confirmee_sans_paiement_reussi'
  FROM v_solde_reservation s WHERE s.statut_reservation = 'confirmee' AND s.paye_fcfa = 0
UNION ALL
SELECT s.id_reservation, NULL, 'en_attente_deja_payee'
  FROM v_solde_reservation s WHERE s.statut_reservation = 'en_attente' AND s.paye_fcfa > 0
UNION ALL
SELECT pa.id_reservation, pa.id_paiement, 'rembourse_sans_trace_de_remboursement'
  FROM paiement pa
 WHERE pa.statut = 'rembourse'
   AND pa.montant_fcfa <> (SELECT COALESCE(SUM(rm.montant_fcfa), 0) FROM remboursement rm
                            WHERE rm.id_paiement = pa.id_paiement AND rm.statut = 'reussi');

