# Bilancio Personale — API Scadenze per xSpese

Contratto JSON usato dalla sezione **Scadenze** nativa di xSpese.

## Convenzioni

- Base URL predefinito: `http://100.112.193.68:3030`
- Autenticazione: header `x-api-token`
- Richieste e risposte: `application/json`
- Date civili: `YYYY-MM-DD`
- Date e orari: ISO 8601
- Fuso di riferimento: `Europe/Rome`
- Risposte riuscite: `{ "ok": true, ... }`

Errore consigliato:

```json
{
  "ok": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "data_scadenza è obbligatoria",
    "fields": {
      "data_scadenza": "Campo obbligatorio"
    }
  }
}
```

L'app mostra `error.message`, una stringa `error` oppure `message` quando presenti.

## Modello

```json
{
  "id": 42,
  "scadenza_uuid": "4F39932E-BC57-4E94-9101-1C30F64E27CF",
  "titolo": "Bolletta elettrica",
  "descrizione": "Fattura luglio/agosto",
  "data_scadenza": "2026-08-31",
  "importo": 87.40,
  "valuta": "EUR",
  "utente_id": 1,
  "utente": "Antonio",
  "categoria_id": 3,
  "categoria": "Casa",
  "stato": "aperta",
  "priorita": "normale",
  "note": "Addebito su Fineco",
  "promemoria_giorni": [7, 1, 0],
  "ricorrenza": {
    "tipo": "mensile",
    "intervallo": 1,
    "fine": null
  },
  "movimento_id": null,
  "completata_il": null,
  "created_at": "2026-08-19T08:30:00.000Z",
  "updated_at": "2026-08-19T08:30:00.000Z"
}
```

Valori supportati:

- `stato`: `aperta`, `completata`, `annullata`
- `priorita`: `bassa`, `normale`, `alta`
- `ricorrenza.tipo`: `giornaliera`, `settimanale`, `mensile`, `annuale`

`importo`, `descrizione`, `categoria_id`, `note`, `ricorrenza`, `movimento_id` e `completata_il` possono essere `null`. `scadenza_uuid` deve essere univoco per rendere la creazione idempotente.

## Elenco

### GET `/api/scadenze`

Query usate dal client:

| Campo | Valori |
|---|---|
| `stato` | `aperte`, `completate`, `annullate`, `tutte` |
| `dal` | data facoltativa `YYYY-MM-DD` |
| `al` | data facoltativa `YYYY-MM-DD` |
| `q` | ricerca facoltativa |
| `limit` | da 1 a 500 |

Risposta:

```json
{
  "ok": true,
  "scadenze": [],
  "totale": 0,
  "server_time": "2026-08-19T08:31:00.000Z"
}
```

`scadenze` deve essere sempre presente, anche quando vuoto.

## Dettaglio

### GET `/api/scadenze/:id`

```json
{
  "ok": true,
  "scadenza": {
    "id": 42,
    "scadenza_uuid": "4F39932E-BC57-4E94-9101-1C30F64E27CF",
    "titolo": "Bolletta elettrica",
    "data_scadenza": "2026-08-31",
    "utente_id": 1,
    "stato": "aperta"
  }
}
```

La risorsa reale deve contenere tutti i campi non opzionali del modello.

## Creazione

### POST `/api/scadenze`

```json
{
  "scadenza_uuid": "4F39932E-BC57-4E94-9101-1C30F64E27CF",
  "titolo": "Bolletta elettrica",
  "descrizione": "Fattura luglio/agosto",
  "data_scadenza": "2026-08-31",
  "importo": 87.40,
  "valuta": "EUR",
  "utente_id": 1,
  "categoria_id": 3,
  "priorita": "normale",
  "note": null,
  "promemoria_giorni": [7, 1, 0],
  "ricorrenza": null
}
```

Risposta `201`:

```json
{
  "ok": true,
  "saved": true,
  "scadenza": {}
}
```

