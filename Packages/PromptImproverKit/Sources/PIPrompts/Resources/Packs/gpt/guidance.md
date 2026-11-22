The prompt will be read by a current OpenAI model (the GPT-6 family), in ChatGPT, through the API, or in Codex.

These models are concise and direct by default. Do not add "be concise" or "be brief" out of habit; ask for length or depth only when the person wants something other than a short, direct answer, and say which (a detailed walkthrough, a one-paragraph summary, a full draft).

State the outcome and where the task ends. When intent is unclear, GPT tends to propose a next step and wait for confirmation. If the person wants finished work, the prompt should describe the finished result, say that reasonable, reversible assumptions are fine and should be stated, and name the few decisions that should come back to the person. If they only want options or a plan, say that instead.

Say who the result is for. When the output is something to be sent or published (an email, a post, a document), name the audience and what they already know, so the model supplies the background that audience needs. When the task is editing existing text, say to preserve the author's wording and content and to change only what was asked.

For long or multi-part work, ask for a self-contained final answer: it should make sense to someone who did not follow the intermediate steps, without shorthand carried over from the model's working.

Keep the register plain. Clear sentences that give the goal, the context, the constraints and the expected output work better than emphatic or repeated instructions; these models do well with high-level guidance and a clear goal. Leave out "think step by step" and requests for visible reasoning, since reasoning depth is a setting on the model, and do not mention sampling settings such as temperature.

Structure in proportion. A short request should stay a short paragraph. For longer prompts, mark the parts with Markdown headings and use XML-style tags to show where supplied material begins and ends. In a system or developer prompt the usual order is identity, instructions, examples, then context, with reference material near the end; keep examples and variables as given.

For coding tasks, describe the conventions that matter in this codebase and the behaviour existing callers rely on: when to reuse existing code, how narrowly to scope the change, and whether tests are wanted. Ask for readable code rather than clever or compressed code, and for a check that the requested outcome works.

For interfaces and visual work, name the visual style, the kind of imagery and the typography wanted, and say that interface text should be limited to what people need to know or do. For image generation in ChatGPT, describe the picture itself (subject, setting, style, composition, lighting) and any text that must appear in it.
