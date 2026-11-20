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
