'use strict';

const { expect } = require('chai');
const authService = require('../src/services/authService');
const db = require('../src/db');
const { AppError } = require('../src/utils/errors');
const { hashPassword } = require('../src/services/passwords');

// Mock de la base de données
let mockUsers = [];

const mockDb = {
  findUserByEmail: async (email) => mockUsers.find(u => u.email === email) || null,
  findUserById: async (id) => mockUsers.find(u => u.id_utilisateur === id) || null,
  createUser: async (d) => {
    const u = { id_utilisateur: mockUsers.length + 1, ...d };
    mockUsers.push(u);
    return u;
  },
  updateUser: async (id, patch) => {
    const u = mockUsers.find(u => u.id_utilisateur === id);
    if (u) Object.assign(u, patch);
    return u;
  },
};

describe('AuthService', () => {
  before(async () => {
    // Remplacer la base de données réelle par le mock
    Object.assign(db, mockDb);

    // Créer un utilisateur de test avec un vrai hash
    const hash = await hashPassword('motdepasse');
    mockUsers.push({
      id_utilisateur: 1,
      email: 'test@example.com',
      mot_de_passe_hache: hash,
      statut: 'actif',
      role: 'voyageur',
      nom: 'Test',
      prenom: 'User',
      consentement_version: '2026-10'
    });
  });

  describe('login', () => {
    it('devrait connecter un utilisateur avec des identifiants valides', async () => {
      const user = await authService.login('test@example.com', 'motdepasse');
      expect(user).to.have.property('id_utilisateur', 1);
    });

    it('devrait rejeter les identifiants invalides', async () => {
      try {
        await authService.login('test@example.com', 'mauvaismotdepasse');
        throw new Error('Devrait avoir échoué');
      } catch (e) {
        expect(e).to.be.instanceOf(AppError);
        expect(e.code).to.equal('BAD_CREDENTIALS');
      }
    });
  });

  describe('register', () => {
    it('devrait créer un nouvel utilisateur', async () => {
      const user = await authService.register({
        nom: 'Nouveau',
        prenom: 'User',
        email: 'new@example.com',
        telephone: '1234567890',
        mot_de_passe: 'motdepasse',
        consentement: true,
      });
      expect(user).to.have.property('email', 'new@example.com');
    });

    it('devrait rejeter les e-mails en double', async () => {
      try {
        await authService.register({
          nom: 'Test',
          prenom: 'User',
          email: 'test@example.com',
          telephone: '1234567890',
          mot_de_passe: 'motdepasse',
          consentement: true,
        });
        throw new Error('Devrait avoir échoué');
      } catch (e) {
        expect(e).to.be.instanceOf(AppError);
        expect(e.code).to.equal('DUPLICATE_EMAIL');
      }
    });
  });

  describe('changePassword', () => {
    it('devrait changer le mot de passe d\'un utilisateur', async () => {
      // On utilise l'utilisateur 1 qui a 'motdepasse'
      await authService.changePassword(1, 'motdepasse', 'nouveaumotdepasse');
      // On vérifie en essayant de se connecter avec le nouveau
      const user = await authService.login('test@example.com', 'nouveaumotdepasse');
      expect(user).to.have.property('id_utilisateur', 1);
    });

    it('devrait rejeter un mot de passe actuel incorrect', async () => {
      try {
        // Le mot de passe est maintenant 'nouveaumotdepasse'
        await authService.changePassword(1, 'mauvaismotdepasse', 'autre');
        throw new Error('Devrait avoir échoué');
      } catch (e) {
        expect(e).to.be.instanceOf(AppError);
        expect(e.code).to.equal('BAD_PASSWORD');
      }
    });
  });
});
