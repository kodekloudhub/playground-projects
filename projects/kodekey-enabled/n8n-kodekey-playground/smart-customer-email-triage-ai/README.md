# Smart Customer Email Triage with AI

**Level:** advanced  ·  **Playground:** N8N | KodeKey Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-n8n)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A global customer operations team receives hundreds of support emails daily in their primary customer inbox. Currently, support representatives manually read each incoming message, attempt to categorize the request (e.g., Billing, Tech Support, or Sales), evaluate customer sentiment, and manually assign or reply to the email. During peak hours, frustrated customers wait hours for a simple acknowledgment, leading to declining Customer Satisfaction (CSAT) scores and agent burnout from repetitive daily tasks.

The Customer Operations team has mandated a shift to an AI-driven, zero-touch email sorting system. You have been tasked with building an automated workflow in n8n. The goal is to ensure that whenever a new unread email arrives in the monitored inbox, n8n automatically triggers an AI model to parse the email body, classify its category and sentiment as structured data, route the message logically, and immediately dispatch a personalized, empathetic response to frustrated customers without human intervention.

## What you'll build
Starting from a clean workspace in n8n, you must establish an end-to-end automated email classification and response workflow. You will be provided with an n8n instance and access to an LLM API key via KodeKeys. To connect your email, you will use your own Google account to generate a secure App Password. You must configure IMAP and SMTP credentials in n8n, construct a visual workflow connecting Email and AI nodes, implement routing logic using Switch and IF nodes, and test the full lifecycle of an incoming customer inquiry.

## Learning objectives
By the end you will be able to:
- Authenticate and configure external email triggers (IMAP) and actions (SMTP) within n8n using App Passwords.
- Connect an n8n workflow to an LLM provider to process and structure raw text data.
- Utilize JavaScript within an n8n Code node to parse and sanitize AI-generated JSON payloads.
- Design advanced conditional routing logic using Switch and IF nodes based on dynamic variables.

## Prerequisites
- Playground: **n8n** (open it before starting)
- A personal Gmail account to use for testing

---

## Steps

### Task 1 — Get Your API Keys via KodeKeys

1. Navigate to https://kodekloud.com/ai-playgrounds/kodekey in your browser.
2. Click the **Launch now** button, then select **Start Playground**.
3. Select your designated AI model from the available options.
4. Copy both the **Base URL** and the **API Key** provided. Keep these handy.

### Task 2 — Register and Activate n8n

1. Open the n8n editor by clicking the n8n UI button in your lab environment.
2. Complete the registration form with a valid personal email address, your first and last name, and a secure password.
3. Click **Get started**, then click **Send me a free license key**.
4. Go to your email and copy the license key.
5. On the n8n UI, navigate to **Settings > Usage and plan**. 
6. Click **Enter activation key**, paste the license key you just copied, and click **Activate**.

### Task 3 — Generate a Gmail App Password

1. Open a new browser tab and go to your Google Account Security settings: https://myaccount.google.com/security
2. Ensure you are logged into the `@gmail.com` account you want to use for this lab.
3. Under "How you sign in to Google," ensure **2-Step Verification** is turned ON. (This is required to use App Passwords).
4. Use the search bar at the top of the Google Account page and search for **App passwords**.
5. Under "App name," type `n8n Lab` and click **Create**.
6. Google will generate a 16-letter password. Copy this password and keep it open in a notepad.

### Task 4 — Create the Workflow & Connect the IMAP Email Trigger

1. Switch back to your n8n tab. Click the **+** icon in the top-left corner of the sidebar and select **Workflow** from the dropdown menu (or click **Start from scratch** in the center).
2. Click the **+ Add first step** button on the canvas.
3. Search for `email` and select the **Email Trigger (IMAP)** node.
4. Under *Credential to connect with*, select **Create New Credential**.
5. Fill in the credential details:
   - **User:** Your full Gmail address (e.g., your.email@gmail.com)
   - **Password:** The 16-letter App Password you just generated.
   - **Host:** `imap.gmail.com`
   - **Port:** `993`
   - **SSL/TLS:** Toggle this **ON**.
6. Click **Save** and close the credential window.
7. In the node settings, ensure **Mailbox Name** is set to `INBOX` and the **Action** dropdown is set to `Mark as Read`.
8. Close the settings panel.

### Task 5 — Add the AI Brain & Connect KodeKeys

1. Hover over the right side of the Email Trigger node and click the **+** icon.
2. Search for `OpenAI` and select the **OpenAI** node.
3. Select **Message a model** under the *Text Actions* category.
4. Under *Credential to connect with*, click the dropdown and select **Create New Credential**.
5. Paste your KodeKey API Key into the API Key field and your KodeKey Base URL into the Base URL field. Click **Save** and close the window.
6. Under the *Model* section, click the **Choose...** dropdown and select the specific model you launched in KodeKeys earlier.
7. Under the *Messages* section, ensure **Type** is set to `Text` and **Role** is set to `User`.
8. In the Prompt field, click the **Expression** tab and paste this exact prompt:

