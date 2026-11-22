# Getting help

Afino is supported through [GitHub issues](https://github.com/jnjambrin0/Afino/issues), on a best-effort basis by the maintainer and contributors.

## Before you ask

1. Check the [README](README.md), especially the [FAQ](README.md#faq) and the requirements (macOS 26 or later, an Anthropic or OpenAI API key).
2. Make sure you are on the latest version: Settings › About › Check for Updates.
3. Search the existing issues, including closed ones.

## Opening an issue

Pick the form that fits:

- **Question** for help with using Afino.
- **Bug report** for something that does not work as it should.
- **Feature request** for an idea or an improvement.
- **Documentation** for something missing or wrong in the docs.

A good report includes:

- The Afino version (Settings › About) and the macOS version.
- The engine provider and preset (Settings › Engine) and the target you picked.
- What you did, what you expected, and what happened instead.
- The message the panel showed, and the details from **⌘K › Copy Details** if the panel offers them.
- Screenshots, if they help.

**Never paste an API key**, and leave out drafts or results you would not want public. If a log helps, `log show --last 10m --info --predicate 'subsystem == "com.jnjambrin0.PromptImprover"'` prints Afino's recent messages; they never contain keys or text, but read them before you share.

## Not a support request

- Security vulnerabilities: report them privately, as described in [SECURITY.md](SECURITY.md).
- Billing or account questions about your API key: ask Anthropic or OpenAI.
