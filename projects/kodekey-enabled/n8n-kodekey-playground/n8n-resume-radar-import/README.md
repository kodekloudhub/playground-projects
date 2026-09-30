# ResumeRadar - Import and Run

**Level:** beginner  ·  **Playground:** N8N | KodeKey Playground

A [`commands.sh`](./commands.sh) with the runnable steps is included.

```plain
---
id: n8n-resume-radar-import
title: ResumeRadar - Import and Run
playground: n8n
difficulty: beginner
estimated_minutes: 15
tags:
  - n8n
  - ai
  - kodekey
  - webhooks
skills:
  - importing a shared n8n workflow
  - one credential across several model vendors
  - publishing a webhook-backed page
prerequisites:
  - Comfortable in a browser
  - A KodeKloud account to create a KodeKey
  - The workflow JSON URL from whoever shared this project
---

# ResumeRadar - Import and Run

## Scenario

Every CV tool hands you a keyword percentage and nothing you can act on. The
number drifts between runs; you cannot see which requirement cost you the
points, and the "tailored" version quietly grows experience you do not have.

ResumeRadar is the version that does not do those things, and it already exists
as an n8n workflow. Rather than wiring 15 nodes yourself, you import
it, point it at your own KodeKey, and spend the time on the part that teaches
you something: reading how it works and changing what it uses.

> Building it node by node instead? Use **ResumeRadar - One Key, Every Model**,
> which walks the same workflow from an empty canvas.

## What you'll build

A running web page, served by n8n itself, that takes a CV as a PDF and a job ad
as text and returns a match score, a list of what the CV cannot show, and a
rewritten CV. Three companies' models do the work behind it, and all three run on
a single KodeKey credential. You will have it live in about fifteen minutes,
then change one model and watch the output move.

## Learning objectives

By the end, you will be able to:

- Import an n8n workflow from a URL and know why some URLs will not work
- Attach one KodeKey credential and reach three vendors' models through it
- Publish a webhook-backed workflow and find the URL that actually answers
- Read a finished workflow and say what each node contributes
- Swap a model and compare the result against the same input

## Prerequisites

- Playground: **n8n** (open it before starting)
- A KodeKloud account, so you can create a KodeKey
- The workflow JSON URL from whoever shared this project. It must be a **direct
  link that returns the JSON itself** - a GitHub file page or a file-collection
  page returns HTML and will fail

## Architecture/overview

One webhook is both the front door and the intake. n8n routes `GET` and `POST`
down separate branches, so the same URL serves the page and receives the
submission.

```text
                    GET  -> Page HTML ------------------> Serve Page
Web UI (webhook) --|
                    POST -> Extract CV Text -> Intake --|
                                                        |
                            Parse CV      (Google)  <---|
                            Parse Job Ad  (MiniMax) <---|
                                   |
                                 Merge -> Score (no AI) -> Tailor (Anthropic)
                                                              |
                                          Send Result <- Build Report
```

| Node | Model | Company | Why this one |
|---|---|---|---|
| `Parse CV Model` | `google/gemini-3.1-flash-lite` | Google | Reads a whole document on every run, so it has to be cheap |
| `Job Ad Model` | `minimax/minimax-m3` | MiniMax | Same job, same cost tier, a different vendor |
| `Writer Model` | `claude-sonnet-4-6` | Anthropic | Runs once on a few hundred tokens, where quality shows |

## Steps

### Task 1 - Sign in to n8n

The first time you open n8n it asks you to create an owner account. It is local
to your playground session, not a KodeKloud login, and it disappears when the
session ends.

- Click **n8n UI** in the playground toolbar
- On **Set up owner account**, fill in an email, a first and last name, and a
  password of **at least 8 characters with one capital letter and one number**
- Click **Next**. Skip the survey and any trial or activation-key screen

> **Why:** n8n rejects a weak password without saying much, so **Next** appears
> to do nothing. Check that rule first if you get stuck here.

### Task 2 - Import the workflow from a URL

- Click **Create Workflow**
- Open the **...** menu at the top right and choose **Import from URL...**
- Paste the workflow JSON URL you were given and confirm
- The canvas fills with 15 nodes. Save it

> **Why:** the URL has to return the JSON body itself. A GitHub file page, a
> shared-drive preview or a file-collection page returns HTML, and n8n reports a
> parse error rather than a network one - so the message points at the file when
> the problem is the link. If in doubt, open the URL in a browser tab: you should
> see raw JSON, not a page.

### Task 3 - Add your KodeKey as one credential

- Click **KodeKeys** in the playground toolbar to get your key. If you do not
  have one, go to <https://kodekloud.com/ai-playgrounds/kodekey>, click
  **Launch now**, then **Start Playground**, and copy the key
- In n8n, open **Credentials** > **Create Credential**, search **OpenAI**
- **API Key:** your key
- **Base URL:** `https://api.ai.kodekloud.com/v1`
- Leave **Organization ID (optional)** empty, **Add Custom Header** off, and
  **Allowed HTTP Request Domains** on **All**
