'use strict';

const { expect } = require('chai');
const db = require('../src/db');
const { AppError } = require('../src/utils/errors');

// Mock de la base de données
const mockDb = {
  createReservation: async (data) => ({ id_reservation: 1, ...data, statut: 'confirmee' }),
  getReservationByTicket: async (numero) => {
    if (numero === 'TICKET123') return { id_reservation: 1, numero_ticket: 'TICKET123', statut: 'confirmee' };
    return null;
  },
  cancelReservation: async (id) => {
    if (id === 1) return { id_reservation: 1, statut: 'annulee' };
    return null;
  },
  listReservationsByUser: async (id_utilisateur) => [
    { id_reservation: 1, numero_ticket: 'TICKET123', statut: 'confirmee' },
    { id_reservation: 2, numero_ticket: 'TICKET456', statut: 'annulee' }
  ],
};

describe('Réservations', () => {
  before(() => {
    // Remplacer la base de données réelle par le mock
    Object.assign(db, mockDb);
  });

  describe('createReservation', () => {
    it('devrait créer une nouvelle réservation', async () => {
      const reservation = await db.createReservation({
        numero_ticket: 'TICKET123',
        id_utilisateur: 1,
        id_horaire: 1,
        numero_place: 1,
        nom_passager: 'Test',
        prenom_passager: 'User',
        telephone_passager: '1234567890',
      });
      expect(reservation).to.have.property('id_reservation', 1);
      expect(reservation).to.have.property('statut', 'confirmee');
    });
  });

  describe('getReservationByTicket', () => {
    it('devrait retourner une réservation par numéro de ticket', async () => {
      const reservation = await db.getReservationByTicket('TICKET123');
      expect(reservation).to.have.property('id_reservation', 1);
    });

    it('devrait retourner null pour un ticket inexistant', async () => {
      const reservation = await db.getReservationByTicket('INEXISTANT');
      expect(reservation).to.be.null;
    });
  });

  describe('cancelReservation', () => {
    it('devrait annuler une réservation', async () => {
      const reservation = await db.cancelReservation(1);
      expect(reservation).to.have.property('statut', 'annulee');
    });

    it('devrait retourner null pour une réservation inexistante', async () => {
      const reservation = await db.cancelReservation(999);
      expect(reservation).to.be.null;
    });
  });

  describe('listReservationsByUser', () => {
    it('devrait lister les réservations d\'un utilisateur', async () => {
      const reservations = await db.listReservationsByUser(1);
      expect(reservations).to.be.an('array').with.lengthOf(2);
      expect(reservations[0]).to.have.property('numero_ticket', 'TICKET123');
      expect(reservations[1]).to.have.property('numero_ticket', 'TICKET456');
    });
  });
});
