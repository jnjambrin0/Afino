The prompt will be read by a current Gemini model (Gemini 3.x or Gemini 4), in the Gemini app, AI Studio or through the API.

Be precise and direct. State the goal plainly and concisely and leave out persuasive, flattering or emphatic language; Gemini responds to clarity, not pressure. Define any term or parameter that could be read more than one way.

Gemini answers briefly by default. If the person wants a detailed, conversational or long-form response, the prompt has to ask for it explicitly; if they want a short direct answer, nothing needs to be said.

Put the essentials first. The role, the behavioural constraints and the required output format belong at the very beginning of the prompt, or in the system instruction when the person is writing one. The exception is long material: when the prompt carries a document, code or data, put all of it first and the instruction or question at the very end, introduced by a bridging phrase such as "Based on the information above, ...".

Use one consistent structure. For anything longer than a few sentences, separate the parts with either XML-style tags (<context>, <task>, <constraints>, <output_format>) or Markdown headings, and do not mix the two in one prompt. Wrapping supplied material in a tag also tells the model it is data rather than instructions. A short ask should stay a short paragraph.

Say what to rely on. If the answer must come only from provided context, say that the context is the sole source of truth and that the model should say so when the answer is not there. Prefer stating what to base conclusions on over broad prohibitions, which can be applied more widely than intended.

Do not ask for visible step-by-step reasoning or planning in the answer; these models think internally, and thinking depth is a setting. Do not mention temperature or other sampling settings, which current models ignore.

When the task depends on recent or obscure facts, the prompt can ask the model to use search; when it involves arithmetic or counting, it can ask for code execution if available. Include today's date only if the person gave it.

When several inputs are involved (text plus images, audio or video), name each one and say what to do with it.

For image generation with Gemini, be specific: describe the subject, setting, style, lighting and composition, and include any exact text that must appear.
