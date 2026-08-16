# blitzjob

Job-Matching-Prototyp für Studentenjobs in Ostbelgien (DE/FR/NL). Statisches Frontend (`index.html`, `dashboard.html`) auf GitHub Pages, Backend über [Supabase](https://supabase.com) (Postgres + Auth + Auto-API).

## Warum es Blitzjob gibt

Blitzjob verfolgt zwei Ziele gleichzeitig:

- **Für Unternehmen:** schnell motivierte Studenten aus der Region finden, ohne sich in landesweiten Jobportalen zu verlieren.
- **Für Studenten:** schnell und unkompliziert einen passenden Nebenjob in der Nähe finden — um sich weiterzuentwickeln, erste Erfahrung zu sammeln und eigenes Geld zu verdienen, ohne stundenlange Bewerbungen schreiben zu müssen.

Die Seite ist für Unternehmen und Studenten **100% kostenlos**.

## Sprachen (DE / FR / NL)

Die Zielgruppe in Ostbelgien ist dreisprachig — **jeder sichtbare Text auf `index.html` muss deshalb in allen drei Sprachen vorliegen**, nicht nur Deutsch. Konkret heißt das:

- Jeder neue/geänderte Text bekommt ein `data-i18n="key"`-Attribut im HTML und einen passenden Fallback-Text als Inhalt (wird angezeigt, falls ein Key mal fehlt).
- Der gleiche `key` muss in **allen drei** Objekten `i18n.de`, `i18n.fr`, `i18n.nl` im `<script>`-Block von `index.html` gepflegt werden — fehlt ein Key in einer Sprache, bleibt beim Umschalten der vorherige (falsche) Sprachtext stehen.
- `dashboard.html` ist aktuell bewusst nur auf Deutsch (interne Nutzung durch Unternehmen) — falls das sich ändern soll, gerne ansprechen.

## Setup

1. Supabase-Projekt anlegen, `supabase/schema.sql` im SQL-Editor ausführen
2. Project URL + Publishable Key in `assets/supabase-client.js` eintragen
3. Auf GitHub Pages deployen (Branch `main`, Ordner `/root`)

## Sicherheitskonzept

Das Frontend ist eine reine statische Seite ohne eigenen Server — die **einzige Zugriffskontrolle ist Postgres Row Level Security (RLS)** in Supabase. Das ist bewusst so:

- Der **Publishable Key** in `assets/supabase-client.js` ist absichtlich öffentlich und darf im Repo/Frontend liegen — er ersetzt keine Zugriffskontrolle, sondern identifiziert nur das Projekt.
- Der **Secret/Service-Role Key** darf **niemals** im Frontend, im Repo oder sonst irgendwo im Code landen. Er existiert nur für serverseitige Admin-Zwecke und wurde in diesem Projekt nirgends verwendet.
- Jede Tabelle hat RLS aktiviert (`enable row level security`) mit expliziten Policies — ohne Policy ist eine Tabelle mit dem Publishable Key unlesbar/unschreibbar, das ist der eigentliche Schutzmechanismus.

**Konkret umgesetzt (siehe `supabase/schema.sql`):**

| Schutz | Umsetzung |
|---|---|
| XSS über Nutzereingaben (Bewerbername, Jobtitel, …) | Alle dynamisch eingefügten Texte werden im Frontend per `escapeHtml()` escaped, bevor sie ins DOM geschrieben werden |
| Fake-Firmen greifen Studentendaten ab | Jobs sind für Studenten erst öffentlich sichtbar, wenn `companies.verified = true` — das Flag kann ein Unternehmen **nicht selbst setzen** (`revoke update (verified) ...`), nur du im SQL-Editor nach manueller Prüfung |
| Unternehmen sieht fremde Bewerbungen | RLS-Policy beschränkt `applications`-SELECT strikt auf `jobs.company_id = auth.uid()` |
| Bewerbungen auf geschlossene/erfundene Jobs | INSERT-Policy prüft `jobs.status = 'open'` serverseitig, nicht nur im Frontend |
| Ungültige/gefälschte E-Mail-Formate | CHECK-Constraint mit Regex direkt in der Datenbank (clientseitige Validierung lässt sich umgehen) |
| Spam-Bewerbungen auf denselben Job | `unique (job_id, applicant_email)` verhindert Mehrfachbewerbungen mit derselben Adresse |
| Beliebige/fremde Werte in Kategorie/Ort/Status | CHECK-Constraints mit fester Werteliste statt Freitext |
| Passwort-Policy, Brute-Force auf Login | Von Supabase Auth serverseitig vorgegeben (siehe "Noch manuell zu erledigen") |

## Noch manuell zu erledigen (Supabase Dashboard)

Diese Punkte lassen sich nicht per SQL/Code erzwingen, sondern müssen einmalig in den Projekteinstellungen aktiviert werden:

- **Authentication → Policies**: "Leaked Password Protection" aktivieren (verhindert bekannte, geleakte Passwörter)
- **Authentication → Providers → Email**: "Confirm email" aktiviert lassen, damit Fake-Adressen keine Firmenkonten anlegen können
- Vor jedem Go-Live: prüfen, dass **kein** Secret/Service-Role Key in einem Commit gelandet ist (`git log -p -- assets/`)
- Firmen-Accounts nach der Registrierung manuell im SQL-Editor verifizieren: `update companies set verified = true where id = '<user-uuid>';`

## Skalierung (bis ~1000 gleichzeitige Nutzer)

- Supabase läuft über PostgREST (zustandslose REST-API) — lesender Traffic von bis zu 1000 gleichzeitigen Studenten ist auch im Free-Tier unproblematisch, solange die Anfragen kurz sind (hier: einfache `select`-Queries mit `limit`).
- Der **Free-Tier pausiert Projekte nach 7 Tagen Inaktivität** — für einen produktiven Launch auf **Pro** upgraden, sonst kann die Seite offline gehen.
- Schreibender Traffic (Bewerbungen, neue Anzeigen) ist durch RLS und CHECK-Constraints serverseitig abgesichert, nicht nur im Frontend — das schützt auch bei hoher gleichzeitiger Last vor korrupten/böswilligen Daten.
- Kein eigenes Rate-Limiting auf `applications`-INSERTs über Edge Functions — bei echtem Missbrauch (z. B. Bot-Spam) müsste das zusätzlich über eine Supabase Edge Function oder Cloudflare Turnstile ergänzt werden.
