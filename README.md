# Practice Desk CRM

A CRM for an accounting practice in Slovenia: enquiries from Gmail, leads, clients, company formations, AML checks (ZPPDFT-2), client requests, contracts in Slovenian and English, and import/export for Pantheon / e-Računi.

The whole app is one file, `index.html`.

## How to use it

Download or clone this repository and open `index.html` in Chrome, Edge, Firefox or Safari. You can double-click the file, or host the folder anywhere (GitHub Pages, an intranet server). Nothing needs installing.

- **Records are saved in your browser** (local storage) on that computer. They survive closing the browser, but clearing site data deletes them and other computers don't see them.
- **Back up regularly:** Firm & accounting → Backup → *Download backup* gives one JSON file with everything. *Restore from backup* loads it on any computer (replace or merge).
- **Inbox:** paste an enquiry or client email (sender, subject, text) and turn it into a lead or a request.
- **Quotes, agreements, contracts:** *Save PDF* / *Save Word* download the file. *Save PDF + open email* downloads the PDF and opens your mail app with the subject and message filled in; attach the PDF and send. The document is logged under Documents as Sent.
- The two contract templates in `templates/` are loaded automatically the first time. *Reload default contract templates* restores them.
- PDF creation uses html2pdf.js from the CDN, with a local copy in `vendor/` as fallback, so it also works offline.

Don't use a private/incognito window: the browser deletes its storage when the window closes.

## Shared online database (Supabase)

With `config.js` filled in, the app stops using browser storage and keeps everything in a Supabase database instead. Everyone signs in with email, password and an authenticator app, and changes appear for everyone within a second. With `config.js` left empty the app keeps working in the browser, as described above.

### One-time setup

1. **Create the project.** Sign up at supabase.com → *New project*. Region: **Central EU (Frankfurt)**. Save the database password somewhere safe. The Pro plan is recommended for live client data: the free plan pauses after a week without use and has no daily backups.
2. **Create the tables.** *SQL Editor* → *New query* → paste all of `supabase/schema.sql` → *Run*. It is safe to run again later.
3. **Lock down sign-ups.** *Authentication* → *Sign In / Providers*: keep **Email** on and turn **off** *Allow new users to sign up*. Only people you invite can get in. Under *Multi-Factor*, make sure **TOTP (App Authenticator)** is enabled.
4. **Tell Supabase where the app lives.** *Authentication* → *URL Configuration*: set *Site URL* to the address of the app (e.g. `https://crm.your-domain`) and add the same address to *Redirect URLs*. Invite and password-reset emails link there.
5. **Connect the app.** *Project Settings* → *API* (or the *Connect* button): copy the **Project URL** and the **anon / publishable** key into `config.js`, then commit and deploy. Never use the `service_role` / secret key.
6. **Add yourself.** *Authentication* → *Users* → *Invite user* with your email. Then, in the SQL Editor:

   ```sql
   insert into public.members (user_id, email, name, role)
   select id, email, 'Your Name', 'admin' from auth.users where email = 'you@your-firm.si';
   ```
7. **First sign-in.** Open the link in the invite email. Choose a password, then scan the QR code with an authenticator app (Google Authenticator, Microsoft Authenticator, 1Password…) and enter the 6-digit code.
8. **Move your records.** In the browser where you used the CRM so far: *Firm & accounting* → *Backup* → *Download backup*. Signed in to the online version: *Restore from backup* → OK (replace).

### Colleagues

- **Add:** invite them under *Authentication* → *Users*, then run the `insert into public.members …` query above with their email and role `'staff'`. Until then they see "Waiting for access".
- **Remove:** `delete from public.members where email = 'them@your-firm.si';` and delete the user under *Authentication* → *Users*.
- **Lost phone:** under *Authentication* → *Users* → the user → remove their MFA factor. They set up a new one at the next sign-in.

### Recovering a changed or deleted record

Every change keeps the previous version in `records_history`. To see the history of one record:

```sql
select changed_at, op, data from public.records_history
where coll = 'clients' and data->>'name' ilike '%name of client%'
order by changed_at desc;
```

To put an old version back: `insert into public.records (coll, id, data) values ('clients', '<id>', '<data from above>') on conflict (coll, id) do update set data = excluded.data;`

### How access is protected

- Row-level security in `supabase/schema.sql`: only people in `members` who have signed in **with** their authenticator code can read or write anything. Anonymous visitors and invited-but-not-added users see nothing.
- The anon key in `config.js` is designed to be public; the database rules above do the protecting.
- The app loads the Supabase library from `vendor/supabase.js` (supabase-js 2.118.0, MIT), not from a third-party CDN.

### On claude.ai (optional)

The same page also runs as a **claude.ai artifact**. There it saves records in the artifact's database (shared across your devices) and adds Gmail features: reading the inbox, Claude sorting and extracting enquiries, and creating Gmail drafts with the PDF attached. To move records between the two, download a backup in one and restore it in the other.

## Updating the claude.ai version from this repository

1. Edit `index.html`.
2. In a Claude conversation, ask Claude to publish `index.html` to your existing Practice Desk artifact (give it the artifact link). Your saved records stay in place; they live in the artifact's database, not in the file.

## Contract templates

`templates/` holds the contract templates (accounting and rental) as JSON. They are stored in the artifact's database under the `templates` collection. To restore or reload one, ask Claude to write the JSON file to the `templates` collection of your artifact, using the file name (without `.json`) as the document id. You can also edit templates inside the app under **Contracts → Edit template**.

Template text syntax:

| Write | Result |
|---|---|
| `# Title` | centred title |
| `## 1. člen` | centred article heading |
| `### Section` | left-aligned heading |
| `- item` / `1. item` | bullet / numbered list |
| `**bold**`, `*italic*` | bold, italic |
| empty line | new paragraph |
| `===` | page break |
| `\|\| LEFT \\\\ line 2 \|\| RIGHT` | two signature columns (`\\` = line break) |
| `{{client.name}}`, `{{firm.name}}`, `{{doc.number}}`, `{{doc.date}}` | filled in from the client, your firm settings and the contract |
| `{{f.key}}` | your own fill-in field |
| `- {{f.list}}` | a list field shown as bullets |
| `?f.fee Sentence with {{f.fee}}` | line only appears when the field is filled |

A field default starting with `=` pulls a value: `=client.fee`, `=firm.payDays`, `=today`.

## Data and privacy

Client records, AML checks and documents are **not** in this repository. Keep this repository private if you add anything beyond the code and templates, and never commit client or AML personal data to a public repository.
