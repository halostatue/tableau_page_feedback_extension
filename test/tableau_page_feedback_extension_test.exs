defmodule TableauPageFeedbackExtensionTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import TableauPageFeedbackExtension.FeedbackHelpers

  describe "config/1" do
    test "accepts keyword list" do
      assert {:ok, %{forge: :github}} =
               TableauPageFeedbackExtension.config(forge: :github, repo: "o/r")
    end

    test "accepts map" do
      assert {:ok, %{forge: :github}} =
               TableauPageFeedbackExtension.config(%{forge: :github, repo: "o/r"})
    end

    test "defaults enabled to false" do
      assert {:ok, %{enabled: false}} =
               TableauPageFeedbackExtension.config(%{forge: :github, repo: "o/r"})
    end

    test "rejects missing forge" do
      assert {:error, ":forge is required"} =
               TableauPageFeedbackExtension.config(%{repo: "o/r"})
    end

    test "rejects unsupported forge" do
      assert {:error, "unsupported forge: :gitlab"} =
               TableauPageFeedbackExtension.config(%{forge: :gitlab, repo: "o/r"})
    end

    test "rejects missing repo" do
      assert {:error, ":repo is required"} =
               TableauPageFeedbackExtension.config(%{forge: :github})
    end

    test "rejects non-string repo" do
      assert {:error, ":repo must be a string"} =
               TableauPageFeedbackExtension.config(%{forge: :github, repo: 123})
    end

    test "defaults forge key from schema when omitted" do
      {:ok, config} = TableauPageFeedbackExtension.config(%{forge: :github, repo: "o/r"})
      assert config.github == %{issue: %{}}
    end

    test "converts forge-specific keyword lists to maps" do
      {:ok, config} =
        TableauPageFeedbackExtension.config(
          forge: :github,
          repo: "o/r",
          github: [discussion: [category: "General"]]
        )

      assert config.github == %{issue: %{}, discussion: %{category: "General"}}
    end

    test "validates discussion.category is required when discussion config present" do
      assert {:error, "discussion.category is required"} =
               TableauPageFeedbackExtension.config(%{
                 forge: :github,
                 repo: "o/r",
                 github: %{discussion: %{}}
               })
    end

    test "validates discussion.category must be a string" do
      assert {:error, "discussion.category must be a string"} =
               TableauPageFeedbackExtension.config(%{
                 forge: :github,
                 repo: "o/r",
                 github: %{discussion: %{category: 123}}
               })
    end

    test "accepts valid discussion config" do
      assert {:ok, _} =
               TableauPageFeedbackExtension.config(%{
                 forge: :github,
                 repo: "o/r",
                 github: %{discussion: %{category: "General"}}
               })
    end

    test "passes validation when no forge-specific config" do
      assert {:ok, _} =
               TableauPageFeedbackExtension.config(%{forge: :github, repo: "o/r"})
    end
  end

  describe "pre_build/1" do
    test "adds feedback_urls to posts" do
      page = build_page(title: "My Post", permalink: "/posts/my-post")
      token = build_token(posts: [page])

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [post] = result.posts
      assert %{issue: _} = post.feedback_urls
    end

    test "adds feedback_urls to pages" do
      page = build_page(title: "About", permalink: "/about")
      token = build_token(pages: [page])

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [p] = result.pages
      assert %{issue: _} = p.feedback_urls
    end

    test "skips pages without title" do
      page = %{permalink: "/no-title", body: ""}
      token = build_token(pages: [page])

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [p] = result.pages
      refute Map.has_key?(p, :feedback_urls)
    end

    test "preserves existing feedback_urls" do
      page = Map.put(build_page(), :feedback_urls, %{issue: "custom"})
      token = build_token(pages: [page])

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [p] = result.pages
      assert p.feedback_urls == %{issue: "custom"}
    end

    test "generates issue URL with title and permalink in body" do
      page = build_page(title: "Hello", permalink: "/hello")
      token = build_token(posts: [page])

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [post] = result.posts
      url = post.feedback_urls.issue
      assert url =~ "https://github.com/owner/repo/issues/new?"
      assert url =~ "title=Hello"
      assert url =~ URI.encode_www_form("https://example.com/hello")
    end

    test "applies title_prefix" do
      page = build_page(title: "Hello")
      token = build_token(posts: [page], config: %{title_prefix: "Re: "})

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [post] = result.posts
      assert post.feedback_urls.issue =~ URI.encode_www_form("Re: Hello")
    end

    test "applies body_suffix" do
      page = build_page(title: "Hello", permalink: "/hello")
      token = build_token(posts: [page], config: %{body_suffix: "\n\n---\nExtra"})

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [post] = result.posts
      assert post.feedback_urls.issue =~ URI.encode_www_form("https://example.com/hello\n\n---\nExtra")
    end

    test "uses custom host" do
      page = build_page(title: "Hello")
      token = build_token(posts: [page], config: %{host: "git.example.com"})

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [post] = result.posts
      assert post.feedback_urls.issue =~ "https://git.example.com/"
    end

    test "generates discussion URL with category" do
      page = build_page(title: "Hello", permalink: "/hello")

      token =
        build_token(
          posts: [page],
          config: %{github: %{discussion: %{category: "General"}}}
        )

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [post] = result.posts
      url = post.feedback_urls.discussion
      assert url =~ "https://github.com/owner/repo/discussions/new?"
      assert url =~ "category=General"
    end

    test "only generates issue when discussion config missing" do
      page = build_page(title: "Hello")
      token = build_token(posts: [page])

      log =
        capture_log(fn ->
          {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

          [post] = result.posts
          assert Map.has_key?(post.feedback_urls, :issue)
          refute Map.has_key?(post.feedback_urls, :discussion)
        end)

      assert log =~ "discussion feedback disabled: missing category"
    end

    test "logs warning once for disabled types" do
      pages = [
        build_page(title: "One", permalink: "/one"),
        build_page(title: "Two", permalink: "/two")
      ]

      token = build_token(posts: pages)

      log =
        capture_log(fn ->
          {:ok, _} = TableauPageFeedbackExtension.pre_build(token)
        end)

      # Should appear exactly once, not per-page
      assert length(String.split(log, "discussion feedback disabled")) == 2
    end

    test "handles nil posts collection" do
      token = Map.delete(build_token(), :posts)

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      refute Map.has_key?(result, :posts)
    end

    test "strips trailing slash from site URL" do
      page = build_page(title: "Hello", permalink: "/hello")
      token = build_token(posts: [page], site_url: "https://example.com/")

      {:ok, result} = TableauPageFeedbackExtension.pre_build(token)

      [post] = result.posts
      assert post.feedback_urls.issue =~ URI.encode_www_form("https://example.com/hello")
      refute post.feedback_urls.issue =~ URI.encode_www_form("https://example.com//hello")
    end
  end

  describe "pre_write/1" do
    test "replaces $feedback:issue markers" do
      page = build_page(title: "Hello", permalink: "/hello", body: ~s(<a href="$feedback:issue">Report</a>))

      token =
        build_token(
          posts: [page],
          site_pages: [%{permalink: "/hello", body: ~s(<a href="$feedback:issue">Report</a>)}]
        )

      {:ok, result} = process_pipeline(token)

      body = get_page_body(result)
      assert body =~ "https://github.com/owner/repo/issues/new?"
      refute body =~ "$feedback:issue"
    end

    test "replaces $feedback:discussion markers" do
      page = build_page(title: "Hello", permalink: "/hello", body: ~s(<a href="$feedback:discussion">Discuss</a>))

      token =
        build_token(
          posts: [page],
          config: %{github: %{discussion: %{category: "General"}}},
          site_pages: [%{permalink: "/hello", body: ~s(<a href="$feedback:discussion">Discuss</a>)}]
        )

      {:ok, result} = process_pipeline(token)

      body = get_page_body(result)
      assert body =~ "https://github.com/owner/repo/discussions/new?"
      refute body =~ "$feedback:discussion"
    end

    test "leaves $feedback:discussion marker when discussion disabled" do
      page = build_page(title: "Hello", permalink: "/hello")

      token =
        build_token(
          posts: [page],
          site_pages: [%{permalink: "/hello", body: ~s(<a href="$feedback:discussion">Discuss</a>)}]
        )

      log =
        capture_log(fn ->
          {:ok, result} = process_pipeline(token)

          body = get_page_body(result)
          assert body =~ "$feedback:discussion"
        end)

      assert log =~ "discussion feedback disabled"
    end

    test "replaces multiple markers in same page" do
      body = ~s(<a href="$feedback:issue">Issue</a> <a href="$feedback:discussion">Discuss</a>)
      page = build_page(title: "Hello", permalink: "/hello", body: body)

      token =
        build_token(
          posts: [page],
          config: %{github: %{discussion: %{category: "General"}}},
          site_pages: [%{permalink: "/hello", body: body}]
        )

      {:ok, result} = process_pipeline(token)

      body = get_page_body(result)
      refute body =~ "$feedback:issue"
      refute body =~ "$feedback:discussion"
      assert body =~ "issues/new?"
      assert body =~ "discussions/new?"
    end

    test "leaves pages without feedback_urls unchanged" do
      page = %{permalink: "/no-title", body: "unchanged"}

      token =
        build_token(
          pages: [page],
          site_pages: [%{permalink: "/no-title", body: "unchanged"}]
        )

      {:ok, result} = process_pipeline(token)

      assert get_page_body(result) == "unchanged"
    end
  end
end
