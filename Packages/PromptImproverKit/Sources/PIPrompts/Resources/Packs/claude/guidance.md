The prompt will be read by a current Claude model (the Claude 5 family: Fable, Opus, Sonnet or Haiku), in the Claude apps, through the API, or in a coding agent such as Claude Code.

Claude follows instructions precisely and literally, so say exactly what is wanted and how far to go. It does what the prompt asks rather than guessing at unstated ambitions: if the person wants a thorough, fully featured result, the prompt should ask for that; if they want suggestions only, or changes actually made, it should say which. Words like "never" and "always" are treated as absolute, so state real limits with their scope and reason ("ask before deleting files" rather than "never delete files") and leave the rest out.

Explain purpose and context. Claude makes better judgement calls when it knows why something matters, who the result is for and what it will be used for; one sentence of motivation usually does more than a rule. Write as you would brief a capable colleague who is new to the situation.

Use a calm, plain register. Capitalised emphasis, "CRITICAL", repeated reminders and "do not be lazy" lines were written for older models and now cause over-application. Likewise leave out "think step by step" and requests to show reasoning: Claude decides how much to think on its own, and asking it to write out its internal reasoning can get a request declined. Asking for a brief explanation of the answer is fine.

Describe the outcome, not the procedure. Give the goal, the constraints and what done looks like, and keep numbered steps for cases where order really matters. Say what to do rather than what to avoid; for formatting, describe the form wanted ("flowing prose paragraphs") instead of banning the alternatives. When a specific look or style matters, naming the concrete patterns to avoid works better than a general "don't be generic".

Structure only when it helps. Short prompts are best as plain prose. When a prompt mixes instructions with documents, data or examples, wrap each kind of content in descriptive XML tags (<document>, <examples>, <data>) and refer to them by name. Put long material first and the instruction or question after it. Keep any examples the person gave, and keep them varied, since Claude imitates examples closely.

A role helps when it is specific and brief: one sentence at the start is enough. For system prompts, write the role, the context and the standing behaviours in prose and keep variables where they are.

For coding-agent tasks, state the goal, the relevant files or area, the constraints, how success will be checked, and whether the agent should only propose changes or make them. If the person wants it to restructure freely, say the code is theirs to redesign; if they want a minimal change, say so.

For work that runs long, say when the person wants to be consulted and that otherwise the task should be carried through to the end.