`scadenza` contiene la risorsa completa. Se lo stesso `scadenza_uuid` viene inviato nuovamente, il server non crea duplicati.

## Modifica

### PATCH `/api/scadenze/:id`

Il client invia il modello modificabile completo. I valori `null` servono a cancellare un campo facoltativo:

```json
{
  "scadenza_uuid": "4F39932E-BC57-4E94-9101-1C30F64E27CF",
  "titolo": "Bolletta elettrica",
  "descrizione": null,
  "data_scadenza": "2026-09-05",
  "importo": 92.10,
  "valuta": "EUR",
  "utente_id": 1,
  "categoria_id": 3,
  "priorita": "alta",
  "note": null,
  "promemoria_giorni": [3, 1],
  "ricorrenza": null
}
```

Il client rilegge poi la risorsa con `GET /api/scadenze/:id`.

## Completamento

### POST `/api/scadenze/:id/completa`

Senza movimento:

```json
{
  "completata_il": "2026-08-30T18:20:00.000Z",
  "crea_movimento": false
}
```

Con movimento:

```json
{
  "completata_il": "2026-08-30T18:20:00.000Z",
  "crea_movimento": true,
  "movimento": {
    "transaction_uuid": "1CF6DA5D-E2CE-4A00-A5AF-310857BE2CD6",
    "data_pagamento": "2026-08-30 20:20:00",
    "importo": 87.40,
    "valuta": "EUR",
    "esercente": "Fornitore energia",
    "metodo_pagamento": "Manuale",
    "carta": "Fineco",
    "note": "Pagamento bolletta"
  }
}
```

Il server ricava `utente_id` e `categoria_id` dalla scadenza. Completamento e creazione del movimento devono avvenire nella stessa transazione database. Per una ricorrenza, il server può creare la prossima occorrenza in questo momento.

## Riapertura

### POST `/api/scadenze/:id/riapri`

Nessun body obbligatorio. La risposta usa `{ "ok": true, "saved": true }`. Il client rilegge poi il dettaglio.

Se esiste un movimento associato, il server non deve eliminarlo automaticamente; può restituire `409`.

## Eliminazione

### DELETE `/api/scadenze/:id`

Risposta accettata con body:

```json
{
  "ok": true,
  "deleted": true,
  "id": 42
}
```

È accettata anche una risposta `204` senza body. È consigliata la cancellazione logica tramite `deleted_at`. L'eventuale movimento collegato non deve essere eliminato.

## Comportamento delle ricorrenze

```json
{
  "ricorrenza": {
    "tipo": "mensile",
    "intervallo": 2,
    "fine": "2027-12-31"
  }
}
```

`intervallo: 2` significa ogni due unità. La prima versione dell'app modifica la singola occorrenza; eventuali operazioni `future` o `serie` potranno essere aggiunte successivamente.

## Promemoria

L'app pianifica notifiche locali alle 09:00, ora di Roma, usando `promemoria_giorni`. Per esempio `[7, 1, 0]` indica sette giorni prima, un giorno prima e il giorno stesso. Vengono pianificati al massimo 60 promemoria futuri per rispettare i limiti di iOS.

## Codici HTTP

| Codice | Uso |
|---:|---|
| `200` | Lettura o modifica riuscita |
| `201` | Creazione riuscita |
| `204` | Eliminazione riuscita senza body |
| `400` | Richiesta non valida |
| `401` / `403` | Token mancante o non valido |
| `404` | Scadenza inesistente |
| `409` | UUID duplicato o conflitto di stato |
| `422` | Validazione fallita |
| `500` | Errore interno |

## Checklist

- [x] Elenco con filtri di stato
- [x] Dettaglio
- [x] Creazione idempotente
- [x] Modifica e cancellazione dei valori opzionali
- [x] Completamento con movimento facoltativo
- [x] Riapertura
- [x] Eliminazione
- [x] Categorie e utenti condivisi con i movimenti
- [x] Ricorrenze
- [x] Promemoria
