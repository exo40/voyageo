'use strict';
/**
 * PHOTOS (bus, chauffeurs) : le navigateur redimensionne l'image, l'envoie en « data URL », le serveur la contrôle
 * (type RÉEL du fichier, taille) puis l'enregistre dans data/uploads/ sous un nom aléatoire. Seule l'adresse
 * « /uploads/<nom> » est gardée en base. Aucun nom de fichier fourni par l'utilisateur n'est jamais utilisé.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const config = require('../config');
const { AppError } = require('../utils/errors');

const DIR = path.join(config.root, 'data', 'uploads');
const MAX_BYTES = 1.5 * 1024 * 1024;
const URL_RE = /^\/uploads\/[a-f0-9]{16}\.(jpg|png|webp)$/;

function detect(buf) {
  if (buf.length > 12 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpg';
  if (buf.length > 12 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (buf.length > 12 && buf.subarray(0, 4).toString('latin1') === 'RIFF' && buf.subarray(8, 12).toString('latin1') === 'WEBP') return 'webp';
  return null;
}

async function saveImage(dataUrl) {
  const m = /^data:image\/(?:jpeg|png|webp);base64,([A-Za-z0-9+/]+={0,2})$/.exec(String(dataUrl || ''));
  if (!m) throw new AppError(400, 'Image invalide. Formats acceptés : JPEG, PNG ou WebP.', 'VALIDATION');
  const buf = Buffer.from(m[1], 'base64');
  if (!buf.length) throw new AppError(400, 'Image vide.', 'VALIDATION');
  if (buf.length > MAX_BYTES) throw new AppError(413, 'Image trop lourde (1,5 Mo maximum).', 'TOO_LARGE');
  const ext = detect(buf);
  if (!ext) throw new AppError(400, "Ce fichier n'est pas une image JPEG, PNG ou WebP valide.", 'VALIDATION');
  fs.mkdirSync(DIR, { recursive: true });
  const name = `${crypto.randomBytes(8).toString('hex')}.${ext}`;
  fs.writeFileSync(path.join(DIR, name), buf);
  return `/uploads/${name}`;
}

/** Supprime l'ancien fichier quand une photo est remplacée (sans erreur s'il n'existe plus). */
function removeImage(url) {
  if (!url || !URL_RE.test(url)) return;
  try { fs.unlinkSync(path.join(DIR, path.basename(url))); } catch { /* déjà supprimé */ }
}
module.exports = { saveImage, removeImage, DIR, URL_RE, MAX_BYTES };