- Wait for the green **Connection tested successfully** banner, then close with **X**

> **Why:** the **Base URL** is the only thing that makes an "OpenAI" credential
> talk to KodeKey. Leave it at the default and the credential quietly talks to
> OpenAI instead and fails with a 401. If the connection test does not go green,
> stop here - nothing downstream will work.

### Task 4 - Attach that one credential to all three model nodes

Open each of these and pick the credential you just made:

- `Parse CV Model`
- `Job Ad Model`
- `Writer Model`

> **Why:** the import carries no credentials - those are per-user and never
> travel in the file - so each node shows *Select credential* until you do this.
> All three take the **same** one, and that is the whole point of the project:
> three vendors, one key. While you are in the first node, open the **Model**
> dropdown and look at the list; every model there is reachable with the key you
> just pasted.

### Task 5 - Publish it and open the page

- Click **Publish**
- Open the `Web UI` node and copy its **Production URL**, then fix the host. n8n
  prints `http://0.0.0.0:5678/webhook/resumeradar`, and `0.0.0.0` is the address
  it binds to inside its container. Keep the path, use the host from your
  address bar:

```text
https://<your-playground-host>/webhook/resumeradar
```

- Upload a CV and paste a job ad. If you would rather not use your own:
  - Sample CV (PDF): https://collection.cloudinary.com/db3ogkhvu/697cd71d2e1f7f86f4b9626d1c4644d5
  - Sample job ad:

```text
Platform Engineer
Fintech, remote within GMT+2 to GMT+8

We run a payments platform on Kubernetes and we are hiring one more engineer to
own the deployment path from commit to production.

What you must have
- Kubernetes in production, not just in a course
- Terraform
- Go
- At least 5 years writing backend services

Nice to have
- Observability work: tracing, SLOs, real on-call experience
- Python
- Postgres at scale

What the job looks like
You will own the release pipeline, the infrastructure modules every team
depends on, and the on-call rotation for the platform itself. Roughly half
your week is code, half is unblocking other engineers.
```

> **Why:** a webhook workflow has no input until a request arrives, so **Execute
> Workflow** only parks it waiting for the test URL - publishing is what puts the
> real URL up. Publish again after every later change; the production URL serves
> the version you published, not what is on your canvas.

### Task 6 - Read what you just imported

Open these four nodes and look at what they do. This is the part worth your time.

- **`Intake`** - hands `{ cv, job_ad }` to everything downstream. Nothing after
  it knows whether the CV came from an upload or from a string, which is why the
  same pipeline can sit behind a web page or a manual trigger
- **`Score`** - plain JavaScript, no model. It matches whole words on purpose:
  with substring matching, `django` would satisfy a requirement for `go`
- **`Tailor`** - read the prompt. One hard rule does the heavy lifting: never add
  a title, date, tool or achievement that is not in the CV
- **`Build Report`** - note the `esc` helper. The job ad was typed by whoever
  uses the page, so its text is escaped before it reaches a browser

> **Why:** two of the three nodes that make this trustworthy run no model at all.
> The percentage is arithmetic and the safety is a prompt rule plus an escaper -
> knowing which parts are the model's judgement and which are not is the
> difference between using this and trusting it.

### Task 7 - Change one model and compare

- Note the current result for your CV and job ad
- Open `Writer Model` and pick a different model - any vendor in the list
- **Publish** again, reload the page, and submit the same CV and job ad
- Read the two rewritten CVs side by side

> **Why:** same workflow, same credential, same key. Comparing two vendors on
> your own real task cost you one dropdown, not a second signup, a second API key
> and a second bill. Check the new one against the rule as well: some models
> follow "invent nothing" more reliably than others, and you can only see that on
> your own input.

## Validation

With the workflow published, check the page is being served and typed correctly:

```bash
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" \
  "https://<your-playground-host>/webhook/resumeradar"
```

Expected result:

- [ ] The command above prints `200 text/html; charset=utf-8`
- [ ] Opening that URL in a browser shows the ResumeRadar form, not JSON
- [ ] All three model nodes show your credential, and none shows *Select credential*
- [ ] Submitting the sample CV and job ad returns a report on the same page, without a reload
- [ ] The score reads **67%**, with **Go** as the only gap and **Python** as a covered nice-to-have
- [ ] The rewritten CV still contains the p99 latency figure, the nine containerised services and the team of twelve
- [ ] The rewritten CV claims no Go experience anywhere
- [ ] After Task 7, the credit line names a different writing model

If the page returns n8n's 404 JSON, the workflow is not published. If it returns
`200` with an empty body, a branch does not end in a **Respond to Webhook** node.

## References & further learning

- [n8n documentation](https://docs.n8n.io/)
- [n8n Webhook node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)
- [n8n Respond to Webhook node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.respondtowebhook/)
- [KodeKey playground](https://kodekloud.com/ai-playgrounds/kodekey) - create and manage your key
- KodeKloud course: <!-- add the relevant AI/automation course name + link -->
- KodeKloud notes / lab: <!-- add link -->
```
