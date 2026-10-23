'use strict';
const config = require('../config');

let transporter = null;
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function getTransporter() {
  if (!config.smtp.host) return null;
  if (!transporter) {
    const nodemailer = require('nodemailer');
    transporter = nodemailer.createTransport({
      host: config.smtp.host, port: config.smtp.port, secure: config.smtp.secure,
      auth: config.smtp.user ? { user: config.smtp.user, pass: config.smtp.pass } : undefined,
    });
  }
  return transporter;
}

/** Envoie un e-mail. Ne bloque jamais la réservation : en cas d'échec, l'erreur est seulement affichée dans la console. */
async function sendMail({ to, subject, text, html }) {
  const t = getTransporter();
  if (!t) { console.log(`[e-mail désactivé] pour ${to} : ${subject}`); return false; }
  try { await t.sendMail({ from: config.smtp.from, to, subject, text, html }); return true; }
  catch (e) { console.error('[e-mail] échec de l\'envoi :', e.message); return false; }
}

async function sendTicketEmail(to, r) {
  const lien = `${config.baseUrl}/ticket.html?n=${encodeURIComponent(r.numero_ticket)}`;
  const resume = `${r.ville_depart} - ${r.ville_arrivee}, le ${r.date_depart} à ${r.heure_depart}, place ${r.numero_place}`;
  return sendMail({
    to,
    subject: `Votre ticket ${r.numero_ticket} - ${config.appName}`,
    text: `Bonjour ${r.prenom_passager},\n\nVotre réservation est confirmée.\nTicket : ${r.numero_ticket}\nVoyage : ${resume}\nCompagnie : ${r.compagnie_nom}\n\nVotre ticket : ${lien}\n\nBon voyage !\n${config.appName}`,
    html: `<div style="font-family:Arial,sans-serif;max-width:520px"><h2 style="color:#1F3A5F">Votre réservation est confirmée</h2>
      <p>Bonjour ${esc(r.prenom_passager)},</p><p><strong>Ticket : ${esc(r.numero_ticket)}</strong><br>${esc(resume)}<br>Compagnie : ${esc(r.compagnie_nom)}</p>
      <p><a href="${esc(lien)}" style="background:#F28C28;color:#1F3A5F;padding:10px 18px;border-radius:6px;text-decoration:none;font-weight:bold">Voir mon ticket</a></p>
      <p style="color:#5B6770">Bon voyage ! L'équipe ${esc(config.appName)}</p></div>`,
  });
}

/**
 * Envoie un code de confirmation. Contrairement aux autres e-mails, un échec est une ERREUR (l'utilisateur doit savoir que rien n'est parti).
 * Sans SMTP configuré : en développement le code est affiché dans la console du serveur ; en production l'envoi est refusé.
 */
async function sendCodeEmail(to, { code, motif }) {
  const minutes = config.codes.ttlMinutes;
  const titre = motif === 'reset' ? 'Réinitialisation de votre mot de passe' : 'Confirmez votre adresse e-mail';
  const intro = motif === 'reset' ? 'Voici le code pour choisir un nouveau mot de passe :' : `Bienvenue sur ${config.appName} ! Voici votre code de confirmation :`;
  if (!getTransporter()) {
    if (config.isProd) { const { AppError } = require('../utils/errors'); throw new AppError(503, "L'envoi d'e-mails n'est pas configuré sur ce site. Contactez le service client.", 'MAIL_OFF'); }
    console.log(`\n  [CODE DE CONFIRMATION - mode développement, SMTP non configuré] ${to} : ${code}  (valable ${minutes} min)\n`);
    return true;
  }
  const ok = await sendMail({
    to,
    subject: `${code} est votre code ${config.appName}`,
    text: `${titre}\n\n${intro}\n\n${code}\n\nCe code est valable ${minutes} minutes. Si vous n'êtes pas à l'origine de cette demande, ignorez ce message : rien ne sera modifié.\n${config.appName}`,
    html: `<div style="font-family:Arial,sans-serif;max-width:480px"><h2 style="color:#1F3A5F">${esc(titre)}</h2><p>${esc(intro)}</p>
      <p style="font-size:34px;letter-spacing:8px;font-weight:bold;color:#1F3A5F;background:#F2F5F8;padding:14px 18px;border-radius:8px;text-align:center">${esc(code)}</p>
      <p style="color:#5B6770">Ce code est valable ${minutes} minutes. Si vous n'êtes pas à l'origine de cette demande, ignorez ce message : rien ne sera modifié.</p>
      <p style="color:#5B6770">L'équipe ${esc(config.appName)}</p></div>`,
  });
  if (!ok) { const { AppError } = require('../utils/errors'); throw new AppError(502, "Impossible d'envoyer l'e-mail pour le moment. Vérifiez l'adresse ou réessayez dans un instant.", 'MAIL_FAIL'); }
  return true;
}
module.exports = { sendMail, sendTicketEmail, sendCodeEmail };
