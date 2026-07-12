# Qixi TSH Copilot Instructions

## Commit Messages

When generating a commit message, generate both the GitHub Desktop Summary and Description fields.

The Summary must be one Conventional Commit header:

```text
<type>(<optional-scope>): <subject>
```

- Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Use a concise English subject that accurately captures the main change and keep the header within 100 characters.
- The scope is optional. When present, use lowercase kebab-case English words.
- Do not add Markdown headings, quotation marks, invented changes, or irrelevant commentary.

For the Description, write a detailed English Conventional Commit body after a blank line:

- Summarize all meaningful changes in 3 to 8 concise English bullet points, grouped by feature or module.
- Include user-visible behavior, API/data/schema changes, deployment/configuration changes, and test or verification results when they are present in the selected changes.
- Do not enumerate every changed file. Prefer an accurate grouped summary.
- For a large initial import or generated-code change, explain the major modules introduced and the reason, rather than listing hundreds of files.
- Leave the Description empty only when the selected changes truly contain a single trivial change.

Examples:

```text
feat(group-console): sort members by role priority

- Display owners, administrators, and members by role priority
- Keep role ordering consistent after searching and paginating

fix(im-chat): hide delete action for system messages

- Hide the delete action for system notifications to avoid unsupported Tencent IM requests
- Show only the business error message when normal message deletion fails

ci(commitlint): align commit message validation rules

- Add the Conventional Commits validation workflow
- Enforce commit type, scope format, and header length rules
```
