#!/usr/bin/env bash
set -euo pipefail

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

5. Close the panel.

### Task 11 — Configure the IF Node (Sentiment Check)

1. Go back to your Switch node. Click and drag another connector from **Output 1** (Tech Support) into empty space.
2. Search for and select the **If** node.
3. Under Conditions, set **Value 1** to:

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
