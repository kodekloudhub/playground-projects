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
