# xSpese

App iOS 17 per registrare e consultare le spese, anche tramite Comandi Rapidi, e sincronizzarle con il server Bilancio Personale sul Raspberry Pi.

## Funzioni disponibili

- registrazione rapida tramite App Intent/Comandi Rapidi;
- inserimento manuale completo di categoria, valuta, utente, carta/conto e note;
- archivio locale SwiftData con ricerca, filtri, raggruppamento e totale giornaliero;
- dettaglio del singolo movimento al tocco e azioni rapide con pressione prolungata;
- sincronizzazione automatica e manuale con stato, errori e nuovi tentativi;
- dashboard mensile nativa con riepiloghi per categoria, utente e detraibilita;
- consultazione dei movimenti presenti sul Raspberry;
- gestione delle regole esercente/categoria e suggerimento durante l'inserimento;
- gestione nativa delle scadenze con creazione, modifica, completamento, eliminazione e ricerca;
- ricorrenze, priorita, promemoria locali e creazione del movimento al pagamento;
- widget Home Screen per prossima scadenza, spese mensili, sincronizzazione e panoramica;
- impostazioni per URL, token, utente predefinito, valuta e notifiche;
- tentativo di sincronizzazione quando l'app torna attiva e aggiornamento opportunistico in background.

## Configurazione Raspberry

Aprire l'ingranaggio nell'app e configurare:

- URL server, predefinito `http://100.112.193.68:3030`;
- API token corrispondente ad `API_TOKEN` del server;
- ID utente, predefinito `1`;
- sincronizzazione automatica.

La valuta predefinita viene usata sia nell'inserimento manuale sia nell'azione di Comandi Rapidi. Il token resta memorizzato nel portachiavi di iOS.

Il pulsante **Test connessione** verifica `GET /health`. Il pulsante con le frecce circolari nella lista forza l'invio dei movimenti `pending`, `syncing` o `failed` a `POST /api/movimento`. L'header usato è `x-api-token`; l'UUID locale è inviato come `transaction_uuid` per garantire l'idempotenza.

Il server Tailscale indicato usa HTTP, quindi il progetto consente traffico non cifrato tramite ATS. Questa eccezione va rimossa quando il servizio sarà esposto in HTTPS.

## Uso quotidiano

1. Aprire **Impostazioni**, inserire il token e verificare il collegamento.
2. Registrare una spesa con il pulsante **+** oppure con l'azione **Registra spesa** di Comandi Rapidi.
3. Toccare un movimento per il dettaglio; tenerlo premuto per sincronizzarlo o aprirlo rapidamente.
4. Usare **Dashboard** per il riepilogo mensile e **Server** per controllare ciò che risulta già sul Raspberry.
5. Creare regole esercente/categoria dalle impostazioni per velocizzare le registrazioni successive.
6. Usare **Scadenze** per programmare pagamenti e attivare **Promemoria scadenze** nelle impostazioni.

Se il Raspberry non è raggiungibile, la spesa non viene persa: rimane nel database locale e viene riprovata. Dopo più errori consecutivi l'app può inviare una notifica, se autorizzata.

## Scadenze

La scheda **Scadenze** usa direttamente le API JSON del Raspberry. Le scadenze aperte vengono organizzate in scadute, oggi, prossimi sette giorni e successive. Dalla stessa sezione e possibile:

- creare e modificare una scadenza;
- assegnare importo, utente, categoria, priorita e note;
- configurare ricorrenze giornaliere, settimanali, mensili o annuali;
- ricevere promemoria locali a partire dai giorni selezionati;
- completare una scadenza creando facoltativamente il relativo movimento;
- riaprire o eliminare una scadenza;
- consultare separatamente scadenze aperte, completate, annullate o tutte.

La specifica usata dal client si trova in `SCADENZE_API_SPEC.md`.

## Widget Home Screen

Il target **xSpeseWidgets** fornisce quattro widget:

- **Prossima scadenza** (piccolo): titolo, data, importo, ritardo e altre scadenze aperte;
- **Spese del mese** (piccolo): totale corrente e categoria con la spesa maggiore;
- **Sincronizzazione** (piccolo): movimenti da inviare, errori e ultimo invio riuscito;
- **Panoramica xSpese** (medio): totale mensile, prossima scadenza e stato di sincronizzazione insieme.

Un tocco apre direttamente la sezione pertinente dell'app. I widget vengono aggiornati all'avvio dell'app, dopo una registrazione o sincronizzazione, durante il caricamento della Dashboard e negli aggiornamenti in background concessi da iOS.

Per aggiungerlo all'iPhone:

1. installare e aprire xSpese almeno una volta;
2. verificare il server nelle impostazioni e lasciare completare il primo aggiornamento;
3. tenere premuto uno spazio vuoto nella schermata Home;
4. premere **Modifica** e poi **Aggiungi widget**;
5. cercare **xSpese** e scegliere il widget e il formato desiderati.

