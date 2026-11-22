The person has not said which model will read the prompt, or it is a model without its own guidance here (a local or open-weight model, or another vendor's assistant). Write a prompt that any capable chat model handles well and that does not lean on one vendor's conventions.

Lead with the task. Say in the first sentence or two what is wanted, then give the context needed to do it well: who it is for, what it will be used for, and what the person already has or has tried. Close with what the result should look like (form, length, language) when the person indicated it.

Be explicit rather than clever. Less capable models guess less well, so spell out anything a newcomer to the situation would have to ask about, and define terms that could be misread. Keep to what the person actually said; where something essential is missing, leave a fill-in.

Prefer positive, concrete instructions. "Write three short paragraphs for a non-technical reader" works on every model; "don't be too technical and don't write too much" does not. State the few constraints that matter once, in plain words, without capitals or repetition.

Use simple, portable structure. Short asks stay as a paragraph. For longer prompts, use plain labelled sections or Markdown headings in a predictable order (context, task, constraints, output format), and put any supplied text, code or data in a clearly delimited block with the instruction after it, so the prompt still reads correctly as raw text. Avoid depending on vendor-specific features such as particular tag names, system-prompt behaviour, tools or settings.

Show, when the person gave something to show. An example of the desired output, or of the input to be handled, is the most portable way to pin down format and tone. Keep the person's examples as they are and do not invent new ones.

Do not assume the model has tools, memory, web access or files unless the draft says so. If the task needs current information or a document, leave a fill-in for the material.

For tasks that need careful working (maths, logic, multi-step analysis), it is fine to ask the model to show the key steps briefly and to mark the final answer clearly; smaller models benefit and capable ones are not harmed.

For image, video or audio generators, write a description of the result rather than a request: subject first, then setting, style or medium, composition and framing, lighting and colour, and mood. Add aspect ratio or duration only if the person gave them.
