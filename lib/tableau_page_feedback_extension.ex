defmodule TableauPageFeedbackExtension do
  @moduledoc """
  Tableau extension that generates feedback links (issues, discussions) for generated
  pages and posts.

  During the `pre_build` phase, feedback URLs are added to each page's frontmatter, and
  during the `pre_write` phase, links to `$feedback:<type>` (such as
  `$feedback:issue` or `$feedback:discussion`) are replaced in the rendered HTML.

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

  ### Configuration Options

  - `:enabled` (default `false`): Enable or disable the extension.
  - `:forge` (required): The forge type. Currently only `:github` is supported.
  - `:repo` (required): The repository slug on the forge (e.g., `"owner/site"`).
  - `:host` (optional): Override the forge host, with each forge having its own default.
  - `:title_prefix` (optional): String prepended to the page title in the feedback title.
  - `:body_suffix` (optional): Additional text appended after the page URL in the feedback
    body.

  ### Forge-Specific Configuration

  Forge-specific options are nested under the forge key (e.g., `:github`). Each feedback
  type may require its own configuration. Types with missing required config are silently
  disabled with a `Logger.warning`.

  #### GitHub (`forge: :github`)

  The default `host` for GitHub is `github.com`; this should be changed if using a GitHub
  Enterprise instance.

  Supported feedback types:

  - `:issue`: enabled by default; disable with `issue: nil`.
  - `:discussion`: disabled by default; enable by specifying the `:category`.

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

  Markers for disabled feedback types are left in place.
  """

  use Tableau.Extension, key: :page_feedback, priority: 500, enabled: false

  require Logger

  @forges %{
    github: %{
      host: "github.com",
      types: %{
        issue: %{},
        discussion: %{category: {:required, :string}}
      },
      default: %{issue: %{}}
    }
  }

  @known_forges Map.keys(@forges)

  @defaults %{
    enabled: false,
    forge: nil,
    repo: nil,
    host: nil,
    title_prefix: nil,
    body_suffix: nil
  }

  @impl Tableau.Extension
  def config(config) when is_list(config), do: config(Map.new(config))

  def config(config) do
    merged =
      @defaults
      |> Map.merge(config)
      |> config_forge_defaults()

    case validate(merged) do
      :ok -> {:ok, merged}
      {:error, _} = error -> error
    end
  end

  @impl Tableau.Extension
  def pre_build(token) do
    config = token.extensions.page_feedback.config
    site_url = token.site.config.url
    enabled_types = enabled_types(config)

    token =
      token
      |> update_collection(:posts, config, site_url, enabled_types)
      |> update_collection(:pages, config, site_url, enabled_types)

    {:ok, token}
  end

  @impl Tableau.Extension
  def pre_write(token) do
    url_map = build_url_map(token)

    {:ok, put_in(token.site.pages, Enum.map(token.site.pages, &replace_markers(&1, url_map)))}
  end

  defp config_forge_defaults(%{forge: forge} = config) when forge in @known_forges do
    Map.put(
      config,
      forge,
      Map.merge(
        forge(forge).default,
        to_map(config[forge] || %{})
      )
    )
  end

  defp config_forge_defaults(config), do: config

  defp to_map(kw) when is_list(kw), do: Map.new(kw, fn {k, v} -> {k, to_map(v)} end)
  defp to_map(v), do: v

  defp update_collection(token, key, config, site_url, enabled_types) do
    case Map.get(token, key) do
      nil ->
        token

      items ->
        Map.put(
          token,
          key,
          Enum.map(items, &put_feedback_urls(&1, config, site_url, enabled_types))
        )
    end
  end

  defp put_feedback_urls(%{feedback_urls: _} = page, _config, _site_url, _enabled_types), do: page

  defp put_feedback_urls(page, config, site_url, enabled_types) do
    case Map.get(page, :title) do
      nil ->
        page

      title ->
        Map.put(
          page,
          :feedback_urls,
          build_feedback_urls(page, title, config, site_url, enabled_types)
        )
    end
  end

  defp build_feedback_urls(page, title, config, site_url, enabled_types) do
    forge = config.forge
    forge_config = Map.get(config, forge, %{})
    host = config.host || @forges[forge].host
    full_title = if config.title_prefix, do: config.title_prefix <> title, else: title
    permalink = full_permalink(site_url, Map.get(page, :permalink, ""))

    body =
      case config.body_suffix do
        nil -> permalink
        extra -> permalink <> extra
      end

    Map.new(enabled_types, fn type ->
      type_config = Map.get(forge_config, type, %{})
      {type, build_url(forge, type, host, config.repo, full_title, body, type_config)}
    end)
  end

  defp enabled_types(config) do
    forge = config.forge
    forge_config = Map.get(config, forge, %{})

    for {type, required} <- @forges[forge].types, reduce: [] do
      acc ->
        missing = Map.keys(required) -- Map.keys(Map.get(forge_config, type, %{}))

        if missing == [] do
          [type | acc]
        else
          Logger.warning("#{type} feedback disabled: missing #{Enum.join(missing, ", ")}")
          acc
        end
    end
  end

  defp build_url(:github, :issue, host, repo, title, body, _type_config) do
    query = URI.encode_query(%{"title" => title, "body" => body})
    "https://#{host}/#{repo}/issues/new?#{query}"
  end

  defp build_url(:github, :discussion, host, repo, title, body, type_config) do
    params = %{"title" => title, "body" => body}

    params =
      case Map.get(type_config, :category) do
        nil -> params
        category -> Map.put(params, "category", category)
      end

    query = URI.encode_query(params)
    "https://#{host}/#{repo}/discussions/new?#{query}"
  end

  defp full_permalink(site_url, permalink) do
    site_url
    |> String.trim_trailing("/")
    |> Kernel.<>(permalink)
  end

  defp build_url_map(token) do
    for collection <- [:posts, :pages],
        items = Map.get(token, collection, []),
        %{permalink: permalink, feedback_urls: urls} <- items,
        into: %{} do
      {permalink, urls}
    end
  end

  defp replace_markers(page, url_map) do
    case Map.get(url_map, page.permalink) do
      nil ->
        page

      urls ->
        body =
          Enum.reduce(urls, page.body, fn {type, url}, body ->
            String.replace(body, "$feedback:#{type}", url)
          end)

        put_in(page.body, body)
    end
  end

  defp validate(config) do
    with :ok <- validate_repo(config.repo),
         :ok <- validate_forge(config.forge) do
      validate_forge_config(config.forge, config[config.forge])
    end
  end

  defp validate_repo(nil), do: {:error, ":repo is required"}
  defp validate_repo(repo) when is_binary(repo), do: :ok
  defp validate_repo(_repo), do: {:error, ":repo must be a string"}

  defp validate_forge(nil), do: {:error, ":forge is required"}

  defp validate_forge(forge) when forge in @known_forges, do: :ok
  defp validate_forge(forge), do: {:error, "unsupported forge: #{inspect(forge)}"}

  defp validate_forge_config(forge, forge_config) do
    Enum.reduce_while(@forges[forge].types, :ok, fn {type, required}, :ok ->
      forge_config
      |> Map.get(type)
      |> validate_type(type, required)
    end)
  end

  defp validate_type(nil, _type, _required), do: {:cont, :ok}
  defp validate_type(_config, _type, required) when required == %{}, do: {:cont, :ok}

  defp validate_type(type_config, type, required) do
    case validate_type_config(type, required, type_config) do
      :ok -> {:cont, :ok}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp validate_type_config(_type, required, _type_config) when required == %{}, do: :ok

  defp validate_type_config(type, required, type_config) do
    Enum.reduce_while(required, :ok, fn {key, spec}, :ok ->
      case {spec, Map.get(type_config, key)} do
        {{:required, _}, nil} -> {:halt, {:error, "#{type}.#{key} is required"}}
        {_, nil} -> {:cont, :ok}
        {{:required, expected}, value} -> validate_value(type, key, expected, value)
        {expected, value} -> validate_value(type, key, expected, value)
      end
    end)
  end

  defp validate_value(_type, _key, :string, value) when is_binary(value), do: {:cont, :ok}

  defp validate_value(type, key, expected_type, _value) do
    {:halt, {:error, "#{type}.#{key} must be a #{expected_type}"}}
  end

  defp forge(key), do: forges()[key]

  defp forges, do: @forges
end