App e widget condividono solamente riepiloghi gia pronti tramite un App Group; il token API non viene copiato nell'estensione. Nelle installazioni Xcode viene usato `group.it.alessandroiacca.xSpese`. Nelle installazioni SideStore l'app legge da `ALTAppGroups` l'identificatore rimappato con il Team ID Apple. In **Signing & Capabilities** l'App Group deve risultare abilitato sia per il target `xSpese` sia per `xSpeseWidgets`.

## Requisiti

- macOS con Xcode 15 o successivo
- iPhone con iOS 17 o successivo
- Apple ID configurato in Xcode per la firma dell'app

## Configurazione Xcode

1. Aprire `xSpese.xcodeproj`.
2. Selezionare il target **xSpese**, quindi **Signing & Capabilities**.
3. Lasciare **Automatically manage signing** attivo e scegliere il proprio **Team**.
4. Se il bundle identifier è già occupato, sostituire `it.alessandroiacca.xSpese` con un identificatore univoco.
5. Selezionare l'iPhone come destinazione ed eseguire l'app almeno una volta.

App Intents e database SwiftData appartengono allo stesso target. L'App Group e invece necessario per condividere con i widget i soli riepiloghi, senza esporre il token del server.

## Build IPA locale

La pipeline produce un'IPA senza certificati, profili o credenziali Apple nel repository. App ed estensione ricevono solamente una firma ad-hoc che conserva gli entitlement necessari a SideStore; durante l'installazione SideStore la sostituisce con la firma personale dell'utente.

```bash
chmod +x scripts/build_ipa.sh
./scripts/build_ipa.sh
unzip -l dist/xSpese-0.1.1.ipa
```

Gli output sono:

- `dist/xSpese-<versione>.ipa`;
- `dist/build-info.json`, contenente versione, build, bundle identifier, dimensione e SHA-256.

Lo script legge versione e build dall'`Info.plist` compilato, controlla il semantic versioning e verifica che l'IPA contenga `Payload/xSpese.app`. Per imporre la corrispondenza con una release si puo usare:

```bash
EXPECTED_VERSION=0.1.0 ./scripts/build_ipa.sh
```

## Release automatica su GitHub

Il workflow `.github/workflows/build-release.yml` parte con un tag `v*` oppure manualmente da **Actions → Build and publish IPA**. Non usa certificati personali.

Prima release:

1. creare un repository GitHub e impostarlo come remote di questo progetto;
2. verificare in **Settings → Actions → General → Workflow permissions** che GitHub Actions possa scrivere i contenuti;
3. mantenere sincronizzati `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` e la sezione corrispondente di `CHANGELOG.md`;
4. creare e inviare un tag identico alla versione Xcode:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Il workflow compila l'app, valida il tag, crea o aggiorna la GitHub Release, allega IPA e `build-info.json`, genera `source.json` e prova a pubblicarlo sul branch predefinito. Se il branch e protetto e il push automatico viene rifiutato, `source.json` rimane comunque disponibile tra gli asset della Release; il workflow manuale **Repair SideStore source** consente di rigenerarlo.

Il push di `source.json` non riavvia la pipeline perche il workflow di release ascolta solamente tag e avvii manuali.

### Generazione manuale di source.json

```bash
python3 scripts/generate_source.py \
  --version 0.1.0 \
  --build 1 \
  --bundle-id it.alessandroiacca.xSpese \
  --ipa dist/xSpese-0.1.0.ipa \
  --repo Alessandr0IA/xSpese \
  --tag v0.1.0 \
  --branch main \
  --notes-file CHANGELOG.md
```

Il generatore confronta gli argomenti con l'`Info.plist` realmente contenuto nell'IPA, evita duplicati e inserisce la nuova versione in cima. Aggiorna inoltre URL, dimensione reale, SHA-256, data e note della release.

## Installazione tramite source SideStore

Dopo che la prima release ha aggiornato `source.json`, l'URL della source e:

```text
https://raw.githubusercontent.com/Alessandr0IA/xSpese/main/source.json
```

In SideStore:

1. aprire la scheda **Sources**;
2. premere **+** o **Add Source**;
3. incollare l'URL Raw indicato sopra;
4. aprire la source **xSpese SideStore Repo**;
5. selezionare **xSpese** e premere **Install**.

SideStore scarica l'IPA dalla GitHub Release, la firma con l'account Apple configurato e gestisce i successivi aggiornamenti dalla stessa source. Quando viene pubblicata una nuova versione, la pipeline la inserisce in cima all'elenco e SideStore puo rilevarla come aggiornamento.

### Verifica App Intent e widget con SideStore

1. installare xSpese dalla source e avviarla almeno una volta;
2. aprire Comandi Rapidi;
3. cercare **xSpese** e **Registra spesa**;
4. eseguire una registrazione e verificare che compaia nell'archivio locale.
5. aprire **xSpese → Impostazioni → Widget** e verificare che **Condivisione dati** risulti **Attiva**;
6. premere **Aggiorna widget ora** e attendere il messaggio di conferma;
7. rimuovere eventuali widget della versione precedente e aggiungerli nuovamente dalla Home.

