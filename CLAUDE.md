# Practice Desk CRM – notes for Claude

Practice Desk is the CRM of GENERAL LEDGER d.o.o., an accounting practice in Rogatec, Slovenia
(bookkeeping, payroll, company formations, EU transport licences, work and residence permits,
bank account opening). The whole app is `index.html`. Records live in Supabase (see `README.md`);
the live site is built by Cloudflare from the `main` branch.

## Working on the code

- Test changes in Chromium with Playwright before pushing. `config.js` holds the live Supabase
  settings, so tests should replace it with an empty config (route `**/config.js`).
- After a change, push the working branch and, once the user has agreed, bring `main` to the same tree.
- Client data never goes into git. `data/` is git-ignored: put import files and backups there.

## Filling the CRM from Gmail

The user asks things like "check my inbox since 1. 11. and fill the CRM". The mailbox is Google
Workspace; read it with the Gmail connector (read only – never send, label, archive or delete mail).
Claude cannot write to the database directly, so the result is an **import file** the user adds under
*Firm & accounting → Backup → Restore from backup*.

### 1. Get the current CRM first

Ask the user for a fresh backup (*Firm & accounting → Backup → Download backup*) and read it:
clients (name, `email`, `noticeEmail`, `otherEmails`, `contact`), leads, requests (their
`gmailThreadId`, so nothing is added twice), accepted proposals (agreed prices per client) and
`settings.firm.hourly`. Without the backup, still work, but use `matchEmails` / `matchClient`
(below) instead of client ids and say that matching is less reliable.

### 2. Read the mail

Search both received and **sent** mail for the period, e.g.
`after:2026/11/01 -category:promotions -category:social` and `in:sent after:2026/11/01`.
Read a thread's text only when the subject and snippet are not enough to decide.

### 3. Decide what each thread is

**Request (client asks for something)** – the sender is a client, or the mail is clearly about a client:
- sender matches a client's `email`, `noticeEmail` or `otherEmails`;
- many clients write from **personal addresses** (gmail.com etc.): match by the person's name
  (client `contact`, director), the company named in the subject, body or signature, or an earlier
  thread with the same address;
- examples: certificates and confirmations, documents, payroll changes, tax questions, permits,
  invoice questions, corrections.

**Request (work we submit for a client)** – these often never come from the client by email.
They show up as **our sent mail** to an office, or the office's reply about a client:
- **GZS** – EU transport licence, extra licence extracts (type *EU licence (GZS)*);
- **UE** (upravna enota) and **ZRSZ** – work and residence permits (type *Work / residence permit*);
- **banks** – business account opening, KYC (type *Bank account*);
- also FURS, AJPES, ZZZS, notaries, the court register.
Set `submittedTo` (one of: GZS, UE (upravna enota), ZRSZ, FURS, AJPES, ZZZS, Court register, Notary,
Bank, Other), `submittedOn`, and `caseRef` when the mail shows a file number ("Zadeva", "Številka",
"št. zadeve", "Our ref."). Status *In progress*, or *Waiting on client* if we are waiting for documents.

**Lead** – the sender is not a client and asks about our services or prices (formation, bookkeeping,
licence, permits, accounting, "ponudba", "povpraševanje", "quote"). Leads from someone who is
already a client are requests instead.

**Lead from the website** – recognise these by their **content**, never by the sender: the address
they come from (`support@general-ledger.eu`) also sends other mail, so a mail from it is not a lead
by itself. A website lead has the subject "Nova rezervacija posveta: <name>" and/or the heading
"Nova rezervacija brezplačnega posveta – S spletne strani general-ledger.eu", **and** the form
fields below. The person is in the form, not in the sender:
- `Ime in priimek` → lead `name`;
- `Kontakt` → `email` (or `phone` if it is a number);
- `Jezik strani` → `lang` (Slovenščina → `sl`, anything else → `en`);
- `Čas oddaje` → when they booked (UTC), for the notes.
Set `source` "Website form", `stage` "new", `nextAction` "Confirm free consultation (booked on website)",
`nextDate` the next working day, and notes "Booked a free consultation on the website (<language>), <date>".
If the contact already is a client, make it a request for that client instead. Search for these with
`subject:"rezervacija posveta" OR "S spletne strani"` (they may skip the inbox); mails from the same
address without the booking heading and form fields are sorted by the normal rules above.