```plaintext
Analyze this email: {{ $json.textPlain }}. Return ONLY a raw JSON object with two keys: "category" (must be Billing, Tech Support, or Sales) and "sentiment" (must be Positive, Neutral, or Frustrated).
```

9. Scroll down to the bottom, click **Add option**, select **Output Format**, and set it to `JSON Object`.
10. Close the settings panel.

### Task 6 — Parse the AI JSON Output

1. Click the **+** icon on the right side of the OpenAI node.
2. Search for `Code` and select the **Code** node.
3. From the actions list, select **Code in JavaScript**.
4. Set the Mode dropdown to **Run Once for All Items**.
5. Replace the default code with this exact snippet:

```javascript
const data = $input.all()[0].json;
let rawText = "";

if (Array.isArray(data.output) && data.output.length > 0) {
    rawText = data.output[0].content[0].text;
} else if (data.message && data.message.content) {
    rawText = data.message.content; 
} else if (Array.isArray(data.content)) {
    rawText = data.content[0].text;
} else {
    rawText = data.content || data.text || String(data.output) || "";
}

rawText = rawText.replace(/```json/gi, "").replace(/```/g, "").trim();

return { json: JSON.parse(rawText) };
```

6. Close the panel.

### Task 7 — Configure the Switch Node (Routing Logic)

1. Click the **+** icon next to the Code node. Search for and select the **Switch** node.
2. Set the Mode to **Rules**.
3. Add the first routing rule:
   - **Value 1:** `{{ $json.category }}`
   - **Value 2:** `Billing`
4. Click **Add Routing Rule** again:
   - **Value 1:** `{{ $json.category }}`
   - **Value 2:** `Tech Support`
5. Click **Add Routing Rule** one more time:
   - **Value 1:** `{{ $json.category }}`
   - **Value 2:** `Sales`
6. Close the panel.

### Task 8 — Configure the Billing Action (Forwarding)

1. Hover over the Switch node, click and drag the connector from **Output 0** into empty space.
2. Search for `Send Email` and select the **Send Email** node. Select Action: **Send an email**.
3. Under *Credential to connect with*, select **+ Create New Credential**.
4. Fill in the SMTP details:
   - **User:** Your full Gmail address
   - **Password:** Your 16-letter App Password
   - **Host:** `smtp.gmail.com`
   - **Port:** `587`
   - **SSL/TLS:** Toggle this **OFF**.
5. Click **Save** and close the credential window. Ensure Operation is set to **Send**.
6. Configure the email details:
   - **From Email:** Your full Gmail address
   - **To Email:** Type a test forwarding address (e.g., your own email address).
   - **Subject:** `[Automated Forward] New Billing Inquiry`
   - **Email Format:** Change it from HTML to `Text`.
   - **Text:** Click the Expression tab and paste the following:

```plaintext
{{ $('Email Trigger (IMAP)').item.json.textPlain || $('Email Trigger (IMAP)').item.json.textHtml }}
```

7. Close the panel.

### Task 9 — Configure the Sales Action (Forwarding)

1. Hover over the Switch node, click and drag the connector from **Output 2** into empty space.
2. Search for `Send Email` and select the **Send Email** node. Select Action: **Send an email**.
3. Under *Credential to connect with*, select your existing SMTP credential. Ensure Operation is set to **Send**.
4. Configure the email details:
   - **From Email:** Your full Gmail address
   - **To Email:** Type a test forwarding address (e.g., your own email address).
   - **Subject:** `[Automated Forward] New Sales Inquiry`
   - **Email Format:** Change it to `Text`.
   - **Text:** Click the Expression tab and paste the following:

```plaintext
{{ $('Email Trigger (IMAP)').item.json.textPlain || $('Email Trigger (IMAP)').item.json.textHtml }}
```

5. Close the panel.

### Task 10 — Configure the Tech Support Action (Forwarding)

1. Go back to your Switch node. Hover over **Output 1**, click and drag a new connector into empty space.
2. Search for `Send Email` and select the **Send Email** node. Select Action: **Send an email**.
3. Under *Credential to connect with*, select your existing SMTP credential. Ensure Operation is set to **Send**.
4. Configure the forwarding email:
   - **From Email:** Your full Gmail address
   - **To Email:** Type a test forwarding address representing the tech team (e.g., your own email).
   - **Subject:** `[Automated Forward] New Tech Support Ticket`
   - **Email Format:** Change it to `Text`.
   - **Text:** Click the Expression tab and paste the following:

```plaintext
{{ $('Email Trigger (IMAP)').item.json.textPlain || $('Email Trigger (IMAP)').item.json.textHtml }}
```

5. Close the panel.

### Task 11 — Configure the IF Node (Sentiment Check)

1. Go back to your Switch node. Click and drag another connector from **Output 1** (Tech Support) into empty space.
2. Search for and select the **If** node.
3. Under Conditions, set **Value 1** to:

```plaintext
{{ $json.sentiment }}
```

4. Set the condition operator to **Equal**.
5. Set **Value 2** to `Frustrated`.
6. Close the panel.

### Task 12 — Configure the Frustrated Tech Support Action (Escalation Auto-Reply)

1. Drag the connector from the IF node's **true** output into empty space.
2. Search for `Send Email` and select the **Send Email** node. Select Action: **Send an email**.
3. Under *Credential to connect with*, select your SMTP credential. Ensure Operation is set to **Send**.
4. Configure the auto-reply:
   - **From Email:** Your full Gmail address
   - **To Email:** Click the Expression tab and paste: `{{ $('Email Trigger (IMAP)').item.json.from }}`
   - **Subject:** Click the Expression tab and paste: `Re: {{ $('Email Trigger (IMAP)').item.json.subject }}`
   - **Email Format:** Change it to `Text`.
   - **Text:** Type this empathetic response:

```plaintext
Hi there, I am an automated assistant. I detected that you are experiencing a frustrating technical issue. I have escalated this ticket to our on-call manager for priority review. We will reach out shortly.
```

5. Close the panel.

### Task 13 — Configure the Standard Tech Support Action (Auto-Reply)

1. Drag the connector from the IF node's **false** output into empty space.
2. Search for `Send Email` and select the **Send Email** node. Select Action: **Send an email**.
3. Under *Credential to connect with*, select your SMTP credential. Ensure Operation is set to **Send**.
4. Configure the standard auto-reply:
   - **From Email:** Your full Gmail address
   - **To Email:** Click the Expression tab and paste: `{{ $('Email Trigger (IMAP)').item.json.from }}`
   - **Subject:** Click the Expression tab and paste: `Re: {{ $('Email Trigger (IMAP)').item.json.subject }}`
   - **Email Format:** Change it to `Text`.
   - **Text:** Type this standard response:

```plaintext
Hi there, we have received your technical support request. A team member will review it and get back to you within 24 hours.
```

5. Close the panel.

### Task 14 — Publish and Activate

1. At the top left of the screen, click the default workflow name ("My workflow") and rename it to `Smart Customer Email Triage`.
2. In the top right corner of the screen, click the **Publish** button. This saves your workflow and activates it immediately.

### Task 15 — Test Your Triage Workflow (See It In Action)

Now that your workflow is active, it will automatically listen for new, unread emails. Open a different email account and compose a new message addressed to the Gmail account connected to n8n. 

> **Important:** Make sure you haven't viewed the email in the receiving inbox, otherwise n8n will ignore it!

1. **Test the Billing Route:** Send an email with the subject `Invoice Question` and the body: *Hi, I need help understanding a charge on my recent invoice.*
2. **Test the Frustrated Tech Support Route:** Send an email with the subject `Broken System` and the body: *This software is completely broken! I am extremely frustrated and nothing is working. I need help right now!*
3. **Test the Standard Tech Support Route:** Send an email with the subject `Password Reset` and the body: *Hello, I forgot my password and cannot seem to log in. Can someone assist me?*
4. **View the Logs:** Go back to your n8n dashboard and click the **Executions** tab at the top of the screen. You can click on any of the recent successful runs to see exactly how the AI categorized your text and watch the path the data took through your Switch node.

---

## Validation

Verify that your workflow routes messages appropriately based on your tests in Task 15.

- [ ] Is your OpenAI API Credential successfully authenticated and active inside n8n?
- [ ] Are your IMAP and SMTP credentials fully authenticated and connected in n8n?
- [ ] Does the OpenAI Node consistently parse raw email text and return a valid JSON payload containing both `category` and `sentiment` keys?
- [ ] Does your Switch Node successfully route Billing emails down a separate branch from Tech Support emails?
- [ ] Does your IF Node correctly differentiate between a `Frustrated` sentiment and a `Neutral` or `Positive` sentiment?
- [ ] **The Final E2E Test:** If you send a new unread email from an external inbox to your connected Gmail account containing a frustrated technical support request (e.g., "My system is completely down and I am losing money, fix this now!"), does the workflow trigger automatically, process the AI classification, and deliver an empathetic auto-reply back to the sender's inbox within a few minutes without manual execution?

## References & further learning
- n8n Nodes Documentation: https://docs.n8n.io/integrations/
- n8n OpenAI Integration Guide: https://docs.n8n.io/integrations/builtin/credentials/openai/
- Gmail IMAP/SMTP Setup Guide (App Passwords): https://support.google.com/accounts/answer/185833
- KodeKloud course: AI Agents Fundamentals: https://kodekloud.com/courses/ai-agents-fundamentals/