L'estensione widget richiede un App ID aggiuntivo e un App Group. L'IPA conserva entrambi gli entitlement e l'app usa automaticamente l'identificatore App Group rimappato da SideStore.

### Installazione IPA diretta come alternativa

Se non si vuole aggiungere la source, la stessa IPA puo essere installata direttamente:

1. scaricare `xSpese-<versione>.ipa` dalla Release in File;
2. aprire **SideStore → My Apps**;
3. premere **+** e selezionare l'IPA;
4. completare la firma e avviare xSpese.

Con un account Apple gratuito SideStore e le app installate sono soggette ai limiti Apple sugli slot e agli App ID disponibili. SideStore deve inoltre aggiornare periodicamente la firma dell'app.

## Creazione IPA manuale da un archivio Xcode

Come fallback firmato:

1. scegliere **Product → Archive** in Xcode;
2. aprire l'archivio con **Show in Finder**;
3. entrare in `Products/Applications`;
4. impacchettare `xSpese.app`:

```bash
work_dir="$(mktemp -d)"
mkdir -p "${work_dir}/Payload"
cp -R /percorso/xSpese.app "${work_dir}/Payload/"
(cd "${work_dir}" && zip -qry xSpese.ipa Payload)
```

La pubblicazione tramite GitHub Pages e facoltativa: la configurazione base usa GitHub Raw e non dipende da Pages.

## Test dell'Intent da Comandi Rapidi

1. Aprire una volta xSpese sull'iPhone e verificare la schermata **Movimenti**.
2. Aprire **Comandi Rapidi** e creare un nuovo comando.
3. Cercare **xSpese** oppure **Registra spesa** tra le azioni.
4. Aggiungere l'azione e compilare importo ed esercente; data, carta/conto, categoria, note, valuta e utente sono facoltativi.
5. Eseguire il comando. Deve comparire il messaggio **Spesa registrata in xSpese**.
6. Tornare nell'app: la nuova transazione deve apparire in cima alla lista con indicatore arancione `pending`.
7. Chiudere forzatamente xSpese e rieseguire il comando per verificare che l'Intent non richieda l'apertura manuale dell'app.

Dopo il test manuale, l'azione può essere selezionata dentro un'automazione personale con trigger **Transazione**, collegando i valori resi disponibili da iOS ai parametri dell'Intent.

## Note e limiti delle API attuali

- App Intents non supporta `Decimal` come parametro: l'importo entra da Comandi Rapidi come `Double` e viene convertito subito in `Decimal` per il salvataggio locale.
- Se il server non è raggiungibile, la transazione resta locale con stato `failed` e viene riprovata quando l'app torna attiva, in background quando iOS lo concede o tramite sincronizzazione manuale.
- iOS decide autonomamente quando eseguire un aggiornamento in background: non e garantito che avvenga a un'ora precisa.
- I movimenti server restano in sola lettura finche il backend non espone route di modifica/eliminazione.
- I promemoria delle scadenze sono notifiche locali e vengono aggiornati quando l'app scarica l'elenco dal server. iOS limita il numero di notifiche locali pendenti, quindi vengono pianificati i primi 60 promemoria futuri.
- La disponibilità e i campi del trigger **Transazione** dipendono dalla versione di iOS, dalla regione, dalle carte e dalle variabili che Apple rende disponibili in Comandi Rapidi.

## Struttura

- `App/xSpeseApp.swift`: ingresso SwiftUI e container SwiftData condiviso.
- `Models/Transaction.swift`: modello persistente e identificatore UUID univoco.
- `Intents/RegistraSpesaIntent.swift`: validazione, salvataggio locale e registrazione dell'azione.
- `Services/APIClient.swift`: richieste tipizzate verso le route del Raspberry.
- `Services/PersistenceController.swift`: unico `ModelContainer` usato da app e Intent.
- `Services/SyncService.swift`: sincronizzazione, tentativi e stato locale.
- `Services/DeadlineWidgetCacheService.swift`: aggiorna la copia condivisa usata dal widget.
- `Services/ExpenseWidgetCacheService.swift`: aggiorna report mensile e stato della sincronizzazione per i widget.
- `Shared/DeadlineWidgetData.swift`: modello e archivio App Group condivisi.
- `scripts/build_ipa.sh`: build unsigned e packaging IPA riproducibile.
- `scripts/generate_source.py`: aggiornamento verificato della source SideStore.
- `.github/workflows/build-release.yml`: release automatica da tag.
- `.github/workflows/update-source.yml`: riparazione manuale della source da una Release.
- `source.json`: catalogo pubblico usato da SideStore.
- `CHANGELOG.md`: note ordinate per versione.
- `Views/TransactionsView.swift`: archivio locale ricercabile e raggruppato per giorno.
- `Views/DashboardView.swift`: report mensile nativo.
- `Views/ServerMovementsView.swift`: archivio restituito dal server.
- `Views/DeadlinesView.swift`: elenco, dettaglio, editor e completamento nativi delle scadenze.
- `xSpeseWidgets/xSpeseDeadlineWidget.swift`: bundle dei quattro widget Home Screen.
