# xSpese - API JSON Prestiti

Contratto usato dalla sezione nativa **Prestiti** di xSpese. Tutte le route richiedono `x-api-token` e rispondono con `Content-Type: application/json`.

## Modello

```json
{
  "id": 12,
  "titolo": "Finanziamento auto",
  "creditore": "Banca",
  "debitore": null,
  "tipo": "ricevuto",
  "categoria_prestito": "finanziamento",
  "importo_totale": "18000.00",
  "importo_rata": "300.00",
  "importo_residuo": "12600.00",
  "valuta": "EUR",
  "numero_rate": 60,
  "rate_pagate": 18,
  "data_inizio": "2025-03-10",
  "data_fine": "2030-02-10",
  "data_prossima_rata": "2026-09-10",
  "giorno_scadenza": 10,
  "frequenza": "mensile",
  "tasso_interesse": "4.20",
  "utente_id": 1,
  "utente": "Alessandro",
  "categoria_id": 4,
  "categoria": "Auto",
  "metodo_pagamento": "Addebito",
  "carta": "Conto principale",
  "stato": "attivo",
  "note": null,
  "created_at": "2026-08-21T08:00:00.000Z",
  "updated_at": "2026-08-21T08:00:00.000Z"
}
```

Gli importi possono essere numeri JSON oppure stringhe decimali. `tipo` indica la direzione (`ricevuto` o `concesso`), mentre `categoria_prestito` vale `mutuo`, `prestito`, `finanziamento` oppure `altro`.

`importo_residuo`, `data_prossima_rata` e `rate_pagate` devono provenire dalla stessa fonte usata dalla pagina web. Nel server attuale le colonne storiche `debito_residuo`, `prossima_rata`, `rata`, `importo_iniziale`, `nome` e `istituto` sono la fonte principale; `rate_pagate` deve essere il conteggio effettivo di `loan_payments`.

## Route

### `GET /api/prestiti`

L'app usa `?stato=tutti&limit=500` e applica localmente i filtri Attivi/Estinti/Tutti.

```json
{ "ok": true, "prestiti": [] }
```

### `GET /api/prestiti/:id`

```json
{ "ok": true, "prestito": {} }
```

### `POST /api/prestiti`

Body: modello senza `id`, campi calcolati, nomi visualizzati e timestamp.

```json
{ "ok": true, "saved": true, "id": 12, "prestito": {} }
```

### `PATCH /api/prestiti/:id`

Body uguale alla creazione.

```json
{ "ok": true, "saved": true, "prestito": {} }
```

### `POST /api/prestiti/:id/paga-rata`

```json
{
  "data_pagamento": "2026-08-21",
  "crea_movimento": true
}
```

Il server deve incrementare `rate_pagate` in una transazione, impedire il superamento di `numero_rate`, aggiornare lo stato a `estinto` quando necessario e creare il movimento una sola volta. Risposta minima:

```json
{ "ok": true, "saved": true }
```

### `POST /api/prestiti/:id/importa-rate-passate`

Body vuoto. Crea i movimenti mancanti fino alla data corrente in modo idempotente e aggiorna il prestito.

```json
{ "ok": true, "saved": true, "importate": 3 }
```

### `DELETE /api/prestiti/:id`

Elimina il prestito ma non i movimenti già registrati.

```json
{ "ok": true, "deleted": true }
```

## Errori

Usare gli stessi errori delle API Scadenze:

```json
{
  "ok": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Numero rate non valido"
  }
}
```

- `400`: dati non validi;
- `401`/`403`: token assente o non valido;
- `404`: prestito inesistente;
- `409`: rata già registrata o prestito estinto;
- `500`: errore interno.