**Ignore** – newsletters, supplier invoices, bank and system notifications, automatic replies,
internal mail, anything not about a client or prospect.

**Unsure** – do not guess. List these for the user (date, sender, subject, why) and leave them out.

### 4. Billable work

Add work rows to a request only when the mail shows the work was done and it is outside the client's
monthly fee (e.g. a submitted permit, a certificate issued). Price from the client's agreed prices
(accepted proposals: same service name, unit and price; `pct` prices use the minimum and a note);
otherwise the firm's hourly rate with the hours left at 1 and a note to check. Leave `billMonth` as
the month the work was done. When unsure whether something is billable, add no work row and mention it.

### 5. Write the import file

Save to `data/import-gmail-<from>-<to>.json` and send it to the user (SendUserFile). Format:

```json
{"app":"practice-desk-crm","version":1,"addOnly":true,"exportedAt":"<ISO time>",
 "data":{
  "requests":{"gm-<gmail thread id>":{
    "subject":"Delovno dovoljenje – Marko Novak","clientId":"<id from backup>",
    "matchEmails":["sender@gmail.com"],"matchClient":"<company name if no id>",
    "from":"Name <email>","channel":"Email","type":"Work / residence permit",
    "priority":"Normal","status":"In progress","received":"2026-11-12","due":"2026-11-19",
    "submittedTo":"UE (upravna enota)","submittedOn":"2026-11-12","caseRef":"214-1234/2026",
    "billMonth":"2026-11","work":[{"d":"2026-11-12","desc":"Vloga za enotno dovoljenje","q":1,"u":"once","p":550}],
    "notes":"one-line summary of the thread","gmailThreadId":"<id>","gmailUrl":"<viewUrl>",
    "createdAt":"<ISO>","updatedAt":"<ISO>"}},
  "leads":{"gm-<gmail thread id>":{
    "name":"Ana Novak","company":"","email":"ana@example.com","phone":"",
    "inquiry":"Accounting | Company formation | Formation + accounting","source":"Email | Website form",
    "stage":"new","services":["Bookkeeping"],"lang":"sl | en","nextDate":"<date>",
    "nextAction":"Reply to enquiry","notes":"summary","gmailThreadId":"<id>","gmailUrl":"<viewUrl>",
    "createdAt":"<ISO>","updatedAt":"<ISO>"}}
 }}
```

- Record ids are `gm-<thread id>`: `addOnly` skips anything already in Practice Desk, so the same
  file (or an overlapping period) can be imported again safely.
- Use `clientId` from the backup when known; otherwise `matchEmails` (any address the client used)
  and/or `matchClient` (company name) – the app links them on import if exactly one client matches.
- Request `type` must be one of: Quote request, Company formation, EU licence (GZS),
  Work / residence permit, Bank account, Permits / residence, Document request, Tax question,
  Payroll change, Certificate / confirmation, Invoice issue, Other.
  Work row units: `h` (hours), `kos` (pieces), `once` (one-off).
  Lead services come from: Bookkeeping, Payroll, VAT returns, Annual accounts, Corporate tax,
  Personal tax, Advisory, Company formation, Bank account opening, Registered address,
  EORI & import VAT, Work & residence permits.
- Write in the language of the mail (Slovenian, English or Bosnian/Croatian/Serbian).

### 6. Report back

Give the user a short table of what is in the file (requests per client, new leads, work rows with
amounts), the unsure threads, and any client addresses worth adding to a client's *Other emails* so
next time matching is automatic.
