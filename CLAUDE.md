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

### 2. Read the mail – always from where the last check ended

Never re-read a fixed number of days. Ask the drop box first (needs the agent key, see 5b):

```bash
curl -sS -X POST "<supabaseUrl>/rest/v1/rpc/agent_state" -H "apikey: <supabaseAnonKey>" \
  -H "Content-Type: application/json" -H "x-agent-token: placeholder-replaced-by-the-proxy" -d '{}'
```

It answers `{"last_checked_to": "<timestamp>", "delivered_thread_ids": [...]}`. Read only mail after
`last_checked_to` (Gmail accepts Unix seconds: `after:1764351840`) and **skip every thread in
`delivered_thread_ids`** – those are already in the CRM or waiting there, even if they got a new message.
The period of this run is `last_checked_to` → now. Only if the call fails (no key, no network), fall back
to the period the user names, or the last 3 days, and say so.

Search both received and **sent** mail for the period, e.g.
`after:2026/11/01 -category:promotions -category:social -category:forums -in:sent` and
`in:sent after:2026/11/01`, with pageSize 50 and view THREAD_VIEW_SUMMARY, following pageToken to the end.
Read a thread's text (get_thread, PLAIN_TEXT) only when the subject and snippet are not enough to
decide, to find the client, a case number or a website-form contact. The mailbox gets roughly
350 threads a week, so for long periods split the work by week.

The client list (company → email addresses) is not in the repository (client data stays out of git):
it comes from the user's backup, from the scheduled task's prompt, or from `data/client-emails.json`
in the current session.

### 3. Decide what each thread is

**Request (client asks for something)** – the sender is a client, or the mail is clearly about a client:
- sender matches a client's `email`, `noticeEmail` or `otherEmails` – but some addresses are **shared by
  two companies** (e.g. info@jug-ai-gradnje.com is JUG AI GRADNJE d.o.o. and SLOBELMAR;
  vezjak.petra@siol.net is FASADE VEZJAK d.o.o. and VEZJAK d.o.o.): for those, decide by the company
  named in the mail, and if it is not clear, list it as unsure;
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
internal mail, anything not about a client or prospect. Most of the mailbox is **routine
bookkeeping documents** clients send for the monthly books: invoices ("Račun", "Faktura",
"Rechnung", e-računi), scans ("[Scan] …", "scan0399.pdf"), fuel/toll statements (DKV, Eurowag),
loading orders, CMR, mileage ("Kilometrina"), payroll hours ("Place", "Plate") for the monthly payroll,
bank statements and payment advices. These are **not** requests – unless the mail also asks for
something (e.g. "please issue an invoice", "send me a confirmation", "correct this").

One request per **matter**: several threads about the same thing for the same client are one request
(mention the number of threads in the notes).

**Unsure** – do not guess and do not leave it out: add it with a `review` text saying what to check
(e.g. "Not sure which company this is for – shared address"). The app shows it in purple with a
*Check* label until the user clicks *Verified*. Only clearly irrelevant mail is left out.

**Already written** – the user also writes requests by hand. The app skips an imported request that
matches an existing one (same client, similar subject, within 3 weeks, or the same case number) and
marks near-matches purple. Still avoid obvious duplicates within one file (one request per matter,
even if it spans several threads).

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

### 5b. Deliver it to the CRM drop box (preferred)

If the environment can reach the Supabase project (host in `config.js`, `supabaseUrl`) and holds the
agent key as a network credential for the header `x-agent-token`, put the import straight into the
CRM's drop box instead of only sending a file. The user then sees a banner in the CRM and adds it with
one click (same duplicate checks and purple marks as a file import).

```bash
python3 -c 'import json,sys; print(json.dumps({"p_payload": json.load(open(sys.argv[1])), "p_summary": sys.argv[2]}))' \
  data/import-gmail-<from>-<to>.json "<period>: N requests, M leads" > /tmp/queue.json
curl -sS -X POST "<supabaseUrl>/rest/v1/rpc/submit_import" \
  -H "apikey: <supabaseAnonKey from config.js>" -H "Content-Type: application/json" \
  -H "x-agent-token: placeholder-replaced-by-the-proxy" --data @/tmp/queue.json
```

Always add the period: `{"p_payload": …, "p_summary": …, "p_period_from": "<last_checked_to>", "p_period_to": "<now, ISO>"}`.
Deliver even when nothing new was found (`"data": {"requests": {}, "leads": {}}`): that records where the
check ended, so the next run continues from there (the app files empty runs away without a banner).
The answer is the queue number. The real key is injected by the environment's proxy; never print,
store or commit it. If the call fails (no key, host blocked, "invalid agent key"), fall back to sending
the file with SendUserFile and say why. The key can only add to the drop box: it cannot read the CRM.

### 6. Report back

Client email lists (company → addresses) can be added in the app under *Firm & accounting → Client
emails*, or as an import file `{"app":"practice-desk-crm","version":1,"clientEmails":[{"name":"…","emails":["…"]}]}`.

Give the user a short table of what is in the file (requests per client, new leads, work rows with
amounts), the unsure threads, and any client addresses worth adding to a client's *Other emails* so
next time matching is automatic.
