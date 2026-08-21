# Changelog

Tutte le modifiche rilevanti di xSpese vengono documentate in questo file.

## 0.2.0 - 2026-08-21

- Nuova scheda Prestiti con riepilogo, filtri e ricerca.
- Creazione, modifica, dettaglio ed eliminazione dei prestiti.
- Registrazione delle rate e creazione facoltativa del movimento associato.
- Importazione idempotente delle rate passate.
- Supporto ai campi storici del server e specifica completa delle API JSON.

## 0.1.1 - 2026-08-20

- Build GitHub allineata a Xcode 26.6 e SDK iOS 26.5, come la build locale.
- Entitlement App Group preservato nell'IPA per la rifirma di SideStore.
- Rilevamento automatico dell'App Group rimappato da SideStore con il Team ID Apple.
- Cache dei widget condivisa anche tramite file atomici nel contenitore App Group.
- Aggiornamento dei widget quando xSpese torna in primo piano.

## 0.1.0 - 2026-08-20

- Prima build distribuibile come IPA tramite GitHub Releases.
- Registrazione delle spese con inserimento manuale e App Intent.
- Sincronizzazione con il server Raspberry Pi tramite Meshnet.
- Dashboard, movimenti server, regole esercenti e gestione delle scadenze.
- Widget per scadenze, spese mensili, sincronizzazione e panoramica.
