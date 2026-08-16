-- Blitzjob — Datenbank-Schema (Security-gehärtete Version)
-- Im Supabase Dashboard unter "SQL Editor" -> "New query" einfügen und ausführen.
--
-- Design-Entscheidung: Nur Unternehmen haben echte Accounts (Supabase Auth).
-- Studenten bewerben sich ohne Login/Formular direkt aus dem Chat heraus —
-- ihre Angaben (Name, E-Mail, Chat-Antworten) landen als Zeile in "applications".
--
-- Sicherheitsprinzip: Der Publishable Key im Frontend ist bewusst öffentlich.
-- Der einzige Schutz für die Daten ist Row Level Security (RLS) — jede Tabelle
-- MUSS also durch eine Policy abgedeckt sein, sonst ist sie mit dem Key lesbar.

-- ============================================================
-- 1. companies — ein Account pro Unternehmen (Supabase Auth)
-- ============================================================
create table companies (
  id uuid primary key references auth.users(id) on delete cascade,
  company_name text not null check (char_length(company_name) between 1 and 150),
  industry text check (char_length(industry) <= 100),
  location text check (location in ('eupen','stvith','kelmis','raeren')),
  verified boolean not null default false,
  created_at timestamptz not null default now()
);

alter table companies enable row level security;

create policy "Firmenprofile sind öffentlich lesbar"
  on companies for select
  using (true);

create policy "Unternehmen kann eigenes Profil anlegen"
  on companies for insert
  with check (auth.uid() = id);

create policy "Unternehmen kann eigenes Profil bearbeiten"
  on companies for update
  using (auth.uid() = id);

-- Wichtig: "verified" darf ein Unternehmen NICHT selbst setzen (sonst Selbst-Verifizierung).
-- Nur du (als DB-Owner/Admin über den Supabase SQL-Editor) darfst das ändern.
revoke update (verified) on companies from authenticated, anon;

-- ============================================================
-- 2. jobs — Stellenanzeigen der Unternehmen
-- ============================================================
create table jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 150),
  category text check (category in ('service','logistik','buero','nachhilfe')),
  location text check (location in ('eupen','stvith','kelmis','raeren')),
  hours_per_week text check (char_length(hours_per_week) <= 30),
  wage_per_hour numeric check (wage_per_hour >= 0 and wage_per_hour <= 500),
  start_option text check (start_option in ('now','weeks','month')),
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now()
);

alter table jobs enable row level security;

-- Öffentlich (mit Publishable Key) sind NUR offene Jobs verifizierter Firmen sichtbar.
-- Das verhindert, dass sich jemand als Firma registriert, eine Fake-Anzeige
-- online stellt und so Namen/E-Mails von Studenten abgreift, bevor er geprüft wurde.
create policy "Offene Jobs verifizierter Firmen sind öffentlich lesbar"
  on jobs for select
  using (
    (status = 'open' and exists (
      select 1 from companies
      where companies.id = jobs.company_id
      and companies.verified = true
    ))
    or company_id = auth.uid()
  );

create policy "Unternehmen kann eigene Jobs anlegen"
  on jobs for insert
  with check (company_id = auth.uid());

create policy "Unternehmen kann eigene Jobs bearbeiten"
  on jobs for update
  using (company_id = auth.uid());

create policy "Unternehmen kann eigene Jobs löschen"
  on jobs for delete
  using (company_id = auth.uid());

-- ============================================================
-- 3. applications — Bewerbungen, ohne Studenten-Login
-- ============================================================
create table applications (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references jobs(id) on delete cascade,
  applicant_name text not null check (char_length(applicant_name) between 1 and 100),
  applicant_email text not null check (applicant_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
  location text check (location in ('eupen','stvith','kelmis','raeren')),
  hours_pref text check (char_length(hours_pref) <= 60),
  start_pref text check (start_pref in ('now','weeks','month')),
  message text check (char_length(message) <= 500),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  unique (job_id, applicant_email)
);

alter table applications enable row level security;

-- Bewerben ohne Login ist erlaubt, aber nur auf tatsächlich offene Jobs
-- (verhindert Bewerbungen auf geschlossene oder frei erfundene job_id-Werte).
create policy "Jeder kann sich auf offene Jobs bewerben"
  on applications for insert
  with check (exists (
    select 1 from jobs
    where jobs.id = applications.job_id
    and jobs.status = 'open'
  ));

-- Nur das Unternehmen, dem der Job gehört, sieht die Bewerbungen dazu.
create policy "Unternehmen sieht Bewerbungen auf eigene Jobs"
  on applications for select
  using (exists (
    select 1 from jobs
    where jobs.id = applications.job_id
    and jobs.company_id = auth.uid()
  ));

create policy "Unternehmen kann Status eigener Bewerbungen ändern"
  on applications for update
  using (exists (
    select 1 from jobs
    where jobs.id = applications.job_id
    and jobs.company_id = auth.uid()
  ));

-- ============================================================
-- 4. Firma manuell verifizieren (nach echter Prüfung durch dich)
-- ============================================================
-- Beispiel, im SQL-Editor mit deinem eigenen Admin-Zugriff ausführen:
-- update companies set verified = true where id = '<user-uuid-hier>';
