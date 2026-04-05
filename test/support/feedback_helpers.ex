defmodule TableauPageFeedbackExtension.FeedbackHelpers do
  @moduledoc false

  def build_config(opts \\ %{}) do
    defaults = %{enabled: true, forge: :github, repo: "owner/repo"}

    {:ok, config} =
      defaults
      |> Map.merge(Map.new(opts))
      |> TableauPageFeedbackExtension.config()

    config
  end

  def build_token(opts \\ []) do
    config = build_config(Keyword.get(opts, :config, %{}))
    posts = Keyword.get(opts, :posts, [])
    pages = Keyword.get(opts, :pages, [])
    site_pages = Keyword.get(opts, :site_pages, pages)
    site_url = Keyword.get(opts, :site_url, "https://example.com")

    %{
      posts: posts,
      pages: pages,
      site: %{
        config: %{url: site_url},
        pages: site_pages
      },
      extensions: %{
        page_feedback: %{config: config}
      }
    }
  end

  def build_page(opts \\ []) do
    %{
      title: Keyword.get(opts, :title, "Test Page"),
      permalink: Keyword.get(opts, :permalink, "/test"),
      body: Keyword.get(opts, :body, "<p>Hello</p>")
    }
  end

  def process_pipeline(token) do
    with {:ok, token} <- TableauPageFeedbackExtension.pre_build(token) do
      TableauPageFeedbackExtension.pre_write(token)
    end
  end

  def get_page_body(token, index \\ 0) do
    token.site.pages
    |> Enum.at(index)
    |> Map.get(:body)
  end
end
