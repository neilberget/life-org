defmodule LifeOrg.UnitTest do
  use ExUnit.Case
  alias LifeOrg.{LinkDetector, Integrations.Decorators.WebLink}

  describe "Link Detection" do
    test "extracts URLs from text" do
      content = "Check out https://example.com and also visit https://github.com/user/repo"
      
      urls = LinkDetector.extract_urls(content)
      
      assert length(urls) == 2
      assert Enum.any?(urls, fn u -> u.url == "https://example.com" end)
      assert Enum.any?(urls, fn u -> u.url == "https://github.com/user/repo" end)
    end

    test "handles www URLs without protocol" do
      content = "Visit www.example.com for more info"
      
      urls = LinkDetector.extract_urls(content)
      
      assert length(urls) == 1
      assert hd(urls).url == "https://www.example.com"
    end

    test "validates URLs correctly" do
      assert LinkDetector.valid_url?("https://example.com")
      assert LinkDetector.valid_url?("http://example.com")
      refute LinkDetector.valid_url?("not-a-url")
      refute LinkDetector.valid_url?("ftp://example.com")
    end
  end

  describe "Web Link Decorator" do
    test "matches HTTP and HTTPS URLs" do
      assert WebLink.match_url("https://example.com")
      assert WebLink.match_url("http://example.com")
      refute WebLink.match_url("ftp://example.com")
      refute WebLink.match_url("not-a-url")
    end

    test "has correct integration properties" do
      assert WebLink.name() == "Generic Web Link"
      assert WebLink.provider() == :web
      assert WebLink.priority() == 1
      assert :fetch_metadata in WebLink.capabilities()
      assert :render_preview in WebLink.capabilities()
    end
  end
end