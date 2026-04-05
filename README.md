# TableauPageFeedbackExtension

[![Hex.pm][shield-hex]][hexpm] [![Hex Docs][shield-docs]][docs]
[![Apache 2.0][shield-licence]][licence] ![Coveralls][shield-coveralls]

- code :: <https://github.com/halostatue/tableau_page_feedback_extension>
- issues :: <https://github.com/halostatue/tableau_page_feedback_extension/issues>

A [Tableau][tableau] extension that generates feedback links (issues,
discussions) for pages and posts. Each displayable page gets a `feedback_urls`
map in its frontmatter, and `$feedback:issue` / `$feedback:discussion` markers
in rendered HTML are replaced with the full URLs.

## Installation

Add `tableau_page_feedback_extension` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tableau_page_feedback_extension, "~> 1.0"}
  ]
end
```

## Configuration

```elixir
config :tableau, TableauPageFeedbackExtension,
  enabled: true,
  forge: :github,
  repo: "owner/repo",
  github: [
    discussion: [category: "General"]
  ]
```

### Options

- `:forge` (required) — The forge type. Currently only `:github` is supported.
- `:repo` (required) — Repository slug (`"owner/repo"`).
- `:host` — Override the forge host. Defaults to `"github.com"`.
- `:title_prefix` — String prepended to the page title in the feedback title.
- `:body_suffix` — Additional text appended after the page URL in the feedback body.

### Forge-Specific Configuration

Forge-specific options are nested under the forge key. Types with missing
required config are disabled with a warning.

#### GitHub (`:github`)

- `:issue` — No additional configuration. Enabled by default.
- `:discussion` — Requires `:category` (the GitHub Discussions category name).

### Feedback Types by Forge

| Forge    | Types                    |
| -------- | ------------------------ |
| `:github` | `issue`, `discussion`   |

## Usage

### In Templates

The extension adds `feedback_urls` to each page's assigns:

```eex
<%= if assigns[:feedback_urls] do %>
  <a href="<%= @feedback_urls.issue %>">Report an issue</a>
  <a href="<%= @feedback_urls.discussion %>">Start a discussion</a>
<% end %>
```

### In Markdown Content

Use markers directly in content — they're replaced in the rendered HTML:

```markdown
[Report an issue]($feedback:issue)
[Start a discussion]($feedback:discussion)
```

## Semantic Versioning

TableauPageFeedbackExtension follows [Semantic Versioning 2.0][semver].

[docs]: https://hexdocs.pm/tableau_page_feedback_extension
[hexpm]: https://hex.pm/packages/tableau_page_feedback_extension
[licence]: https://github.com/halostatue/tableau_page_feedback_extension/blob/main/LICENCE.md
[semver]: https://semver.org/
[shield-coveralls]: https://img.shields.io/coverallsCoverage/github/halostatue/tableau_page_feedback_extension?style=for-the-badge
[shield-docs]: https://img.shields.io/badge/hex-docs-purple.svg?style=for-the-badge
[shield-hex]: https://img.shields.io/hexpm/v/tableau_page_feedback_extension.svg?style=for-the-badge
[shield-licence]: https://img.shields.io/hexpm/l/tableau_page_feedback_extension.svg?style=for-the-badge
[tableau]: https://hexdocs.pm/tableau
